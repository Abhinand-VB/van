import 'package:van_core/van_core.dart';

/// The one place in Van allowed to read the wall clock.
///
/// Everything else takes a [Clock] so it can be driven by `FakeClock` in tests
/// and by the simulation harness. `tool/check_layers.dart` enforces this: a
/// `DateTime.now()` anywhere but here and `main.dart` fails the build.
class SystemClock implements Clock {
  /// Creates a clock backed by the device's current time.
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  /// The device's current offset from UTC.
  ///
  /// Lives here rather than beside its only caller because this file is one
  /// of exactly two allowed to read the wall clock, and `timeZoneOffset` is a
  /// wall-clock read like any other. `TimezoneWatcher` asks this class rather
  /// than asking Dart.
  Duration utcOffset() => DateTime.now().timeZoneOffset;
}
