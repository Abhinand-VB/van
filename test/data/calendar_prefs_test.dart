import 'package:flutter_test/flutter_test.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/data/repositories/settings_repo.dart';

void main() {
  late VanDatabase db;
  late SettingsRepo settings;
  late CalendarPreferences preferences;

  setUp(() {
    db = VanDatabase.memory();
    settings = SettingsRepo(db);
    preferences = CalendarPreferences(settings);
  });

  tearDown(() async => db.close());

  test('nothing is excluded to begin with', () async {
    expect(await preferences.excluded(), isEmpty);
  });

  test('an exclusion survives a round trip', () async {
    await preferences.setExcluded({'2', '7'});
    expect(await preferences.excluded(), {'2', '7'});
  });

  test('one calendar can be excluded without disturbing the others', () async {
    await preferences.setExcluded({'2'});
    await preferences.setIncluded('7', included: false);

    expect(await preferences.excluded(), {'2', '7'});
  });

  test('including one that was never excluded changes nothing', () async {
    await preferences.setExcluded({'2'});
    await preferences.setIncluded('9', included: true);

    expect(await preferences.excluded(), {'2'});
  });

  test('the stored value is sorted, so it reads cleanly by hand', () async {
    // This project debugs by pulling the sqlite file off the phone and
    // reading it, so a stable encoding is worth the one line it costs.
    await preferences.setExcluded({'7', '2', '13'});

    expect(
      await settings.read(SettingKeys.excludedCalendars),
      '["13","2","7"]',
    );
  });

  test('a corrupt stored value reads as no exclusions', () async {
    // This runs on the capture path. One unparseable settings row must not
    // be able to cost the user their typed sentence, and the worst case of
    // being wrong here is a calendar coming back - visible, one tap to fix.
    await settings.write(SettingKeys.excludedCalendars, 'not json at all');

    expect(await preferences.excluded(), isEmpty);
  });

  test('a value of the wrong shape reads as no exclusions', () async {
    await settings.write(SettingKeys.excludedCalendars, '{"1": true}');

    expect(await preferences.excluded(), isEmpty);
  });

  test(
    'excluding everything is allowed and is not the same as nothing',
    () async {
      await preferences.setExcluded({'1', '2'});
      expect(await preferences.excluded(), hasLength(2));

      await preferences.setExcluded({});
      expect(await preferences.excluded(), isEmpty);
    },
  );
}
