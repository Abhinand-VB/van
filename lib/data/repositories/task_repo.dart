import 'package:drift/drift.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/mappers.dart';
import 'package:van_core/van_core.dart';

/// Storage for tasks. Returns domain models only; no Drift type escapes here.
class TaskRepo {
  /// Creates a repository over [_db].
  TaskRepo(this._db);

  final VanDatabase _db;

  /// Inserts or replaces [task].
  Future<void> save(Task task) =>
      _db.into(_db.tasks).insertOnConflictUpdate(taskToRow(task));

  /// The task with [id], or null.
  Future<Task?> byId(String id) async {
    final row = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : taskFromRow(row);
  }

  /// Every task, newest first.
  Future<List<Task>> all() => (_db.select(
    _db.tasks,
  )..orderBy([(t) => OrderingTerm.desc(t.createdUtc)])).map(taskFromRow).get();

  /// Tasks that are still live, in deadline order with undated ones last.
  ///
  /// This is the query behind the Now screen, so the ordering is the product
  /// decision about what "next" means, not an arbitrary sort.
  Future<List<Task>> open() async {
    final rows =
        await (_db.select(_db.tasks)..where(
              (t) => t.status.isNotIn([
                TaskStatus.done.name,
                TaskStatus.abandoned.name,
              ]),
            ))
            .map(taskFromRow)
            .get();
    rows.sort((a, b) {
      if (a.deadline == null && b.deadline == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (a.deadline == null) return 1;
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);
    });
    return rows;
  }

  /// Tasks whose deadline falls before [before] and are not finished.
  Future<List<Task>> dueBefore(DateTime before) async {
    final cutoff = before.toUtc().millisecondsSinceEpoch;
    final rows =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deadlineUtc.isSmallerThanValue(cutoff) &
                  t.status.isNotIn([
                    TaskStatus.done.name,
                    TaskStatus.abandoned.name,
                  ]),
            ))
            .map(taskFromRow)
            .get();
    return rows;
  }

  /// Removes a task. Sessions referencing it must be removed first.
  ///
  /// Deleting a task is not the same as abandoning one: prefer setting
  /// [TaskStatus.abandoned] so the event log keeps making sense.
  Future<void> delete(String id) =>
      (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();

  /// Watches every open task, for reactive UI.
  Stream<List<Task>> watchOpen() =>
      (_db.select(_db.tasks)..where(
            (t) => t.status.isNotIn([
              TaskStatus.done.name,
              TaskStatus.abandoned.name,
            ]),
          ))
          .map(taskFromRow)
          .watch();
}
