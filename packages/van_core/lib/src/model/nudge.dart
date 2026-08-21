import 'package:meta/meta.dart';

/// The kinds of interruption Van can make, with their baseline importance.
///
/// Importance is the first term in the scoring formula in
/// docs/ARCHITECTURE.md section 6.2. It is deliberately attached to the type
/// rather than computed, so that the cost of interrupting someone is a visible
/// constant a human can argue with.
enum NudgeType {
  /// Drink something. Cheap to ignore, cheap to send.
  hydration(baseImportance: 2),

  /// You have been sitting a long time.
  stand(baseImportance: 2),

  /// A planned session is due right now.
  sessionStart(baseImportance: 6),

  /// A planned session is due and nothing has happened.
  sessionMissed(baseImportance: 7),

  /// Something is due within a day and is not close to done.
  deadlineTomorrow(baseImportance: 8),

  /// A hard commitment starts in minutes. The only routinely urgent nudge.
  meetingImminent(baseImportance: 10),

  /// Demonstrably off-task during a block you committed to. Phase 4.
  distractionDuringSession(baseImportance: 7)
  ;

  const NudgeType({required this.baseImportance});

  /// Baseline cost-to-interrupt, 0-10.
  final int baseImportance;
}

/// How hard Van pushes, from a gentle prompt to giving up gracefully.
///
/// The level is chosen deterministically by `InterventionPolicy`. A language
/// model may write the words for a level, but never picks the level itself.
/// That separation is what keeps escalation predictable and tunable.
enum InterventionLevel {
  /// A plain prompt that the block is due.
  l0Gentle,

  /// A check that it has not started yet, offering to move it.
  l1Check,

  /// Asking what is in the way.
  l2Diagnose,

  /// Offering a much smaller version of the same work.
  l3Shrink,

  /// Naming the pattern of repeated moves against a near deadline.
  l4Renegotiate,

  /// Accepting the answer and moving the work on.
  l5Concede,
}

/// One interruption: what Van decided to say, when, and whether it was
/// actually allowed out.
///
/// Suppressed nudges are recorded too. Knowing what Van decided *not* to send
/// is as informative as what it did send, and it is the only way to tell a
/// quiet day from a broken scheduler.
@immutable
class Nudge {
  /// Creates a nudge record. All instants must be UTC.
  Nudge({
    required this.id,
    required this.type,
    required this.importance,
    required this.level,
    required this.scheduledAt,
    required this.copy,
    this.sessionId,
    this.deliveredAt,
    this.templateId,
    this.backendId,
    this.wasSuppressed = false,
    this.suppressionReason,
  }) : assert(scheduledAt.isUtc, 'scheduledAt must be UTC'),
       assert(
         !wasSuppressed || suppressionReason != null,
         'a suppressed nudge must record why',
       );

  /// Stable identifier.
  final String id;

  /// The session this is about, when it is about one.
  final String? sessionId;

  /// What kind of interruption this is.
  final NudgeType type;

  /// Final score after context adjustments, not the baseline.
  final int importance;

  /// How hard this one pushes.
  final InterventionLevel level;

  /// When it was due to fire. UTC.
  final DateTime scheduledAt;

  /// When it actually reached the user. Null if suppressed or still pending.
  final DateTime? deliveredAt;

  /// The text shown.
  final String copy;

  /// Which template produced [copy], when a template did.
  final String? templateId;

  /// Which inference backend produced [copy], when a model did. Null means the
  /// deterministic fallback wrote it.
  final String? backendId;

  /// Whether the suppression policy blocked this before it was shown.
  final bool wasSuppressed;

  /// Why it was blocked. Always set when [wasSuppressed].
  final String? suppressionReason;

  /// Whether this actually reached the user.
  bool get wasDelivered => deliveredAt != null && !wasSuppressed;

  /// Records delivery at [at].
  Nudge deliver(DateTime at) => Nudge(
    id: id,
    type: type,
    importance: importance,
    level: level,
    scheduledAt: scheduledAt,
    copy: copy,
    sessionId: sessionId,
    deliveredAt: at,
    templateId: templateId,
    backendId: backendId,
  );

  /// Records that this was held back, for [reason].
  ///
  /// A method rather than a hand-built copy at the call site: the class has
  /// twelve fields and a copy that quietly dropped one - the template id, say -
  /// would corrupt the record without failing anything.
  Nudge suppress(String reason) => Nudge(
    id: id,
    type: type,
    importance: importance,
    level: level,
    scheduledAt: scheduledAt,
    copy: copy,
    sessionId: sessionId,
    deliveredAt: deliveredAt,
    templateId: templateId,
    backendId: backendId,
    wasSuppressed: true,
    suppressionReason: reason,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Nudge &&
          id == other.id &&
          sessionId == other.sessionId &&
          type == other.type &&
          importance == other.importance &&
          level == other.level &&
          scheduledAt == other.scheduledAt &&
          deliveredAt == other.deliveredAt &&
          copy == other.copy &&
          templateId == other.templateId &&
          backendId == other.backendId &&
          wasSuppressed == other.wasSuppressed &&
          suppressionReason == other.suppressionReason;

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    type,
    importance,
    level,
    scheduledAt,
    deliveredAt,
    copy,
    templateId,
    backendId,
    wasSuppressed,
    suppressionReason,
  );

  @override
  String toString() => wasSuppressed
      ? 'Nudge($id, ${type.name}, SUPPRESSED: $suppressionReason)'
      : 'Nudge($id, ${type.name}, ${level.name})';
}
