import 'package:meta/meta.dart';

import 'package:van_core/src/model/event.dart';

/// What the event log says happened, counted up.
///
/// Van's design principle is that the append-only log is the app's memory, and
/// until this existed none of that memory was legible without hand-written
/// SQL. The point is not a dashboard. It is that the three dials worth
/// adjusting after real use - the replacement lead, the dismissal limit, and
/// whether halving a block is the right first concession - are all questions
/// about what actually happened, and guessing at them is how a scheduler ends
/// up tuned for nobody.
///
/// Pure: it takes events and returns numbers. Every field is derived from a
/// payload key that is actually written somewhere in `VanService`; nothing
/// here infers, estimates, or fills in a gap.
@immutable
class WeekReview {
  /// Creates a review directly. Prefer [WeekReview.from].
  const WeekReview({
    required this.tasksCaptured,
    required this.blocksPlanned,
    required this.blocksStarted,
    required this.blocksCompleted,
    required this.blocksPartial,
    required this.blocksMissed,
    required this.missedByReason,
    required this.reschedulesByReason,
    required this.movedThenMissedAgain,
    required this.nudgesScheduled,
    required this.nudgesDelivered,
    required this.nudgesSuppressed,
    required this.suppressedByReason,
    required this.nudgeScheduleFailures,
    required this.responsesByType,
    required this.proposalsByAction,
    required this.proposalsFromModel,
    required this.proposalsRefused,
    required this.from,
    required this.to,
  });

  /// Counts [events], which need not be sorted.
  factory WeekReview.from(Iterable<VanEvent> events) {
    var tasksCaptured = 0;
    var blocksPlanned = 0;
    var blocksStarted = 0;
    var blocksCompleted = 0;
    var blocksPartial = 0;
    var blocksMissed = 0;
    var nudgesScheduled = 0;
    var nudgesDelivered = 0;
    var nudgesSuppressed = 0;
    var nudgeScheduleFailures = 0;
    var proposalsFromModel = 0;
    var proposalsRefused = 0;

    final missedByReason = <String, int>{};
    final reschedulesByReason = <String, int>{};
    final suppressedByReason = <String, int>{};
    final responsesByType = <String, int>{};
    final proposalsByAction = <String, int>{};

    // A replacement that was itself missed is the sharpest signal in the log:
    // Van moved the work and the move did not help. Collected as ids rather
    // than counted inline because the miss can arrive before or after the
    // reschedule in an unsorted list.
    final replacementIds = <String>{};
    final missedSessionIds = <String>{};

    DateTime? from;
    DateTime? to;

    void bump(Map<String, int> into, String? key) {
      if (key == null) return;
      into[key] = (into[key] ?? 0) + 1;
    }

    for (final event in events) {
      if (from == null || event.timestamp.isBefore(from)) {
        from = event.timestamp;
      }
      if (to == null || event.timestamp.isAfter(to)) to = event.timestamp;

      switch (event.type) {
        case EventType.taskCreated:
          tasksCaptured++;
        case EventType.sessionPlanned:
          blocksPlanned++;
        case EventType.sessionStarted:
          blocksStarted++;
        case EventType.sessionCompleted:
          blocksCompleted++;
        case EventType.sessionPartial:
          blocksPartial++;
        case EventType.sessionMissed:
          blocksMissed++;
          bump(missedByReason, event.field<String>('reason'));
          final id = event.field<String>('sessionId');
          if (id != null) missedSessionIds.add(id);
        case EventType.rescheduleApplied:
          bump(reschedulesByReason, event.field<String>('reason'));
          final to = event.field<String>('to');
          if (to != null) replacementIds.add(to);
        case EventType.nudgeScheduled:
          nudgesScheduled++;
        case EventType.nudgeDelivered:
          nudgesDelivered++;
        case EventType.nudgeSuppressed:
          nudgesSuppressed++;
          bump(suppressedByReason, event.field<String>('reason'));
        case EventType.nudgeScheduleFailed:
          nudgeScheduleFailures++;
        case EventType.nudgeResponded:
          bump(responsesByType, event.field<String>('response'));
        case EventType.interventionSelected:
          bump(proposalsByAction, event.field<String>('action'));
          if (event.field<String>('source') == 'model') proposalsFromModel++;
          if (event.field<String>('refused') != null) proposalsRefused++;
        case EventType.taskUpdated:
        case EventType.inferenceOk:
        case EventType.inferenceFallback:
        case EventType.appOpened:
        case EventType.appBackgrounded:
          break;
      }
    }

    return WeekReview(
      tasksCaptured: tasksCaptured,
      blocksPlanned: blocksPlanned,
      blocksStarted: blocksStarted,
      blocksCompleted: blocksCompleted,
      blocksPartial: blocksPartial,
      blocksMissed: blocksMissed,
      missedByReason: Map.unmodifiable(missedByReason),
      reschedulesByReason: Map.unmodifiable(reschedulesByReason),
      movedThenMissedAgain: replacementIds
          .intersection(missedSessionIds)
          .length,
      nudgesScheduled: nudgesScheduled,
      nudgesDelivered: nudgesDelivered,
      nudgesSuppressed: nudgesSuppressed,
      suppressedByReason: Map.unmodifiable(suppressedByReason),
      nudgeScheduleFailures: nudgeScheduleFailures,
      responsesByType: Map.unmodifiable(responsesByType),
      proposalsByAction: Map.unmodifiable(proposalsByAction),
      proposalsFromModel: proposalsFromModel,
      proposalsRefused: proposalsRefused,
      from: from,
      to: to,
    );
  }

