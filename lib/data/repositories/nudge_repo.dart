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

  /// Replies to [nudgeId], oldest first.
  Future<List<NudgeResponse>> responsesFor(String nudgeId) =>
      (_db.select(_db.nudgeResponses)
            ..where((r) => r.nudgeId.equals(nudgeId))
            ..orderBy([(r) => OrderingTerm.asc(r.respondedUtc)]))
          .map(responseFromRow)
          .get();

  /// How many nudges of [type] were dismissed or ignored in a row, most
  /// recently, at or after [since].
  ///
  /// Drives the fatigue penalty: a person who has swiped away three of these
  /// today has told Van something, and it should listen.
  Future<int> consecutiveDismissals(NudgeType type, DateTime since) async {
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
    for (final nudge in nudges) {
      final replies = await responsesFor(nudge.id);
      final engaged = replies.any(
        (r) =>
            r.response != ResponseType.dismissed &&
            r.response != ResponseType.ignored,
      );
      if (engaged) break;
      streak++;
    }
    return streak;
  }
}
