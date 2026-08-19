import 'package:meta/meta.dart';
import 'package:van_core/src/model/nudge.dart';

/// The tunable numbers behind the scoring formula.
///
/// Kept in a value object rather than as constants so the simulation harness
/// can sweep them, and so `assets/policy.json` can override them without a
/// rebuild. These are the dials that decide whether Van feels present or
/// feels like spam.
@immutable
class ScoringWeights {
  /// Creates a weight set.
  const ScoringWeights({
    this.deliveryThreshold = 5,
    this.deadlineWithin24h = 2,
    this.deadlineWithin6h = 3,
    this.perMoveBoost = 1,
    this.maxMoveBoost = 3,
    this.recentNudgeMinutes = 20,
    this.recentNudgePenalty = 3,
    this.samehourNudgePenalty = 1,
    this.perDismissalPenalty = 2,
  });

  /// Minimum score required to interrupt.
  final int deliveryThreshold;

  /// Added when the deadline is inside a day.
  final int deadlineWithin24h;

  /// Added instead when the deadline is inside six hours.
  final int deadlineWithin6h;

  /// Added per prior move of this work.
  final int perMoveBoost;

  /// Cap on the move boost, so a chronically postponed task cannot escalate
  /// without limit.
  final int maxMoveBoost;

  /// Window that counts as "just interrupted them".
  final int recentNudgeMinutes;

  /// Subtracted inside that window.
  final int recentNudgePenalty;

  /// Subtracted within the hour.
  final int samehourNudgePenalty;

  /// Subtracted per consecutive dismissal of this nudge type.
  final int perDismissalPenalty;
}

/// The inputs to a single scoring decision.
@immutable
class ScoringContext {
  /// Creates a context.
  const ScoringContext({
    required this.type,
    this.hoursToDeadline,
    this.rescheduleCount = 0,
    this.minutesSinceLastNudge,
    this.consecutiveDismissals = 0,
    this.continuesSameSession = false,
  });

  /// The kind of nudge being considered.
  final NudgeType type;

  /// Hours until the related task is due, if any.
  final double? hoursToDeadline;

  /// How many times this work has been moved.
  final int rescheduleCount;

  /// Minutes since the last delivered nudge of any kind. Null if none yet.
  final int? minutesSinceLastNudge;

  /// Consecutive unanswered nudges of this type today.
  final int consecutiveDismissals;

  /// Whether this continues an escalation about the session the last nudge
  /// was already about.
  ///
  /// When it does, the recency and fatigue penalties are skipped: they exist
  /// to stop Van hopping between topics, and applying them inside a single
  /// conversation drives the score below threshold before the ladder can
  /// reach L1. The hard limits in SuppressionPolicy remain in force.
  final bool continuesSameSession;
}

/// Turns context into a number, so that interrupting someone is a decision
/// with a visible cost rather than an implicit one.
class ImportanceScorer {
  /// Creates a scorer.
  const ImportanceScorer({this.weights = const ScoringWeights()});

  /// The dials.
  final ScoringWeights weights;

  /// Scores [context]. Result is clamped to 0-10.
  int score(ScoringContext context) {
    var value = context.type.baseImportance;

    final hours = context.hoursToDeadline;
    if (hours != null) {
      if (hours < 6) {
        value += weights.deadlineWithin6h;
      } else if (hours < 24) {
        value += weights.deadlineWithin24h;
      }
    }

    value += (context.rescheduleCount * weights.perMoveBoost).clamp(
      0,
      weights.maxMoveBoost,
    );

    if (!context.continuesSameSession) {
      final since = context.minutesSinceLastNudge;
      if (since != null) {
        if (since < weights.recentNudgeMinutes) {
          value -= weights.recentNudgePenalty;
        } else if (since < 60) {
          value -= weights.samehourNudgePenalty;
        }
      }
      value -= context.consecutiveDismissals * weights.perDismissalPenalty;
    }

    return value.clamp(0, 10);
  }

  /// Whether a nudge scoring [value] clears the bar for interrupting.
  bool clearsThreshold(int value) => value >= weights.deliveryThreshold;
}
