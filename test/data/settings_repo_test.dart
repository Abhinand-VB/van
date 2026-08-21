import 'package:flutter_test/flutter_test.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/settings_repo.dart';

void main() {
  late VanDatabase db;
  late SettingsRepo settings;

  setUp(() {
    db = VanDatabase.memory();
    settings = SettingsRepo(db);
  });

  tearDown(() async => db.close());

  test('an unwritten key reads as absent', () async {
    expect(await settings.read('nothing_here'), isNull);
  });

  test('a value survives being written and read back', () async {
    await settings.write('greeting', 'hello');
    expect(await settings.read('greeting'), 'hello');
  });

  test('writing the same key twice replaces rather than duplicates', () async {
    await settings.write('greeting', 'hello');
    await settings.write('greeting', 'goodbye');
    expect(await settings.read('greeting'), 'goodbye');
  });

  group('one-time latches', () {
    test('a latch starts down', () async {
      expect(await settings.flag(SettingKeys.askedForPermission), isFalse);
    });

    test('pulling a latch raises it', () async {
      await settings.setFlag(SettingKeys.askedForPermission);
      expect(await settings.flag(SettingKeys.askedForPermission), isTrue);
    });

    test('pulling a latch twice is harmless', () async {
      await settings.setFlag(SettingKeys.askedForPermission);
      await settings.setFlag(SettingKeys.askedForPermission);
      expect(await settings.flag(SettingKeys.askedForPermission), isTrue);
    });

    test('latches are independent of one another', () async {
      await settings.setFlag('one');
      expect(await settings.flag('one'), isTrue);
      expect(await settings.flag('two'), isFalse);
    });

    test('a key holding something else is not a raised latch', () async {
      // The store is shared, so a latch must not be fooled by an unrelated
      // value that happens to be sitting under a key it cares about.
      await settings.write('one', 'sometime');
      expect(await settings.flag('one'), isFalse);
    });
  });
}
