import 'package:meta/meta.dart';
import 'package:nova_core/src/clock.dart';
import 'package:nova_core/src/id_generator.dart';
import 'package:nova_core/src/model/task.dart';
import 'package:nova_core/src/model/work_session.dart';
import 'package:nova_core/src/result.dart';
import 'package:nova_core/src/scheduling/time_window.dart';

/// The shape Nova insists work should take.
///
/// These defaults are the product opinion, not arbitrary numbers: a four-hour
/// block labelled "finish assignment" is exactly the thing people fail to
/// start, so the planner is forbidden from producing one.
@immutable
class PlannerConstraints {
  /// Creates a constraint set.
  const PlannerConstraints({
    this.maxSessionMinutes = 90,
    this.minSessionMinutes = 15,
    this.breakMinutes = 10,
    this.finishBeforeDeadlineHours = 12,
    this.maxSessionsPerDay = 3,
    this.defaultEstimateMinutes = 60,
  }) : assert(
         minSessionMinutes <= maxSessionMinutes,
         'minSessionMinutes must not exceed maxSessionMinutes',
       );

  /// Longest single block. Nothing longer is ever emitted.
  final int maxSessionMinutes;

  /// Shortest block worth scheduling, except for a final remainder.
  final int minSessionMinutes;

  /// Gap left between consecutive blocks in the same slot.
  final int breakMinutes;

  /// Finish this far ahead of the deadline, so the deadline is not the plan.
  final int finishBeforeDeadlineHours;

  /// Cap on blocks per local day, to avoid a plan nobody would follow.
  final int maxSessionsPerDay;

  /// Assumed effort when the user never said how long it would take.
  final int defaultEstimateMinutes;
}

/// Why a task could not be fully scheduled.
enum PlanFailureKind {
  /// The deadline is already in the past.
  deadlinePassed,

  /// There is not enough free time before the deadline.
  insufficientTime,
}

/// A plan that could not be completed, and what is missing.
///
/// This is a [Result] failure rather than an exception because running out of
/// time is a fact about the user's week, not a bug. The caller decides whether
/// to say "you need two more hours" or to quietly schedule what fits.
@immutable
class PlanFailure {
  /// Creates a failure carrying the partial plan and the gap.
  const PlanFailure({
    required this.kind,
    required this.shortfallMinutes,
    this.scheduled = const [],
  });

  /// What went wrong.
  final PlanFailureKind kind;

  /// Minutes of work that could not be placed.
  final int shortfallMinutes;

  /// The blocks that did fit. May be empty.
  final List<WorkSession> scheduled;

  @override
  String toString() =>
      'PlanFailure(${kind.name}, short by ${shortfallMinutes}m, '
      '${scheduled.length} placed)';
}

/// Turns a task into work sessions that a human might actually do.
class SessionPlanner {
  /// Creates a planner.
  const SessionPlanner({
    required this.ids,
    this.constraints = const PlannerConstraints(),
    this.waking = const WakingHours(),
  });

  /// Supplies session identifiers.
  final IdGenerator ids;

  /// The shape rules.
  final PlannerConstraints constraints;

  /// Used to decide which local day a block falls on.
  final WakingHours waking;

  /// Places [task] into [slots], earliest first.
  ///
  /// Returns [Ok] only when the whole estimate fits. A partial plan comes back
  /// as [Err] carrying both the shortfall and the blocks that did fit, so the
  /// caller can present the honest version rather than a plan that quietly
  /// drops two hours of work.
  Result<List<WorkSession>, PlanFailure> plan({
    required Task task,
    required List<FreeSlot> slots,
    required Clock clock,
  }) {
    final now = clock.now();
    var remaining = task.estimatedMinutes ?? constraints.defaultEstimateMinutes;

    final cutoff = task.deadline?.subtract(
      Duration(hours: constraints.finishBeforeDeadlineHours),
    );
    if (task.deadline != null && !task.deadline!.isAfter(now)) {
      return Err(
        PlanFailure(
          kind: PlanFailureKind.deadlinePassed,
          shortfallMinutes: remaining,
        ),
      );
    }

    final placed = <WorkSession>[];
    final perDay = <String, int>{};

    for (final raw in slots) {
      if (remaining <= 0) break;

      var usable = raw.clippedFrom(now);
      if (usable != null && cutoff != null) usable = usable.clippedTo(cutoff);
      if (usable == null) continue;

      var cursor = usable.start;
      while (remaining > 0 && cursor.isBefore(usable.end)) {
        final dayKey = _localDayKey(cursor);
        if ((perDay[dayKey] ?? 0) >= constraints.maxSessionsPerDay) break;

        final available = usable.end.difference(cursor).inMinutes;
        var take = remaining;
        if (take > constraints.maxSessionMinutes) {
          take = constraints.maxSessionMinutes;
        }
        if (take > available) take = available;

        // A block below the minimum is only worth placing when it is the last
        // of the work; otherwise it fragments the plan for no benefit.
        if (take < constraints.minSessionMinutes && take < remaining) break;
        if (take <= 0) break;

        placed.add(
          WorkSession(
            id: ids.next(),
            taskId: task.id,
            plannedStart: cursor,
            plannedMinutes: take,
          ),
        );
        remaining -= take;
        perDay[dayKey] = (perDay[dayKey] ?? 0) + 1;
        cursor = cursor.add(
          Duration(minutes: take + constraints.breakMinutes),
        );
      }
    }

    if (remaining > 0) {
      return Err(
        PlanFailure(
          kind: PlanFailureKind.insufficientTime,
          shortfallMinutes: remaining,
          scheduled: placed,
        ),
      );
    }
    return Ok(placed);
  }

  String _localDayKey(DateTime utcInstant) {
    final wall = waking.toLocalWall(utcInstant);
    return '${wall.year}-${wall.month}-${wall.day}';
  }
}
