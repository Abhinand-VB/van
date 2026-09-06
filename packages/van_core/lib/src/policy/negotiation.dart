import 'package:meta/meta.dart';
import 'package:van_core/src/model/nudge.dart';
import 'package:van_core/src/policy/intervention_policy.dart';

/// What Van proposes doing about a block the user is not starting.
enum NegotiationAction {
  /// Ask again, unchanged. The deal on the table is still the deal.
  hold,

  /// Offer a smaller version of the same work.
  shrink,

  /// Move the whole block later today.
  defer,

  /// Let it go for now. The work stays; this block does not.
  release,
}

/// Why a proposal was refused.
enum NegotiationRejection {
  /// The level Van is at does not permit this action. An l0 prompt cannot
  /// decide to cancel your afternoon.
  actionExceedsLevel,

  /// A shrink that is not smaller, or is too small to be work.
  shrinkOutOfRange,

  /// A delay that is instant, or long enough to be a cancellation wearing a
  /// disguise.
  deferOutOfRange,

  /// The move would land the work after the thing it was due for.
  deferPastDeadline,

  /// The action needs a size or a delay and did not carry one.
  missingAmount,

  /// Nothing to say to the user.
  emptyMessage,

  /// A move proposed for work the log says moving does not help.
  ///
  /// Distinct from [deferOutOfRange], which is about the *size* of the delay.
  /// This one is about the delay being the wrong idea at all: the block has
  /// been moved several times and has never once been started, so a further
  /// move is the reflex rather than the answer.
  deferAgainstEvidence,
}

/// What the log already knows about a block that is not starting.
///
/// **All of this existed before and none of it reached the decision.**
/// `Negotiate` saw the ladder rung and the block length; the move count, the
/// start history and the calendar were sitting in the database being used for
/// nothing. That is the whole of `WP_JUDGEMENT.md` 13c.
///
/// Counts rather than conclusions, on purpose. "Two starts out of nine
/// blocks at this hour" is a fact that survives a change of mind about what
/// it means; "the user is bad at mornings" is a judgement baked in at the
/// wrong layer, and the rules below are where judgements belong.
@immutable
class NegotiationEvidence {
  /// Creates an evidence set. Every field defaults to "nothing known", so a
  /// caller that cannot supply a piece is indistinguishable from one that had
  /// nothing to supply - which is the honest reading of both.
  const NegotiationEvidence({
    this.moves = 0,
    this.everStarted = false,
    this.startsAtThisHour = 0,
    this.blocksAtThisHour = 0,
    this.calendarBusyMinutes = 0,
    this.calendarWindowMinutes = 0,
  });

  /// Nothing is known. The state before 13c, and the state in every caller
  /// that has no history to read.
  static const none = NegotiationEvidence();

  /// How many times this piece of work has already been moved.
  final int moves;

  /// Whether any block in this chain of reschedules was ever started.
  ///
  /// The distinction that matters most here. Four moves where the user
  /// started each time and ran out of time is a task that is too big; four
  /// moves where they never began is a task that is never going to start at
  /// that size, and the two want opposite answers.
  final bool everStarted;

  /// How many blocks scheduled at this hour of day were actually started.
  final int startsAtThisHour;

  /// How many blocks have been scheduled at this hour of day at all.
  final int blocksAtThisHour;

  /// Minutes of the stretch around this block that the calendar already
  /// claims.
  final int calendarBusyMinutes;

  /// How long that stretch is. Zero when no calendar was read.
  final int calendarWindowMinutes;

  /// Whether there is enough history at this hour for the rate to mean
  /// anything.
  ///
  /// Three is a low bar and deliberately so: this number is offered to a
  /// model as context, not used to refuse anything, and the alternative to a
  /// low bar is a field that stays null for the first fortnight of use.
  bool get hasHourHistory => blocksAtThisHour >= 3;

  /// The share of blocks at this hour that were started, or null when there
  /// is not enough history to say.
  double? get startRateAtHour =>
      hasHourHistory ? startsAtThisHour / blocksAtThisHour : null;

  /// The share of the surrounding stretch the calendar has already claimed.
  double get calendarDensity => calendarWindowMinutes == 0
      ? 0
      : calendarBusyMinutes / calendarWindowMinutes;

  /// Whether moving this again is the reflex rather than the answer.
  ///
  /// Both halves are required. Moves alone are not evidence of anything - a
  /// block that moved three times and was worked on each time is a plan
  /// adapting, which is what Van is for.
  bool movingHasNotWorked({required int afterMoves}) =>
      !everStarted && moves >= afterMoves;

  @override
  String toString() =>
      'NegotiationEvidence(moves=$moves, everStarted=$everStarted, '
      'hour=$startsAtThisHour/$blocksAtThisHour, '
      'calendar=$calendarBusyMinutes/$calendarWindowMinutes)';
}

/// One proposed way out of a stalled block, plus the words for it.
///
/// This is a *proposal*, never an applied change. It exists as a separate type
/// precisely so that something produced by a language model can be handed to
/// the domain and refused. See `NegotiationRules`.
@immutable
class NegotiationProposal {
  /// Creates a proposal.
  const NegotiationProposal({
    required this.action,
    required this.message,
    this.shrinkToMinutes,
    this.deferByMinutes,
    this.templateId,
  });

  /// What to do about the block.
  final NegotiationAction action;

  /// What to say to the user. One line.
  final String message;

  /// New block length, when [action] is [NegotiationAction.shrink].
  final int? shrinkToMinutes;

  /// How much later to place it, when [action] is [NegotiationAction.defer].
  final int? deferByMinutes;

