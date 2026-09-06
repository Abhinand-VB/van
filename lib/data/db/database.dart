import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:van/data/db/tables.dart';
// Required by the generated part file: `part` files inherit only the
// enclosing library's imports, so the enums used by textEnum<T>() columns
// must be visible here even though this file does not name them.
import 'package:van_core/van_core.dart';

part 'database.g.dart';

/// Van's local database. There is no server and no sync; this file is the
/// entire persistent state of the app.
@DriftDatabase(
  tables: [Tasks, WorkSessions, Nudges, NudgeResponses, Events, Settings],
)
class VanDatabase extends _$VanDatabase {
  /// Opens the on-device database.
  VanDatabase() : super(_openConnection());

  /// Opens a throwaway in-memory database for tests.
  VanDatabase.memory() : super(NativeDatabase.memory());

  /// Opens over an executor the caller already has.
  ///
  /// Exists so a migration can be tested against a database built by hand at
  /// an older version. This one runs on a phone holding the only copy of the
  /// event log, so "it compiled" is not enough assurance.
  VanDatabase.on(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // v2 lifts sessionId out of the JSON payload into an indexed column, so
      // reading one session's history stops meaning "load the entire log and
      // filter it in Dart".
      if (from < 2) {
        await m.addColumn(events, events.sessionId);
        // Backfill rather than leaving history unsearchable. json_extract
        // returns null for rows whose payload has no sessionId, which is
        // exactly the value those rows should carry.
        //
        // The json_valid guard is not defensive padding. json_extract raises
        // on malformed JSON, which aborts the whole UPDATE - so one bad row
        // anywhere in the log would fail the migration and leave the app
        // unable to open. `eventFromRow` has always tolerated an unparseable
        // payload, so such a row is possible by construction, and there is a
        // test for exactly this.
        await customStatement(
          'UPDATE events '
          r"SET session_id = json_extract(payload_json, '$.sessionId') "
          'WHERE session_id IS NULL AND json_valid(payload_json)',
        );
      }

      // v3 exists only because v2 shipped without this. `addColumn` does not
      // create the indexes declared on a table - only `createAll` does, and an
      // upgrade never calls it - so a database upgraded to v2 got the column
      // and no index, which is the one thing the change was for. Found on the
      // phone rather than in the tests.
      //
      // Separate from the v2 block because a device that already ran v2 will
      // never run it again, and that device exists. IF NOT EXISTS makes the
      // statement safe on every path into v3.
      if (from < 3) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_events_session '
          'ON events (session_id)',
        );
      }

      // v4 carries task depth and the opening block that depends on it.
      //
      // Both columns are declared with defaults, which is what makes this a
      // two-line upgrade: `addColumn` on a NOT NULL column with no default
      // fails on a table that already has rows, and this database is on a
      // phone with months of them. Nothing is backfilled and nothing should
      // be - re-reading old titles through today's verb list would invent a
      // depth for tasks that were planned without one, and the plans they
      // already have were made on the old rule.
      //
      // No index on either. Depth is read alongside a task that is being
      // loaded anyway, and there is no query that selects *by* it.
      if (from < 4) {
        await m.addColumn(tasks, tasks.depth);
        await m.addColumn(workSessions, workSessions.isOpener);
      }

      // v5 records how long work actually took, which is the only number in
      // Van that can tell an estimate it was wrong. Nullable, so the column
      // adds cleanly to a table full of rows and every task that predates it
      // reads back as "nobody said" - which is exactly true of them.
      if (from < 5) {
        await m.addColumn(tasks, tasks.actualMinutes);
      }
    },
    beforeOpen: (details) async {
      // Foreign keys are off by default in SQLite. Without this the
      // references declared in tables.dart are decorative.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(dir.path, 'van.sqlite')),
    );
  });
}
