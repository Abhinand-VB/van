import 'package:flutter/services.dart';
import 'package:van_core/van_core.dart';

/// One calendar on the device, as offered to the user for exclusion.
///
/// The account name is here because display names collide constantly - two
/// Google accounts both showing "Birthdays", a work and a personal
/// "Calendar" - and a list the user cannot tell apart is a list they cannot
/// safely edit.
class CalendarSource {
  /// Creates a source.
  const CalendarSource({
    required this.id,
    required this.name,
    required this.accountName,
    this.colour,
  });

  /// Provider id, stable for as long as the calendar exists on the device.
  final String id;

  /// What the calendar calls itself.
  final String name;

  /// The account it syncs with, or the local account name.
  final String accountName;

  /// The calendar's colour as an ARGB integer, when the provider gives one.
  final int? colour;

  @override
  String toString() => 'CalendarSource($id, $name, $accountName)';
}

/// Reads the device calendar. Never writes to it.
///
/// Van reads commitments; it does not create events. Putting work blocks on
/// the user's calendar is a separate decision with its own consequences, and
/// this interface deliberately offers no way to start making it.
///
/// Shaped like `Notifications`: an interface the app depends on, an Android
/// implementation over a method channel, and a fake in `test/support` so the
/// whole feature can be tested without a device.
abstract interface class Calendars {
  /// Whether the OS has granted Van read access.
  ///
  /// Read fresh every time. The user can revoke this from system settings at
  /// any moment, and Van finding out on the next restart is exactly the
  /// silent failure this exists to prevent.
  Future<bool> hasPermission();

  /// Asks for read access. Returns whether it was granted.
  Future<bool> requestPermission();

  /// Every calendar on the device.
  Future<List<CalendarSource>> sources();

  /// Every occurrence between [from] and [to], excluding calendars in
  /// [exclude].
  ///
  /// Returns entries, not commitments: which of them actually block is a
  /// domain decision and lives in [CalendarFilter], not here.
  Future<List<CalendarEntry>> between({
    required DateTime from,
    required DateTime to,
    Set<String> exclude = const {},
  });
}

/// The Android implementation, over a method channel.
///
/// Three methods and no cache. The OS already persists the calendar and is
/// the source of truth for it; a copy inside Van would have to be
/// invalidated, and there is no good moment to do that. Planning reads
/// through this a handful of times a day, which is not a hot path.
class MethodChannelCalendars implements Calendars {
  /// Creates a client for the platform channel.
  const MethodChannelCalendars();

  /// The channel name, matching `CalendarPlugin.CHANNEL` in Kotlin.
  static const channel = MethodChannel('dev.van.app/calendars');

  @override
  Future<bool> hasPermission() async =>
      await channel.invokeMethod<bool>('hasPermission') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<List<CalendarSource>> sources() async {
    final rows = await channel.invokeListMethod<Map<Object?, Object?>>(
      'sources',
    );
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[])
        _sourceFrom(row),
    ];
  }

  @override
  Future<List<CalendarEntry>> between({
    required DateTime from,
    required DateTime to,
    Set<String> exclude = const {},
  }) async {
    final rows = await channel.invokeListMethod<Map<Object?, Object?>>(
      'between',
      {
        'from': from.toUtc().millisecondsSinceEpoch,
        'to': to.toUtc().millisecondsSinceEpoch,
      },
    );

    // Excluded here rather than in the query. The Kotlin side moves rows
    // across the boundary and makes no decisions - the same rule the local
    // model channel follows - and the excluded set is a Van preference the
    // platform has no business knowing about.
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[])
        if (_entryFrom(row) case final entry?)
          if (!exclude.contains(entry.calendarId)) entry,
    ];
  }

  static CalendarSource _sourceFrom(Map<Object?, Object?> row) =>
      CalendarSource(
        id: '${row['id']}',
        name: row['name'] as String? ?? '',
        accountName: row['account'] as String? ?? '',
        colour: row['colour'] as int?,
      );

  /// Builds an entry, or null when the row cannot make one.
  ///
  /// A provider row with no instants is not an error worth failing a whole
  /// plan over - it is one entry Van cannot see. Dropping it keeps a single
  /// malformed row from costing the user their capture.
  static CalendarEntry? _entryFrom(Map<Object?, Object?> row) {
    final start = row['start'] as int?;
    final end = row['end'] as int?;
    if (start == null || end == null || end < start) return null;

    return CalendarEntry(
      calendarId: '${row['calendarId']}',
      start: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
      end: DateTime.fromMillisecondsSinceEpoch(end, isUtc: true),
      isAllDay: row['allDay'] as bool? ?? false,
      isBusy: row['busy'] as bool? ?? true,
      attendance: _attendanceFrom(row['attendance'] as String?),
    );
  }

  static Attendance _attendanceFrom(String? name) => switch (name) {
    'accepted' => Attendance.accepted,
    'declined' => Attendance.declined,
    'invited' => Attendance.invited,
    'tentative' => Attendance.tentative,
    // Anything unrecognised is treated as "no answer to give", which blocks.
    // When in doubt, block: see CalendarFilter.
    _ => Attendance.none,
  };
}

/// A device with no calendar Van can read.
///
/// Not a failure mode and not a stub: this is the correct implementation
/// everywhere the plugin does not exist, and it is what keeps calendar
/// support from being a hard dependency of planning.
class UnsupportedCalendars implements Calendars {
  /// Creates the empty implementation.
  const UnsupportedCalendars();

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<CalendarSource>> sources() async => const [];

  @override
  Future<List<CalendarEntry>> between({
    required DateTime from,
    required DateTime to,
    Set<String> exclude = const {},
  }) async => const [];
}
