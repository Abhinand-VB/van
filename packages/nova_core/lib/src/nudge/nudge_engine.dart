import 'package:meta/meta.dart';
import 'package:nova_core/src/model/nudge.dart';
import 'package:nova_core/src/model/nudge_response.dart';
import 'package:nova_core/src/model/task.dart';
import 'package:nova_core/src/model/work_session.dart';
import 'package:nova_core/src/nudge/importance_scorer.dart';
import 'package:nova_core/src/nudge/suppression_policy.dart';
import 'package:nova_core/src/policy/intervention_policy.dart';

/// One session, with everything Nova has learned about how it is going.
@immutable
class SessionContext {
  /// Creates a context.
  const SessionContext({
    required this.session,
    required this.task,
    this.priorResponses = const [],
    this.userGaveReason = false,
    this.userRefused = false,
  });

  /// The block in question.
  final WorkSession session;

  /// The task it belongs to.
  final Task task;

  /// How the user answered earlier nudges about this block, oldest first.
  final List<ResponseType> priorResponses;

  /// Whether they explained themselves rather than just ignoring it.
  final bool userGaveReason;

  /// Whether they have said no outright.
  final bool userRefused;
}

/// An immutable snapshot of everything the engine reads.
///
/// The engine takes this in and returns decisions out. It performs no I/O,
/// touches no database and sends no notifications, which is what makes a
/// simulated week runnable in milliseconds.
@immutable
class NudgeEngineState {
  /// Creates a snapshot.
  const NudgeEngineState({
    this.sessions = const [],
    this.lastNudgeAt,
    this.lastNudgeSessionId,
    this.lastLevelBySession = const {},
    this.consecutiveDismissals = const {},
    this.deviceDoNotDisturb = false,
  });

  /// Every session still awaiting an outcome.
  final List<SessionContext> sessions;

  /// When the last nudge actually reached the user.
  final DateTime? lastNudgeAt;

  /// Which session that last nudge was about, if any.
  final String? lastNudgeSessionId;

  /// The last level delivered about each session, used to avoid repeating a
  /// nudge verbatim. Keyed per session because a global "last level" is
  /// defeated the moment two blocks alternate.
  final Map<String, InterventionLevel> lastLevelBySession;

  /// Consecutive unanswered nudges per type, today.
  final Map<NudgeType, int> consecutiveDismissals;

  /// Whether the OS is in do-not-disturb.
  final bool deviceDoNotDisturb;

  /// Whether a session is running right now.
  bool get focusInProgress =>
      sessions.any((s) => s.session.status == SessionStatus.started);
}

/// What the engine decided about one candidate interruption.
@immutable
class NudgeDecision {
  /// Creates a decision.
  const NudgeDecision({
    required this.type,
    required this.level,
    required this.importance,
    this.sessionId,
    this.suppressedBecause,
  });

  /// The kind of interruption.
  final NudgeType type;

  /// How hard it would push.
  final InterventionLevel level;

  /// Final score after context adjustments.
  final int importance;

  /// The session it concerns, when it concerns one.
  final String? sessionId;

  /// Why it will not be shown, or null when it will be.
  final SuppressionReason? suppressedBecause;

  /// Whether this will actually reach the user.
  bool get willDeliver => suppressedBecause == null;

  @override
  String toString() => willDeliver
      ? 'deliver(${type.name}, ${level.name}, score=$importance)'
      : 'hold(${type.name}, ${suppressedBecause!.name})';
}

/// Decides what to say and whether to say it.
///
/// No language model is involved here. The model may later write the *words*
/// for a chosen level, but the decision to interrupt, and how hard, is
/// deterministic so that it can be tested, tuned and explained.
class NudgeEngine {
  /// Creates an engine.
  const NudgeEngine({
    this.policy = const InterventionPolicy(),
    this.scorer = const ImportanceScorer(),
    this.suppression = const SuppressionPolicy(),
    this.giveUpAfterMinutes = 60,
  });

  /// Chooses how hard to push.
  final InterventionPolicy policy;

  /// Scores the cost of interrupting.
  final ImportanceScorer scorer;

  /// The hard gate.
  final SuppressionPolicy suppression;

  /// Minutes past a planned start after which Nova stops asking.
  ///
  /// A block nobody started an hour ago is not a live conversation, it is
  /// work that needs moving. Without this the engine will nag about the same
  /// dead session until the end of the day, which is exactly the failure mode
  /// that gets accountability apps muted.
  final int giveUpAfterMinutes;

