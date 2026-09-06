import 'package:van/platform/calendars.dart';
import 'package:van_core/van_core.dart';

/// A device calendar Van can be planned against without a phone.
///
/// Holds entries as instants rather than pretending to be a provider: the
/// query semantics being faked are simply "everything overlapping the window,
/// minus the calendars you excluded", and anything more elaborate would be
/// testing the fake.
class FakeCalendars implements Calendars {
  /// Entries the device would return.
  final entries = <CalendarEntry>[];

  /// Calendars the device says it has.
  final sourceList = <CalendarSource>[];

  /// Whether the OS has granted read access.
  bool granted = false;

  /// What [requestPermission] should answer. Null leaves the state alone,
  /// which is what happens when the user walks away from the dialog.
  bool? grantOnRequest;

  /// How many times permission has been asked for.
  int requests = 0;

  /// The windows [between] was called with, so a test can assert Van reads at
  /// plan time rather than from something it cached earlier.
  final reads = <({DateTime from, DateTime to, Set<String> exclude})>[];

  /// When set, every read throws this.
  ///
  /// Stands in for the permission being revoked mid-session, the provider
  /// erroring, or the read timing out - the three ways this fails on a real
  /// phone, all of which must leave the capture standing. Typed as an
  /// [Exception] because that is what the channel actually throws: a
  /// `PlatformException`. The service still catches wider than this, which is
  /// the right asymmetry for a path whose promise is that nothing gets out.
  Exception? failure;

  @override
  Future<bool> hasPermission() async {
    final thrown = failure;
    // Permission is read on the same path as the entries, so a fault that
    // only appeared for one of the two would let a test pass while the real
    // failure mode went untested.
    if (thrown != null) throw thrown;
    return granted;
  }

  @override
  Future<bool> requestPermission() async {
    requests++;
    final grant = grantOnRequest;
    if (grant != null) granted = grant;
    return granted;
  }

  @override
  Future<List<CalendarSource>> sources() async {
    final thrown = failure;
    if (thrown != null) throw thrown;
    return List.unmodifiable(sourceList);
  }

  @override
  Future<List<CalendarEntry>> between({
    required DateTime from,
    required DateTime to,
    Set<String> exclude = const {},
  }) async {
    final thrown = failure;
    if (thrown != null) throw thrown;
    reads.add((from: from, to: to, exclude: exclude));

    return [
      for (final entry in entries)
        if (!exclude.contains(entry.calendarId))
          if (entry.start.isBefore(to) && from.isBefore(entry.end)) entry,
    ];
  }
}
