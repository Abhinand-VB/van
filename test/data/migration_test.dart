import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van_core/van_core.dart';

/// The events table exactly as schema v1 had it: no `session_id`.
const _v1Events = '''
  CREATE TABLE events (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    ts_utc INTEGER NOT NULL,
    type TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}'
  );
''';

/// The other two tables an upgrade now touches, as v1 had them: `tasks`
/// without `depth`, `work_sessions` without `is_opener`.
///
/// **Added because the fixture was lying by omission.** It built the events
/// table alone, which was enough while every migration only touched events -
/// and the moment v4 added a column to `tasks`, seven passing tests started
/// failing with "no such table". A phone at v1 has all six tables; a fixture
/// that has one is not the shape sitting on the phone, which is the whole
/// claim this file makes.
const _v1Rest = '''
  CREATE TABLE tasks (
    id TEXT NOT NULL PRIMARY KEY,
    title TEXT NOT NULL,
    notes TEXT NULL,
    deadline_utc INTEGER NULL,
    estimated_minutes INTEGER NULL,
    priority TEXT NOT NULL,
    status TEXT NOT NULL,
    created_utc INTEGER NOT NULL,
    source TEXT NOT NULL
  );
  CREATE TABLE work_sessions (
    id TEXT NOT NULL PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks (id),
    planned_start_utc INTEGER NOT NULL,
    planned_minutes INTEGER NOT NULL,
    actual_start_utc INTEGER NULL,
    actual_end_utc INTEGER NULL,
    status TEXT NOT NULL,
    reschedule_count INTEGER NOT NULL DEFAULT 0,
    parent_session_id TEXT NULL
  );
''';

/// Builds a database at schema v1.
///
/// Written out by hand rather than generated, because the point of the test is
/// to prove the upgrade works against the shape that is actually sitting on
/// the phone.
Database v1DatabaseWith(List<({EventType type, int ts, String payload})> rows) {
  final db = sqlite3.openInMemory()
    ..execute(_v1Events)
    ..execute(_v1Rest)
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
        ..execute(_v1Events)
        ..execute(_v1Rest)
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

  group('upgrading to v4', () {
    /// A v3 database - the shape on the phone before tonight - carrying one
    /// task and one block.
    Database v3With() =>
        v1DatabaseWith([
            event(EventType.taskCreated, 1000, {'taskId': 't1'}),
          ])
          ..execute('ALTER TABLE events ADD COLUMN session_id TEXT NULL')
          ..execute(
            'CREATE INDEX idx_events_session ON events (session_id)',
          )
          ..execute(
            'INSERT INTO tasks (id, title, priority, status, created_utc, '
            'source, estimated_minutes) '
            "VALUES ('t1', 'Write the dissertation', 'normal', 'active', "
            '1000, '
            "'quickAdd', 180)",
          )
          ..execute(
            'INSERT INTO work_sessions (id, task_id, planned_start_utc, '
            'planned_minutes, status) '
            "VALUES ('s1', 't1', 2000, 90, 'planned')",
          )
          ..execute('PRAGMA user_version = 3');

    test('a task that predates depth reads back as unknown', () async {
      final raw = v3With();
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final task = await TaskRepo(db).byId('t1');

      // Nothing is backfilled and nothing should be. Re-reading old titles
      // through today's verb list would invent a depth for work that was
      // planned without one - and the plan it already has was made on the old
      // rule, so a depth disagreeing with it would be worse than no depth.
      expect(task?.depth, TaskDepth.unknown);
      expect(task?.title, 'Write the dissertation');
      expect(task?.estimatedMinutes, 180);
    });

    test('a block that predates the opener is not one', () async {
      final raw = v3With();
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final session = await SessionRepo(db).byId('s1');

      expect(session?.isOpener, isFalse);
      expect(session?.plannedMinutes, 90);
    });

    test('the columns are added, and only once', () async {
      final raw = v3With();
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);
      await TaskRepo(db).byId('t1');

      // addColumn on a NOT NULL column with no default fails outright against
      // a table that already has rows, which is every database on the phone.
      // Both columns carry defaults for exactly that reason.
      final columns = raw
          .select('PRAGMA table_info(tasks)')
          .map((r) => r['name'] as String);
      expect(columns, contains('depth'));
      expect(columns.where((c) => c == 'depth'), hasLength(1));
    });

    test('writing after the upgrade round-trips both new fields', () async {
      final raw = v3With();
      final db = VanDatabase.on(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final tasks = TaskRepo(db);
      final sessions = SessionRepo(db);
      final task = (await tasks.byId('t1'))!;
      await tasks.save(task.copyWith(depth: TaskDepth.deep));
      await sessions.save(
        WorkSession(
          id: 's2',
          taskId: 't1',
          plannedStart: DateTime.utc(2026, 9, 6, 9),
          plannedMinutes: 25,
          isOpener: true,
        ),
      );

      expect((await tasks.byId('t1'))?.depth, TaskDepth.deep);
      expect((await sessions.byId('s2'))?.isOpener, isTrue);
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