  /// Tasks captured.
  final int tasksCaptured;

  /// Blocks the planner placed.
  final int blocksPlanned;

  /// Blocks the user pressed START on.
  final int blocksStarted;

  /// Blocks that ran to the end.
  final int blocksCompleted;

  /// Blocks that started and stopped early. Still a success, in Van's terms.
  final int blocksPartial;

  /// Blocks that came due and were not worked.
  final int blocksMissed;

  /// Misses by the `reason` recorded with them: `stale`, `not_today`,
  /// `negotiated_release`.
  final Map<String, int> missedByReason;

  /// Moves by the `reason` recorded with them: `snooze`, `stuck`, `sweep`,
  /// and whatever a negotiation passed in.
  final Map<String, int> reschedulesByReason;

  /// Replacements that were themselves missed.
  ///
  /// The number to look at before trusting any rescheduling behaviour: it
  /// counts the times Van moved work and moving it did not help.
  final int movedThenMissedAgain;

  /// Nudges handed to the platform.
  final int nudgesScheduled;

  /// Nudges recorded as delivered.
  ///
  /// **Not a delivery count.** Van has no way to observe a notification
  /// appearing: `nudgeDelivered` is written by `_recordAnswer` on the way past
  /// when a rung is *answered*, so a nudge that showed up and was ignored is
  /// never counted. Reading this as "how many reached the user" understates it
  /// by exactly the nudges that were shrugged off, which are the ones worth
  /// knowing about.
  final int nudgesDelivered;

  /// Nudges Van decided against sending.
  final int nudgesSuppressed;

  /// Suppressions by rule, which is how to tell whether a limit is set right.
  final Map<String, int> suppressedByReason;

  /// Nudges the platform refused. Any number above zero is worth a look.
  final int nudgeScheduleFailures;

  /// Answers by kind: `started`, `snoozed`, `dismissed`, `ignored`.
  final Map<String, int> responsesByType;

  /// Proposals by action: `hold`, `shrink`, `defer`, `release`.
  final Map<String, int> proposalsByAction;

  /// Proposals that came from a model rather than the deterministic fallback.
  final int proposalsFromModel;

  /// Proposals the domain gate refused.
  final int proposalsRefused;

  /// Timestamp of the earliest event counted, or null when there were none.
  final DateTime? from;

  /// Timestamp of the latest event counted, or null when there were none.
  final DateTime? to;

  /// Whether anything was counted at all.
  bool get isEmpty => blocksPlanned == 0 && tasksCaptured == 0;

  /// Blocks that were started, as a fraction of those planned.
  ///
  /// Null rather than zero when nothing was planned: a rate over no blocks is
  /// not 0%, it is a question with no answer, and printing 0% would read as a
  /// week of total failure rather than a week of no data.
  double? get startRate =>
      blocksPlanned == 0 ? null : blocksStarted / blocksPlanned;

  /// Blocks that ran to the end, as a fraction of those started.
  double? get completionRate =>
      blocksStarted == 0 ? null : blocksCompleted / blocksStarted;
}