  /// Which template wrote [message], or null when a model did.
  final String? templateId;

  /// Whether a model wrote the words.
  bool get fromModel => templateId == null;

  @override
  String toString() => switch (action) {
    NegotiationAction.shrink => 'shrink to ${shrinkToMinutes}m',
    NegotiationAction.defer => 'defer by ${deferByMinutes}m',
    _ => action.name,
  };
}

/// The facts a proposal is judged against.
@immutable
class NegotiationContext {
  /// Creates a context.
  const NegotiationContext({
    required this.level,
    required this.currentMinutes,
    this.hoursToDeadline,
    this.evidence = NegotiationEvidence.none,
  });

  /// How hard Van is currently pushing. Chosen by `InterventionPolicy`, never
  /// by a model.
  final InterventionLevel level;

  /// How long the block is now.
  final int currentMinutes;

  /// Hours until the task is due, if it has a deadline.
  final double? hoursToDeadline;

  /// What the log knows about this block. Defaults to knowing nothing.
  final NegotiationEvidence evidence;
}

/// Decides whether a proposed action is one Van is allowed to take.
///
/// The whole reason `negotiate` can be routed to a language model is that its
/// output passes through here first. A model may propose; it may not decide.
/// Without this class, routing `negotiate` to a cloud provider would hand that
/// provider the ability to quietly cancel the user's afternoon.
///
/// The binding constraint is the intervention level, which is always chosen
/// deterministically. Escalation stays predictable because the ladder, not the
/// model, sets the ceiling on what may be offered.
class NegotiationRules {
  /// Creates a rule set.
  const NegotiationRules({
    this.minimumBlockMinutes = 15,
    this.minimumDeferMinutes = 5,
    this.maximumDeferMinutes = 480,
    this.maximumMessageLength = 200,
    this.stopDeferringAfterMoves = 3,
  });

  /// Shortest block still worth calling work. Matches
  /// `PlannerConstraints.minSessionMinutes`.
  final int minimumBlockMinutes;

  /// A delay shorter than this is not a delay, it is a flicker.
  final int minimumDeferMinutes;

  /// A delay longer than this is a cancellation that will not say so.
  final int maximumDeferMinutes;

  /// Longest message Van will put in a notification.
  final int maximumMessageLength;

  /// After this many moves with no start, a further move is refused.
  ///
  /// Matched to `InterventionPolicy.renegotiateAfterMoves`, which is the
  /// point at which Van already names the pattern out loud. Refusing to keep
  /// moving at the same moment Van starts talking about the moving is the
  /// consistent position; refusing later would mean saying one thing and
  /// offering another.
  final int stopDeferringAfterMoves;

  /// Which actions [level] permits.
  ///
  /// The ordering is the ladder itself: Van only gains the right to give
  /// ground as it climbs. Level 5 is the only one that may let a block go,
  /// because conceding is what level 5 *is*.
  ///
  /// **Evidence is not consulted here, and that is a rule rather than an
  /// omission.** The ladder sets the ceiling on what may be offered, and
  /// evidence may only take options away from underneath it - never add one.
  /// If a bad reading of the log could *widen* what a model is permitted to
  /// propose, the whole argument for letting a model near this collapses.
  Set<NegotiationAction> allowedAt(InterventionLevel level) {
    if (InterventionPolicy.concedes(level)) {
      return NegotiationAction.values.toSet();
    }
    if (InterventionPolicy.offersShrink(level)) {
      return const {NegotiationAction.hold, NegotiationAction.shrink};
    }
    return const {NegotiationAction.hold};
  }

  /// Checks [proposal] against [context]. Null means it may be applied.
  ///
  /// Returning a reason rather than a bool because the caller logs it: a model
  /// that keeps proposing things it is not allowed to is a fact worth having
  /// in the event log before anyone trusts it with more.
  NegotiationRejection? reject(
    NegotiationProposal proposal,
    NegotiationContext context,
  ) {
    if (proposal.message.trim().isEmpty ||
        proposal.message.length > maximumMessageLength) {
      return NegotiationRejection.emptyMessage;
    }

    if (!allowedAt(context.level).contains(proposal.action)) {
      return NegotiationRejection.actionExceedsLevel;
    }

    switch (proposal.action) {
      case NegotiationAction.hold:
      case NegotiationAction.release:
        return null;

      case NegotiationAction.shrink:
        final to = proposal.shrinkToMinutes;
        if (to == null) return NegotiationRejection.missingAmount;
        if (to < minimumBlockMinutes || to >= context.currentMinutes) {
          return NegotiationRejection.shrinkOutOfRange;
        }
        return null;

      case NegotiationAction.defer:
        final by = proposal.deferByMinutes;
        if (by == null) return NegotiationRejection.missingAmount;
        if (by < minimumDeferMinutes || by > maximumDeferMinutes) {
          return NegotiationRejection.deferOutOfRange;
        }
        final hours = context.hoursToDeadline;
        if (hours != null && by / Duration.minutesPerHour > hours) {
          return NegotiationRejection.deferPastDeadline;
        }
        // The one place the log gets to overrule a proposal. Work that has
        // been moved three times and never once started does not need a
        // fourth time; it needs to be smaller, or to be let go. Both of those
        // remain on the table, so this narrows the answer rather than
        // refusing to answer.
        if (context.evidence.movingHasNotWorked(
          afterMoves: stopDeferringAfterMoves,
        )) {
          return NegotiationRejection.deferAgainstEvidence;
        }
        return null;
    }
  }

  /// Whether [proposal] may be applied as-is.
  bool permits(NegotiationProposal proposal, NegotiationContext context) =>
      reject(proposal, context) == null;
}
