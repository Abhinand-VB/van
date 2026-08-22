import 'package:drift/drift.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/mappers.dart';
import 'package:van_core/van_core.dart';

/// Storage for nudges and the replies to them.
///
/// Suppressed nudges are stored alongside delivered ones. The suppression
/// policy is as much a product decision as the scheduler, and it can only be
/// tuned if there is a record of what it chose to hold back.
class NudgeRepo {
  /// Creates a repository over [_db].
  NudgeRepo(this._db);

  final VanDatabase _db;

  /// Inserts or replaces [nudge].
  Future<void> save(Nudge nudge) =>
      _db.into(_db.nudges).insertOnConflictUpdate(nudgeToRow(nudge));

  /// Records a reply.
  Future<void> saveResponse(NudgeResponse response) => _db
      .into(_db.nudgeResponses)
      .insertOnConflictUpdate(responseToRow(response));

  /// The nudge with [id], or null.
  Future<Nudge?> byId(String id) async {
    final row = await (_db.select(
      _db.nudges,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
    return row == null ? null : nudgeFromRow(row);
  }

  /// The most recent nudge that actually reached the user, if any.
  ///
  /// Feeds the recency penalty in the scoring formula.
  Future<Nudge?> lastDelivered() async {
    final row =
        await (_db.select(_db.nudges)
              ..where(
                (n) =>
                    n.deliveredUtc.isNotNull() & n.wasSuppressed.equals(false),
              )
              ..orderBy([(n) => OrderingTerm.desc(n.deliveredUtc)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : nudgeFromRow(row);
  }

  /// Nudges delivered at or after [from], newest first.
  Future<List<Nudge>> deliveredSince(DateTime from) {
    final cutoff = from.toUtc().millisecondsSinceEpoch;
    return (_db.select(_db.nudges)
          ..where(
            (n) =>
                n.deliveredUtc.isBiggerOrEqualValue(cutoff) &
                n.wasSuppressed.equals(false),
          )
          ..orderBy([(n) => OrderingTerm.desc(n.deliveredUtc)]))
        .map(nudgeFromRow)
        .get();
  }

  /// Every nudge about [sessionId], oldest first.
  Future<List<Nudge>> forSession(String sessionId) =>
      (_db.select(_db.nudges)
            ..where((n) => n.sessionId.equals(sessionId))
            ..orderBy([(n) => OrderingTerm.asc(n.scheduledUtc)]))
          .map(nudgeFromRow)
          .get();

  /// Removes every nudge about [sessionId], and any replies to them.
  ///
  /// Only for work that is being erased rather than resolved - an undone
  /// capture. A nudge about a session that no longer exists describes an
  /// interruption that will never happen, and leaving it behind would make
  /// `forSession` lie. Replies go first because they reference the nudge.
  ///
  /// Note this is not a hole in the append-only rule: that rule governs the
  /// `events` table, which keeps the whole history regardless.
  Future<void> deleteForSession(String sessionId) => _db.transaction(() async {
    final ids = (await (_db.select(
      _db.nudges,
    )..where((n) => n.sessionId.equals(sessionId))).get()).map((n) => n.id);

    for (final id in ids) {
      await (_db.delete(
        _db.nudgeResponses,
      )..where((r) => r.nudgeId.equals(id))).go();
    }
    await (_db.delete(
      _db.nudges,
    )..where((n) => n.sessionId.equals(sessionId))).go();
  });

  /// Replies to [nudgeId], oldest first.
  Future<List<NudgeResponse>> responsesFor(String nudgeId) =>
      (_db.select(_db.nudgeResponses)
            ..where((r) => r.nudgeId.equals(nudgeId))
            ..orderBy([(r) => OrderingTerm.asc(r.respondedUtc)]))
          .map(responseFromRow)
          .get();

  /// How many *ladders* of [type] went unanswered in a row, most recently, at
  /// or after [since].
  ///
  /// Drives the fatigue penalty. Counted per ladder rather than per nudge,
  /// because a ladder is exactly three rungs: counting rungs meant one
  /// unattended block tripped a limit of three all by itself, which is what
  /// muted Van for a day on 21 August. Escalating three times at one block
  /// and getting no answer is Van being ignored once.
  ///
  /// A ladder counts as ignored only when *no* rung of it was engaged with,
  /// so answering late - at L2, after letting L0 and L1 pass - still clears
  /// it. Nudges with no session (hydration, stand) have no ladder to belong
  /// to and count individually.
  Future<int> consecutiveUnansweredLadders(
    NudgeType type,
    DateTime since,
  ) async {
    final cutoff = since.toUtc().millisecondsSinceEpoch;
    final nudges =
        await (_db.select(_db.nudges)
              ..where(
                (n) =>
                    n.type.equalsValue(type) &
                    n.deliveredUtc.isBiggerOrEqualValue(cutoff) &
                    n.wasSuppressed.equals(false),
              )
              ..orderBy([(n) => OrderingTerm.desc(n.deliveredUtc)]))
            .map(nudgeFromRow)
            .get();

    var streak = 0;
    final counted = <String>{};
    for (final nudge in nudges) {
      final replies = await responsesFor(nudge.id);
      final engaged = replies.any(
        (r) =>
            r.response != ResponseType.dismissed &&
            r.response != ResponseType.ignored,
      );
      final sessionId = nudge.sessionId;
      if (engaged) {
        // Walking newest-first, an engaged rung can appear *after* a later
        // rung of the same ladder has already been counted - L0 answered,
        // L1 armed and ignored. The ladder was answered, so take the count
        // back before stopping.
        if (sessionId != null && counted.remove(sessionId)) streak--;
        break;
      }
      if (sessionId == null) {
        streak++;
      } else if (counted.add(sessionId)) {
        streak++;
      }
    }
    return streak;
  }
}
