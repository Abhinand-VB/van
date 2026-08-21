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
  });

  /// How hard Van is currently pushing. Chosen by `InterventionPolicy`, never
  /// by a model.
  final InterventionLevel level;

  /// How long the block is now.
  final int currentMinutes;

  /// Hours until the task is due, if it has a deadline.
  final double? hoursToDeadline;
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

  /// Which actions [level] permits.
  ///
  /// The ordering is the ladder itself: Van only gains the right to give
  /// ground as it climbs. Level 5 is the only one that may let a block go,
  /// because conceding is what level 5 *is*.
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
        return null;
    }
  }

  /// Whether [proposal] may be applied as-is.
  bool permits(NegotiationProposal proposal, NegotiationContext context) =>
      reject(proposal, context) == null;
}