  /// Evaluates [state] at [now].
  ///
  /// Returns a decision for every candidate, including the ones held back, so
  /// the caller can log what Nova chose not to do. At most one decision in the
  /// list will have [NudgeDecision.willDeliver] set: Nova speaks once per
  /// tick, about the thing that matters most.
  List<NudgeDecision> tick(DateTime now, NudgeEngineState state) {
    assert(now.isUtc, 'now must be UTC');

    final minutesSinceLast = state.lastNudgeAt == null
        ? null
        : now.difference(state.lastNudgeAt!).inMinutes;

    final candidates = <_Candidate>[];
    for (final context in state.sessions) {
      final candidate = _evaluate(now, context, state, minutesSinceLast);
      if (candidate != null) candidates.add(candidate);
    }

    if (candidates.isEmpty) return const [];

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Deterministic tie-break: the block that came due first wins.
      return a.context.session.plannedStart.compareTo(
        b.context.session.plannedStart,
      );
    });

    final decisions = <NudgeDecision>[];
    var delivered = false;
    for (final candidate in candidates) {
      var blocked = candidate.blocked;

      if (blocked == null && !scorer.clearsThreshold(candidate.score)) {
        blocked = SuppressionReason.belowThreshold;
      }
      if (blocked == null && delivered) {
        blocked = SuppressionReason.supersededByHigherPriority;
      }
      if (blocked == null) delivered = true;

      decisions.add(
        NudgeDecision(
          type: candidate.type,
          level: candidate.level,
          importance: candidate.score,
          sessionId: candidate.context.session.id,
          suppressedBecause: blocked,
        ),
      );
    }
    return decisions;
  }

  _Candidate? _evaluate(
    DateTime now,
    SessionContext context,
    NudgeEngineState state,
    int? minutesSinceLast,
  ) {
    final session = context.session;

    // Nothing to say about work that is finished, already running, or not yet
    // due.
    if (session.isResolved) return null;
    if (session.hasStarted) return null;
    if (now.isBefore(session.plannedStart)) return null;

    final late = session.minutesLate(now);
    if (late > giveUpAfterMinutes) return null;
    final type = late == 0 ? NudgeType.sessionStart : NudgeType.sessionMissed;
    final hoursToDeadline = context.task.hoursUntilDeadline(now);

    final level = policy.select(
      InterventionContext(
        minutesLate: late,
        rescheduleCount: session.rescheduleCount,
        hoursToDeadline: hoursToDeadline,
        priorResponses: context.priorResponses,
        userGaveReason: context.userGaveReason,
        userRefused: context.userRefused,
      ),
    );

    final ignoredHere = context.priorResponses
        .where(
          (r) => r == ResponseType.ignored || r == ResponseType.dismissed,
        )
        .length;
    final dismissals = ignoredHere > 0
        ? ignoredHere
        : (state.consecutiveDismissals[type] ?? 0);
    final continues = state.lastNudgeSessionId == session.id;

    final score = scorer.score(
      ScoringContext(
        type: type,
        hoursToDeadline: hoursToDeadline,
        rescheduleCount: session.rescheduleCount,
        minutesSinceLastNudge: minutesSinceLast,
        consecutiveDismissals: dismissals,
        continuesSameSession: continues,
      ),
    );

    final gate = suppression.evaluate(
      SuppressionContext(
        type: type,
        now: now,
        focusInProgress: state.focusInProgress,
        minutesSinceLastNudge: minutesSinceLast,
        consecutiveDismissals: dismissals,
        deviceDoNotDisturb: state.deviceDoNotDisturb,
        continuesSameSession: continues,
      ),
    );

    // Saying the same thing again is worse than saying nothing.
    final repeats = state.lastLevelBySession[session.id] == level;

    return _Candidate(
      context: context,
      type: type,
      level: level,
      score: score,
      blocked:
          gate.reason ?? (repeats ? SuppressionReason.nothingNewToSay : null),
    );
  }
}

class _Candidate {
  _Candidate({
    required this.context,
    required this.type,
    required this.level,
    required this.score,
    required this.blocked,
  });

  final SessionContext context;
  final NudgeType type;
  final InterventionLevel level;
  final int score;
  final SuppressionReason? blocked;
}
