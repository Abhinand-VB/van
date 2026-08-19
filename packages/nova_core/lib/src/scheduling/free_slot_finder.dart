import 'package:nova_core/src/scheduling/time_window.dart';

/// Works out when the user is actually free.
///
/// Pure and stateless: the same inputs always produce the same slots, which is
/// what lets the simulation harness replay a week deterministically.
class FreeSlotFinder {
  /// Creates a finder that schedules only inside [waking].
  const FreeSlotFinder({this.waking = const WakingHours()});

  /// The hours work may be placed in.
  final WakingHours waking;

  /// Every free stretch between [from] and [to], earliest first.
  ///
  /// Slots never cross a waking boundary: a gap running from 22:00 to 09:00
  /// the next morning comes back as two slots, not one, because nobody works
  /// through the night and a scheduler that thinks they do will produce plans
  /// the user ignores.
  List<FreeSlot> find({
    required List<Commitment> commitments,
    required DateTime from,
    required DateTime to,
  }) {
    assert(from.isUtc && to.isUtc, 'horizon must be UTC');
    if (!from.isBefore(to)) return const [];

    final windows = _wakingWindows(from, to);
    final busy = _normalise(commitments);

    final slots = <FreeSlot>[];
    for (final window in windows) {
      slots.addAll(_subtract(window, busy));
    }
    return slots;
  }

  /// The waking window of every local day the horizon touches, clipped to the
  /// horizon itself.
  List<FreeSlot> _wakingWindows(DateTime from, DateTime to) {
    final windows = <FreeSlot>[];
    // Step by local day. Starting one day early covers the case where `from`
    // falls inside the previous local day's window.
    var cursor = from.subtract(const Duration(days: 1));
    while (cursor.isBefore(to.add(const Duration(days: 1)))) {
      final window = waking.windowForDayOf(cursor);
      final clipped = window.clippedFrom(from)?.clippedTo(to);
      if (clipped != null && !windows.contains(clipped)) {
        windows.add(clipped);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    windows.sort((a, b) => a.start.compareTo(b.start));
    return windows;
  }

  /// Sorts commitments and merges any that overlap or touch, so the
  /// subtraction below only ever has to walk forwards.
  List<Commitment> _normalise(List<Commitment> commitments) {
    if (commitments.isEmpty) return const [];
    final sorted = [...commitments]..sort((a, b) => a.start.compareTo(b.start));

    final merged = <Commitment>[sorted.first];
    for (final next in sorted.skip(1)) {
      final last = merged.last;
      if (!next.start.isAfter(last.end)) {
        if (next.end.isAfter(last.end)) {
          merged[merged.length - 1] = Commitment(
            start: last.start,
            end: next.end,
            label: last.label,
          );
        }
      } else {
        merged.add(next);
      }
    }
    return merged;
  }

  /// Removes [busy] from [window], returning whatever survives.
  List<FreeSlot> _subtract(FreeSlot window, List<Commitment> busy) {
    final result = <FreeSlot>[];
    var cursor = window.start;

    for (final commitment in busy) {
      if (!commitment.end.isAfter(cursor)) continue;
      if (!commitment.start.isBefore(window.end)) break;

      if (commitment.start.isAfter(cursor)) {
        result.add(FreeSlot(start: cursor, end: commitment.start));
      }
      if (commitment.end.isAfter(cursor)) cursor = commitment.end;
      if (!cursor.isBefore(window.end)) return result;
    }

    if (cursor.isBefore(window.end)) {
      result.add(FreeSlot(start: cursor, end: window.end));
    }
    return result;
  }
}
