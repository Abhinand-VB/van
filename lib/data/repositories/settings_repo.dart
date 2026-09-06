import 'package:van/data/db/database.dart';

/// Keys used with [SettingsRepo].
///
/// Gathered in one place because a key/value store with string literals
/// scattered across the app is a typo away from silently forgetting something.
abstract final class SettingKeys {
  /// Set once Van has taken the user to the notification permission screen.
  ///
  /// Asking is a one-time event, not a state: whether permission was *granted*
  /// is read from the OS every time, and must never be cached here.
  static const askedForPermission = 'asked_for_permission';

  /// Device calendars the user has taken out of planning, as a JSON array of
  /// provider ids.
  ///
  /// Exclusions rather than inclusions, so a calendar added to the phone
  /// later is respected without Van being told about it. See
  /// `CalendarPreferences`, which owns the encoding.
  static const excludedCalendars = 'excluded_calendars';

  /// Set once Van has offered to set up the on-device model.
  ///
  /// Same shape as [askedForPermission] and for the same reason: offering is
  /// a one-time event, and whether the file is actually *present* is read
  /// from disk every time and must never be cached here.
  static const offeredModel = 'offered_model';
}

/// Small key/value store for things that are not worth a table.
///
/// Deliberately not a cache of anything the OS owns. Only facts about what Van
/// itself has already done belong here, because those are the only ones that
/// cannot be re-derived at startup.
class SettingsRepo {
  /// Creates a repository over [_db].
  SettingsRepo(this._db);

  final VanDatabase _db;

  /// The value stored under [key], or null.
  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Stores [value] under [key], replacing anything already there.
  Future<void> write(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingRow(key: key, value: value));

  /// Whether the one-time latch [key] has been pulled.
  Future<bool> flag(String key) async => await read(key) == 'true';

  /// Pulls the one-time latch [key]. Idempotent.
  Future<void> setFlag(String key) => write(key, 'true');
}
