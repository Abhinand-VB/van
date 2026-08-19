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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
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
