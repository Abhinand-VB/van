import 'package:meta/meta.dart';
import 'package:van_core/src/clock.dart';
import 'package:van_core/src/model/work_session.dart';
import 'package:van_core/src/scheduling/rescheduler.dart';
import 'package:van_core/src/scheduling/time_window.dart';

/// Why a stale block was abandoned rather than moved.
enum SweepSkipReason {
  /// No free slot big enough remains in the horizon.
  noSlotAvailable,

  /// Every remaining slot falls after the task's deadline.
  pastDeadline,

  /// This work has already been moved too many times. Moving it again is
  /// pretending, and pretending costs the user three more notifications.
  tooManyMoves,
}

/// A block the sweep may act on, with the deadline that bounds where it can
/// go.
///
/// Deliberately not a `Task`: the sweep needs one date off the task and
/// nothing else, and keeping the dependency that narrow means scheduling never
/// has to know what a task is.
@immutable
class SweepCandidate {
  /// Creates a candidate.
  const SweepCandidate({required this.session, this.deadline});

  /// The block in question.
  final WorkSession session;

  /// When the underlying task is due, if it is due at all. UTC.
  final DateTime? deadline;
}

/// What the sweep decided about one abandoned block.
///
/// [stale] is already transitioned - `rescheduled` when a replacement was
/// found, `skipped` when it was not - so the caller persists what it is given
/// rather than re-deriving the status and getting it subtly wrong.
@immutable
class SweepOutcome {
  /// Creates an outcome.
  const SweepOutcome({
    required this.stale,
    this.replacement,
    this.skipReason,
  }) : assert(
         (replacement == null) != (skipReason == null),
         'an outcome is either a move or a skip, never both or neither',
       );

  /// The original block, with its closing status already applied.
  final WorkSession stale;

  /// The new home for the work, or null when there was nowhere to put it.
  final WorkSession? replacement;

  /// Why the work was dropped, or null when it was moved.
  final SweepSkipReason? skipReason;

  /// Whether the work survived the sweep.
  bool get wasMoved => replacement != null;
}

/// Moves work that was quietly abandoned.
///
/// `NudgeEngine` stops nudging about a block roughly an hour past its start,
/// which is right - an hour-dead session is not a live conversation. But
/// stopping the nudges is only half an answer: without this sweep the block
/// keeps its `planned` status forever, never comes due again, and the work
/// disappears from the plan without anyone deciding it should.
///
/// The sweep is the other half. It runs off a trigger the app already has -
/// opening the app - rather than a background isolate, which is the same
/// tradeoff WP-4 made for notifications and for the same reason.
class StaleSessionSweep {
  /// Creates a sweep.
  const StaleSessionSweep({
    required this.rescheduler,
    this.giveUpAfterMinutes = 60,
    this.maxMoves = 5,
  });

  /// Finds new homes for the blocks the sweep decides to move.
  final Rescheduler rescheduler;

  /// Minutes past a planned start after which a block counts as abandoned.
  ///
  /// Must match `NudgeEngine.giveUpAfterMinutes`. If the sweep threshold were
  /// higher there would be a window in which Van has stopped asking and not
  /// yet moved anything, which is the exact hole this class exists to close.
  final int giveUpAfterMinutes;

  /// Moves after which the sweep stops rescuing a piece of work.
  ///
  /// Sits deliberately above `InterventionPolicy.renegotiateAfterMoves`, so
  /// Van has already named the pattern to the user before it gives up on the
  /// block by itself.
  final int maxMoves;

  /// Whether [session] is abandoned as of [now].
  bool isStale(WorkSession session, DateTime now) =>
      session.status == SessionStatus.planned &&
      !session.hasStarted &&
      session.minutesLate(now) > giveUpAfterMinutes;

  /// Decides what happens to every abandoned block in [candidates].
  ///
  /// [slots] must describe the time still free after the *live* sessions are
  /// accounted for; the stale ones are being vacated and should not be passed
  /// in as commitments. Placements are subtracted from the running slot list
  /// as they are made, so two abandoned blocks are never sent to the same
  /// half hour.
  ///
  /// Oldest first, so that when free time is scarce the work that has been
  /// waiting longest gets it.
  List<SweepOutcome> run({
    required List<SweepCandidate> candidates,
    required List<FreeSlot> slots,
    required Clock clock,
  }) {
    final now = clock.now();
    assert(now.isUtc, 'now must be UTC');

    final stale = candidates.where((c) => isStale(c.session, now)).toList()
      ..sort(
        (a, b) => a.session.plannedStart.compareTo(b.session.plannedStart),
      );
    if (stale.isEmpty) return const [];

    var remaining = List<FreeSlot>.from(slots);
    final outcomes = <SweepOutcome>[];

    for (final candidate in stale) {
      final session = candidate.session;

      if (session.rescheduleCount >= maxMoves) {
        outcomes.add(
          SweepOutcome(
            stale: session.skip(),
            skipReason: SweepSkipReason.tooManyMoves,
          ),
        );
        continue;
      }

      final moved = rescheduler.reschedule(
        missed: session,
        slots: remaining,
        clock: clock,
        deadline: candidate.deadline,
      );

      final replacement = moved.okOrNull;
      if (replacement == null) {
        outcomes.add(
          SweepOutcome(
            stale: session.skip(),
            skipReason: switch (moved.errOrNull!.kind) {
              RescheduleFailureKind.pastDeadline =>
                SweepSkipReason.pastDeadline,
              RescheduleFailureKind.noSlotAvailable =>
                SweepSkipReason.noSlotAvailable,
            },
          ),
        );
        continue;
      }

      remaining = _without(
        remaining,
        from: replacement.plannedStart,
        to: replacement.plannedEnd,
      );
      outcomes.add(
        SweepOutcome(
          stale: session.markRescheduled(),
          replacement: replacement,
        ),
      );
    }

    return outcomes;
  }

  /// Returns [slots] with the span `[from, to)` removed, splitting any slot
  /// that straddles it.
  static List<FreeSlot> _without(
    List<FreeSlot> slots, {
    required DateTime from,
    required DateTime to,
  }) {
    final kept = <FreeSlot>[];
    for (final slot in slots) {
      if (!slot.start.isBefore(to) || !from.isBefore(slot.end)) {
        kept.add(slot);
        continue;
      }
      final before = slot.clippedTo(from);
      if (before != null) kept.add(before);
      final after = slot.clippedFrom(to);
      if (after != null) kept.add(after);
    }
    return kept;
  }
}
