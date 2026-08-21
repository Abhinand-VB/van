import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van_core/van_core.dart';

/// Builds the events table exactly as schema v1 had it: no `session_id`.
///
/// Written out by hand rather than generated, because the point of the test is
/// to prove the upgrade works against the shape that is actually sitting on
/// the phone.
Database v1DatabaseWith(List<({EventType type, int ts, String payload})> rows) {
  final db = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        ts_utc INTEGER NOT NULL,
        type TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}'
      );
    ''')
    ..execute('CREATE INDEX idx_events_ts ON events (ts_utc);')
    ..execute('CREATE INDEX idx_events_type ON events (type);');

  for (final row in rows) {
    db.execute(
      'INSERT INTO events (ts_utc, type, payload_json) VALUES (?, ?, ?)',
      [row.ts, row.type.name, row.payload],
    );
  }

  // Drift decides whether to upgrade from this.
  db.execute('PRAGMA user_version = 1');
  return db;
}

/// Index names currently on the events table.
List<String> indexesOn(Database db) => db
    .select('PRAGMA index_list(events)')
    .map((r) => r['name'] as String)
    .toList();

void main() {
  ({EventType type, int ts, String payload}) event(
    EventType type,
    int ts, [
    Map<String, Object?> payload = const {},
  ]) => (type: type, ts: ts, payload: jsonEncode(payload));

  group('upgrading a v1 database', () {
    test('lifts sessionId out of the payload and indexes it', () async {
      final raw = v1DatabaseWith([
        event(EventType.sessionPlanned, 1000, {'sessionId': 's1', 'x': 1}),
        event(EventType.nudgeScheduled, 2000, {'sessionId': 's1'}),
        event(EventType.sessionPlanned, 3000, {'sessionId': 's2'}),
      ]);
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final found = await EventRepo(
        db,
        FakeClock(DateTime.utc(2026, 8, 21)),
      ).forSession('s1');

      expect(found, hasLength(2));
      expect(found.map((e) => e.type), [
        EventType.sessionPlanned,
        EventType.nudgeScheduled,
      ]);
    });

    test('leaves the payload untouched', () async {
      // The column is a copy for indexing. The payload is still the record,
      // and an append-only log that quietly rewrote itself during an upgrade
      // would not be worth keeping.
      final raw = v1DatabaseWith([
        event(EventType.sessionPlanned, 1000, {
          'sessionId': 's1',
          'minutes': 45,
        }),
      ]);
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final found = await EventRepo(
        db,
        FakeClock(DateTime.utc(2026, 8, 21)),
      ).forSession('s1');

      expect(found.single.field<int>('minutes'), 45);
      expect(found.single.field<String>('sessionId'), 's1');
    });

    test('events with no session survive with a null column', () async {
      final raw = v1DatabaseWith([
        event(EventType.appOpened, 1000),
        event(EventType.taskCreated, 2000, {'taskId': 't1'}),
        event(EventType.sessionPlanned, 3000, {'sessionId': 's1'}),
      ]);
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final events = EventRepo(db, FakeClock(DateTime.utc(2026, 8, 21)));

      expect(await events.count(), 3, reason: 'no row may be lost');
      expect(await events.forSession('s1'), hasLength(1));
      expect(
        (await events.all()).map((e) => e.type),
        [EventType.appOpened, EventType.taskCreated, EventType.sessionPlanned],
      );
    });

    test('a malformed payload does not stop the upgrade', () async {
      // json_extract on invalid JSON would throw and abort the whole
      // migration, taking the log with it, so this is worth knowing.
      final raw = sqlite3.openInMemory()
        ..execute('''
          CREATE TABLE events (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            ts_utc INTEGER NOT NULL,
            type TEXT NOT NULL,
            payload_json TEXT NOT NULL DEFAULT '{}'
          );
        ''')
        ..execute(
          'INSERT INTO events (ts_utc, type, payload_json) VALUES (?, ?, ?)',
          [1000, EventType.appOpened.name, 'not json at all'],
        )
        ..execute(
          'INSERT INTO events (ts_utc, type, payload_json) VALUES (?, ?, ?)',
          [2000, EventType.sessionPlanned.name, '{"sessionId":"s1"}'],
        )
        ..execute('PRAGMA user_version = 1');

      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);
      final events = EventRepo(db, FakeClock(DateTime.utc(2026, 8, 21)));

      expect(await events.count(), 2);
      expect(await events.forSession('s1'), hasLength(1));
    });

    test('creates the index, not just the column', () async {
      // The point of the whole migration. addColumn does not create declared
      // indexes - only createAll does, and an upgrade never calls it - so an
      // upgraded database would otherwise have the column and still scan.
      // This was missed here and caught on the phone.
      final raw = v1DatabaseWith([
        event(EventType.sessionPlanned, 1000, {'sessionId': 's1'}),
      ]);
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      // Force the upgrade to run before inspecting the schema.
      await EventRepo(db, FakeClock(DateTime.utc(2026, 8, 21))).count();

      expect(indexesOn(raw), contains('idx_events_session'));
    });

    test('a database already at v2 still gets the index', () async {
      // Not hypothetical: this is the exact state the phone was left in by
      // the first attempt, and it will never re-run the v2 step.
      final raw =
          v1DatabaseWith([
              event(EventType.sessionPlanned, 1000, {'sessionId': 's1'}),
            ])
            ..execute('ALTER TABLE events ADD COLUMN session_id TEXT NULL')
            ..execute("UPDATE events SET session_id = 's1'")
            ..execute('PRAGMA user_version = 2');

      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);
      final events = EventRepo(db, FakeClock(DateTime.utc(2026, 8, 21)));

      expect(await events.forSession('s1'), hasLength(1));
      expect(indexesOn(raw), contains('idx_events_session'));
    });

    test('appending after the upgrade fills the column too', () async {
      final raw = v1DatabaseWith([
        event(EventType.sessionPlanned, 1000, {'sessionId': 's1'}),
      ]);
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final events = EventRepo(db, FakeClock(DateTime.utc(2026, 8, 21)));
      await events.append(EventType.sessionStarted, {'sessionId': 's1'});

      expect(await events.forSession('s1'), hasLength(2));
    });
  });

  group('a fresh v2 database', () {
    late VanDatabase db;
    late EventRepo events;

    setUp(() {
      db = VanDatabase.memory();
      events = EventRepo(db, FakeClock(DateTime.utc(2026, 8, 21, 9)));
    });

    tearDown(() async => db.close());

    test('finds a session without decoding the whole log', () async {
      await events.append(EventType.sessionPlanned, {'sessionId': 's1'});
      await events.append(EventType.appOpened);
      await events.append(EventType.sessionPlanned, {'sessionId': 's2'});
      await events.append(EventType.nudgeScheduled, {'sessionId': 's1'});

      expect(await events.forSession('s1'), hasLength(2));
      expect(await events.forSession('s2'), hasLength(1));
      expect(await events.forSession('nobody'), isEmpty);
    });

    test('orders by time, then by id within a timestamp', () async {
      final at = DateTime.utc(2026, 8, 21, 9);
      await events.append(EventType.sessionPlanned, {'sessionId': 's1'}, at);
      await events.append(EventType.nudgeScheduled, {'sessionId': 's1'}, at);

      expect((await events.forSession('s1')).map((e) => e.type), [
        EventType.sessionPlanned,
        EventType.nudgeScheduled,
      ]);
    });
  });
}
