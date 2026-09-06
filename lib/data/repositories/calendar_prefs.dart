import 'dart:convert';

import 'package:van/data/repositories/settings_repo.dart';

/// Which device calendars the user has taken out of planning.
///
/// **Exclusions are stored, not inclusions, and that is the whole design.**
/// Someone who grants calendar access expects their calendar respected, so
/// every calendar counts by default and the user removes the ones that should
/// not. Storing the excluded set means a calendar added to the phone next
/// month is included without Van having to notice it appeared - an opt-in
/// list would silently ignore it, which looks like Van being broken.
///
/// That default only works because of the transparency rule in
/// `CalendarFilter`: birthday and holiday calendars are all-day and marked
/// free, so they do not block anything and do not need excluding. Change
/// either and the other stops making sense.
class CalendarPreferences {
  /// Creates preferences over [_settings].
  CalendarPreferences(this._settings);

  final SettingsRepo _settings;

  /// Ids of calendars the user has removed from planning.
  ///
  /// A stored value that will not parse is treated as no exclusions rather
  /// than thrown from. This runs on the capture path, and one corrupt
  /// settings row must not be able to cost the user their typed sentence -
  /// the worst case is a calendar coming back, which is visible and one tap
  /// to fix.
  Future<Set<String>> excluded() async {
    final raw = await _settings.read(SettingKeys.excludedCalendars);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return {for (final id in decoded) '$id'};
    } on FormatException {
      return const {};
    }
  }

  /// Replaces the excluded set.
  Future<void> setExcluded(Set<String> ids) => _settings.write(
    SettingKeys.excludedCalendars,
    // Sorted so the stored value is stable and diffable when read by hand
    // out of the database, which is how this project debugs things.
    jsonEncode(ids.toList()..sort()),
  );

  /// Includes or excludes one calendar, leaving the rest alone.
  Future<void> setIncluded(String id, {required bool included}) async {
    final current = {...await excluded()};
    if (included) {
      current.remove(id);
    } else {
      current.add(id);
    }
    await setExcluded(current);
  }
}
