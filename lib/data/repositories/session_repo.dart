import 'package:drift/drift.dart';
import 'package:nova/data/db/database.dart';
import 'package:nova/data/repositories/mappers.dart';
import 'package:nova_core/nova_core.dart';

/// Storage for work sessions - the blocks Nova nudges about.
class SessionRepo {
  /// Creates a repository over [_db].
  SessionRepo(this._db);

  final NovaDatabase _db;

  /// Inserts or replaces [session].
  Future<void> save(WorkSession session) =>
      _db.into(_db.workSessions).insertOnConflictUpdate(sessionToRow(session));

  /// Inserts or replaces many sessions in one transaction, as the planner
  /// produces them as a set.
  Future<void> saveAll(Iterable<WorkSession> sessions) => _db.batch(
    (b) => b.insertAllOnConflictUpdate(
      _db.workSessions,
      sessions.map(sessionToRow).toList(),
    ),
  );

  /// The session with [id], or null.
  Future<WorkSession?> byId(String id) async {
    final row = await (_db.select(
      _db.workSessions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    return row == null ? null : sessionFromRow(row);
  }

  /// Every session for [taskId], earliest first.
  Future<List<WorkSession>> forTask(String taskId) =>
      (_db.select(_db.workSessions)
            ..where((s) => s.taskId.equals(taskId))
            ..orderBy([(s) => OrderingTerm.asc(s.plannedStartUtc)]))
          .map(sessionFromRow)
          .get();

  /// Sessions planned to start within [from, to), earliest first.
  ///
  /// This is the nudge engine's hot query, which is why
  /// `idx_sessions_planned_start` exists.
  Future<List<WorkSession>> plannedBetween(DateTime from, DateTime to) {
    final start = from.toUtc().millisecondsSinceEpoch;
    final end = to.toUtc().millisecondsSinceEpoch;
    return (_db.select(_db.workSessions)
          ..where(
            (s) =>
                s.plannedStartUtc.isBiggerOrEqualValue(start) &
                s.plannedStartUtc.isSmallerThanValue(end),
          )
          ..orderBy([(s) => OrderingTerm.asc(s.plannedStartUtc)]))
        .map(sessionFromRow)
        .get();
  }

  /// Sessions still awaiting an outcome, earliest first.
  Future<List<WorkSession>> unresolved() =>
      (_db.select(_db.workSessions)
            ..where(
              (s) => s.status.isIn([
                SessionStatus.planned.name,
                SessionStatus.started.name,
              ]),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.plannedStartUtc)]))
          .map(sessionFromRow)
          .get();

  /// The session currently running, if any.
  ///
  /// Used by the suppression policy: Nova must not interrupt work it asked
  /// for.
  Future<WorkSession?> inProgress() async {
    final row =
        await (_db.select(_db.workSessions)
              ..where((s) => s.status.equalsValue(SessionStatus.started))
              ..orderBy([(s) => OrderingTerm.desc(s.plannedStartUtc)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : sessionFromRow(row);
  }

  /// The next session due at or after [from].
  ///
  /// This answers the only question the Now screen asks.
  Future<WorkSession?> next(DateTime from) async {
    final cutoff = from.toUtc().millisecondsSinceEpoch;
    final row =
        await (_db.select(_db.workSessions)
              ..where(
                (s) =>
                    s.plannedStartUtc.isBiggerOrEqualValue(cutoff) &
                    s.status.equalsValue(SessionStatus.planned),
              )
              ..orderBy([(s) => OrderingTerm.asc(s.plannedStartUtc)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : sessionFromRow(row);
  }

  /// Watches sessions awaiting an outcome, for reactive UI.
  Stream<List<WorkSession>> watchUnresolved() =>
      (_db.select(_db.workSessions)
            ..where(
              (s) => s.status.isIn([
                SessionStatus.planned.name,
                SessionStatus.started.name,
              ]),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.plannedStartUtc)]))
          .map(sessionFromRow)
          .watch();

  /// Removes a session. Prefer a status transition; this exists for cleanup.
  Future<void> delete(String id) =>
      (_db.delete(_db.workSessions)..where((s) => s.id.equals(id))).go();
}
