import 'package:meta/meta.dart';
import 'package:van_core/src/model/nudge.dart';
import 'package:van_core/src/model/nudge_response.dart';

/// Everything the ladder needs to decide how hard to push.
///
/// Deliberately a flat bag of facts rather than a reference to the session:
/// the policy must be trivially callable from a test with made-up numbers, and
/// it must be replaceable in phase 4 by something learned from the event log
/// without changing what it is handed.
@immutable
class InterventionContext {
  /// Creates a context.
  const InterventionContext({
    this.minutesLate = 0,
    this.rescheduleCount = 0,
    this.hoursToDeadline,
    this.priorResponses = const [],
    this.userGaveReason = false,
    this.userRefused = false,
  });

  /// Minutes past the planned start with no start recorded.
  final int minutesLate;

  /// How many times this work has already been moved.
  final int rescheduleCount;

  /// Hours until the task is due, if it has a deadline. Negative if overdue.
  final double? hoursToDeadline;

  /// How the user answered earlier nudges about this session, oldest first.
  final List<ResponseType> priorResponses;

  /// Whether the user explained themselves rather than just ignoring it.
  final bool userGaveReason;

  /// Whether the user has said no outright.
  final bool userRefused;

  /// Whether the deadline is close enough to justify pushing harder.
  bool get deadlineIsNear => hoursToDeadline != null && hoursToDeadline! < 24;

  /// How many nudges about this session went unanswered.
  int get ignoredCount =>
      priorResponses.where((r) => r == ResponseType.ignored).length;
}

/// Chooses how hard Van pushes, and never chooses the words.
///
/// The separation matters: a language model may phrase level 3, but if it were
/// also allowed to *pick* level 3 then escalation would stop being predictable
/// and there would be nothing to tune. In v1 this is a lookup table. Phase 4
/// can replace the body with something fitted to the event log without any
/// caller noticing.
class InterventionPolicy {
  /// Creates a policy with the default thresholds.
  const InterventionPolicy({
    this.checkAfterMinutes = 10,
    this.diagnoseAfterMinutes = 25,
    this.renegotiateAfterMoves = 3,
  });

  /// Minutes late before Van asks whether it is starting or moving.
  final int checkAfterMinutes;

  /// Minutes late before Van asks what is in the way.
  final int diagnoseAfterMinutes;

  /// Moves before Van names the pattern out loud.
  final int renegotiateAfterMoves;

  /// Picks the level for [context].
  ///
  /// Order is significant. A refusal outranks lateness, because continuing to
  /// escalate at someone who has already said no is how an accountability app
  /// becomes an app people uninstall.
  InterventionLevel select(InterventionContext context) {
    // Already said no once at the renegotiation stage: stop pushing.
    if (context.userRefused && _wouldRenegotiate(context)) {
      return InterventionLevel.l5Concede;
    }

    // Said no to a normal ask: offer something smaller instead of arguing.
    if (context.userRefused) return InterventionLevel.l3Shrink;

    // Repeatedly moved with the deadline closing in: name it.
    if (_wouldRenegotiate(context)) return InterventionLevel.l4Renegotiate;

    // Gave a reason: meet it with a smaller ask rather than a repeat.
    if (context.userGaveReason) return InterventionLevel.l3Shrink;

    if (context.minutesLate >= diagnoseAfterMinutes) {
      return InterventionLevel.l2Diagnose;
    }
    if (context.minutesLate >= checkAfterMinutes) {
      return InterventionLevel.l1Check;
    }
    return InterventionLevel.l0Gentle;
  }

  bool _wouldRenegotiate(InterventionContext context) =>
      context.rescheduleCount >= renegotiateAfterMoves &&
      context.deadlineIsNear;

  /// Whether [level] should offer a shrunken block rather than the full one.
  static bool offersShrink(InterventionLevel level) =>
      level == InterventionLevel.l3Shrink ||
      level == InterventionLevel.l4Renegotiate;

  /// Whether [level] means Van has stopped asking and is moving the work.
  static bool concedes(InterventionLevel level) =>
      level == InterventionLevel.l5Concede;
}
