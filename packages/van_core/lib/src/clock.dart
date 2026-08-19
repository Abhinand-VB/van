/// Ambient time is banned in Van's domain core.
///
/// Every time-dependent class takes a [Clock] so that a whole simulated week
/// can run inside a unit test in microseconds. See docs/ARCHITECTURE.md P2.
///
/// The real implementation lives in the app layer
/// (`lib/platform/system_clock.dart`) because it is the single place allowed to
/// call `DateTime.now()`. The core ships only the contract and a test double.
abstract interface class Clock {
  /// The current instant, always in UTC.
  DateTime now();
}

/// A [Clock] that only moves when a test tells it to.
///
/// This is shipped in `lib/` rather than `test/` because the app's own tests
/// and the simulation harness both depend on it.
class FakeClock implements Clock {
  /// Creates a clock parked at [start]. Coerced to UTC.
  FakeClock(DateTime start) : _now = start.toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves time forward by [delta]. Rejects negative durations: time in Van
  /// never runs backwards, and a test that wants an earlier instant should
  /// construct a new clock.
  void advance(Duration delta) {
    if (delta.isNegative) {
      throw ArgumentError.value(delta, 'delta', 'must not be negative');
    }
    _now = _now.add(delta);
  }

  /// Jumps to [target]. Rejects instants at or before the current time.
  void advanceTo(DateTime target) {
    final next = target.toUtc();
    if (!next.isAfter(_now)) {
      throw ArgumentError.value(
        target,
        'target',
        'must be strictly after the current time ($_now)',
      );
    }
    _now = next;
  }
}
