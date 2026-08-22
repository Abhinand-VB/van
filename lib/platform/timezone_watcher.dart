import 'package:flutter/widgets.dart';
import 'package:van/platform/system_clock.dart';

/// Tells Van the device's UTC offset again whenever it comes back to the
/// foreground.
///
/// The offset was read once at startup and frozen, so a process alive across
/// a DST change or a flight went on planning in the zone it launched in.
/// Nothing in Flutter reports a timezone change directly, and Van has no
/// background isolate to notice one, so resume is the trigger available: it
/// is the moment the user is looking at the app, and the moment a wrong
/// offset would first show up as a block on the wrong day.
///
/// It reads the offset through [SystemClock] rather than calling
/// `DateTime.now()` itself: `tool/check_layers.dart` allows the wall clock in
/// exactly two files, and this is not one of them. Everything learned here is
/// handed downwards as a plain [Duration].
class TimezoneWatcher with WidgetsBindingObserver {
  /// Calls [onOffset] with the device's current offset on every resume.
  TimezoneWatcher(this.onOffset, {SystemClock clock = const SystemClock()})
    : _clock = clock;

  final SystemClock _clock;

  /// Receives the offset. Called on resume, whether or not it has changed -
  /// deciding that is the callee's job, since only it knows what it was.
  final void Function(Duration offset) onOffset;

  /// Starts listening. Safe to call once; [stop] undoes it.
  void start() => WidgetsBinding.instance.addObserver(this);

  /// Stops listening.
  void stop() => WidgetsBinding.instance.removeObserver(this);

  /// The offset right now, for the initial reading at startup.
  Duration currentOffset() => _clock.utcOffset();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onOffset(currentOffset());
  }
}
