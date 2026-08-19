import 'package:meta/meta.dart';
import 'package:nova_core/src/clock.dart';
import 'package:nova_core/src/id_generator.dart';
import 'package:nova_core/src/model/work_session.dart';
import 'package:nova_core/src/result.dart';
import 'package:nova_core/src/scheduling/time_window.dart';

/// Why a missed block could not be moved.
enum RescheduleFailureKind {
  /// No free slot big enough remains.
  noSlotAvailable,

  /// Every remaining slot falls after the deadline.
  pastDeadline,
}

/// A move that could not be made.
@immutable
class RescheduleFailure {
  /// Creates a failure.
  const RescheduleFailure(this.kind);

  /// What went wrong.
  final RescheduleFailureKind kind;

  @override
  String toString() => 'RescheduleFailure(${kind.name})';
}

/// Moves work that did not happen.
///
/// Rescheduling is the single most frequent thing Nova does, and the move
/// count it maintains is what the escalation ladder reads to decide whether
/// this is the first slip or the fourth.
class Rescheduler {
  /// Creates a rescheduler.
  const Rescheduler({required this.ids, this.minimumLeadMinutes = 5});

  /// Supplies identifiers for replacement sessions.
  final IdGenerator ids;

  /// A replacement is never placed closer than this to the present, so the
  /// user is not nudged the instant they dismiss something.
  final int minimumLeadMinutes;

  /// Finds a new home for [missed].
  ///
  /// [shrinkTo] requests a smaller block, which is what the L3 intervention
  /// does when a full session is the thing the user cannot face. The
  /// replacement always carries an incremented move count and a link back to
  /// its parent, so the history survives.
  Result<WorkSession, RescheduleFailure> reschedule({
    required WorkSession missed,
    required List<FreeSlot> slots,
    required Clock clock,
    DateTime? deadline,
    int? shrinkTo,
  }) {
    final earliest = clock.now().add(Duration(minutes: minimumLeadMinutes));
    final wanted = shrinkTo ?? missed.plannedMinutes;

    final cutoff = deadline;
    var sawSlotButTooLate = false;

    for (final raw in slots) {
      var usable = raw.clippedFrom(earliest);
      if (usable == null) continue;

      if (cutoff != null) {
        final clipped = usable.clippedTo(cutoff);
        if (clipped == null) {
          sawSlotButTooLate = true;
          continue;
        }
        usable = clipped;
      }

      if (usable.minutes >= wanted) {
        return Ok(
          missed.replacement(
            newId: ids.next(),
            newStart: usable.start,
            newMinutes: wanted,
          ),
        );
      }
    }

    return Err(
      RescheduleFailure(
        sawSlotButTooLate
            ? RescheduleFailureKind.pastDeadline
            : RescheduleFailureKind.noSlotAvailable,
      ),
    );
  }
}
