import 'package:meta/meta.dart';
import 'package:nova_core/src/model/nudge.dart';
import 'package:nova_core/src/scheduling/time_window.dart';

/// The reasons Nova decides to stay quiet.
///
/// Recorded on every suppressed nudge, because a quiet day and a broken
/// scheduler look identical unless the silence explains itself.
enum SuppressionReason {
  /// Outside the user's waking hours.
  quietHours,

  /// A focus session is running. Nova must not interrupt work it asked for.
  focusInProgress,

  /// Something else interrupted them moments ago.
  tooSoonAfterLast,

  /// They have swiped this kind of nudge away repeatedly today.
  dismissalFatigue,

  /// The device is in do-not-disturb.
  deviceDoNotDisturb,

  /// The nudge was allowed but did not score highly enough to be worth the
  /// interruption. Set by the engine rather than the gate.
  belowThreshold,

  /// Something more important was already being raised in the same tick.
  /// Nova speaks once per tick, about the thing that matters most.
  supersededByHigherPriority,

  /// The ladder has not moved since the last nudge about this session, so
  /// speaking again would repeat the same words. Repetition is the fastest
  /// route to being ignored, so Nova waits until it has something new.
  nothingNewToSay,
}

/// The outcome of the suppression gate.
@immutable
class SuppressionDecision {
  /// Nova may interrupt.
  const SuppressionDecision.allow() : reason = null;

  /// Nova must stay quiet, because of [reason].
  const SuppressionDecision.suppress(SuppressionReason this.reason);

  /// Why the nudge was blocked, or null when it was allowed.
  final SuppressionReason? reason;

  /// Whether the nudge was blocked.
  bool get suppressed => reason != null;

  @override
  String toString() => suppressed ? 'suppressed(${reason!.name})' : 'allowed';
}

/// The facts the gate considers.
@immutable
class SuppressionContext {
  /// Creates a context.
  const SuppressionContext({
    required this.type,
    required this.now,
    this.focusInProgress = false,
    this.minutesSinceLastNudge,
    this.consecutiveDismissals = 0,
    this.deviceDoNotDisturb = false,
    this.continuesSameSession = false,
  });

  /// The kind of nudge being considered.
  final NudgeType type;

  /// The current instant, UTC.
  final DateTime now;

  /// Whether a session is running right now.
  final bool focusInProgress;

  /// Minutes since the last delivered nudge, or null if there has been none.
  final int? minutesSinceLastNudge;

  /// Consecutive unanswered nudges of this type today.
  final int consecutiveDismissals;

  /// Whether the OS is in do-not-disturb.
  final bool deviceDoNotDisturb;

  /// Whether the previous nudge was about this same session.
  ///
  /// Escalating about a block the user is currently ignoring is one
  /// conversation, not a series of fresh interruptions, so it is allowed to
  /// move faster than the general spacing rule.
  final bool continuesSameSession;
}

/// A hard gate, evaluated before any score is computed.
///
/// Notification fatigue is the top product risk for an app whose whole premise
/// is interrupting people, so this class gets the same rigour as the
/// scheduler. It answers one question: should Nova speak at all?
class SuppressionPolicy {
  /// Creates a policy.
  const SuppressionPolicy({
    this.waking = const WakingHours(),
    this.minimumGapMinutes = 20,
    this.escalationGapMinutes = 8,
    this.dismissalLimit = 3,
    this.overrideGapAtImportance = 8,
    this.overrideAllAtImportance = 10,
  });

  /// Used to decide what counts as quiet hours.
  final WakingHours waking;

  /// Minimum spacing between interruptions about different things.
  final int minimumGapMinutes;

  /// Minimum spacing while escalating about the same session. Shorter,
  /// because the ladder needs to reach L1 ten minutes in without the spacing
  /// rule silently swallowing it.
  final int escalationGapMinutes;

  /// Consecutive dismissals after which Nova stops raising this type today.
  final int dismissalLimit;

  /// Base importance that may ignore the spacing rule.
  final int overrideGapAtImportance;

  /// Base importance that may ignore quiet hours and do-not-disturb. Only a
  /// hard commitment starting in minutes reaches this.
  final int overrideAllAtImportance;

  /// Decides whether [context] may interrupt.
  SuppressionDecision evaluate(SuppressionContext context) {
    final importance = context.type.baseImportance;
    final overridesEverything = importance >= overrideAllAtImportance;

    if (!overridesEverything && _isQuietHours(context.now)) {
      return const SuppressionDecision.suppress(SuppressionReason.quietHours);
    }

    if (!overridesEverything && context.deviceDoNotDisturb) {
      return const SuppressionDecision.suppress(
        SuppressionReason.deviceDoNotDisturb,
      );
    }

    if (!overridesEverything && context.focusInProgress) {
      return const SuppressionDecision.suppress(
        SuppressionReason.focusInProgress,
      );
    }

    // Fatigue is checked before the spacing rule and cannot be overridden by
    // importance: someone who has dismissed three of these today has told
    // Nova something, and repeating it louder is the wrong answer.
    if (context.consecutiveDismissals >= dismissalLimit) {
      return const SuppressionDecision.suppress(
        SuppressionReason.dismissalFatigue,
      );
    }

    final gap = context.continuesSameSession
        ? escalationGapMinutes
        : minimumGapMinutes;
    final since = context.minutesSinceLastNudge;
    if (since != null && since < gap && importance < overrideGapAtImportance) {
      return const SuppressionDecision.suppress(
        SuppressionReason.tooSoonAfterLast,
      );
    }

    return const SuppressionDecision.allow();
  }

  bool _isQuietHours(DateTime now) {
    final window = waking.windowForDayOf(now);
    return now.isBefore(window.start) || !now.isBefore(window.end);
  }
}
