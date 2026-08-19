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
}
