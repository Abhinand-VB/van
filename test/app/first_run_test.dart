import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/settings_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van/main.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late SettingsRepo settings;
  late VanService service;

  setUp(() {
    db = VanDatabase.memory();
    notifications = FakeNotifications();
    settings = SettingsRepo(db);
    final clock = FakeClock(DateTime.utc(2026, 8, 19, 9));

    final events = EventRepo(db, clock);
    service = VanService(
      tasks: TaskRepo(db),
      sessions: SessionRepo(db),
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(
        defaultBackend: const NullBackend(),
        observer: EventLogInferenceObserver(events),
      ),
      notifications: notifications,
      templates: NudgeTemplates.fromJson(
        File('assets/nudge_templates/templates.json').readAsStringSync(),
      ),
      clock: clock,
      ids: SequentialIds('x'),
      waking: const WakingHours(utcOffset: Duration.zero),
    );
  });

  tearDown(() async => db.close());

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      VanApp(
        service: service,
        clock: FakeClock(DateTime.utc(2026, 8, 19, 9)),
        notifications: notifications,
        settings: settings,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('asking for permission', () {
    testWidgets('asks on a fresh install', (tester) async {
      notifications
        ..canPost = false
        ..canScheduleExactly = false;

      await launch(tester);

      expect(notifications.requests, 1);
      expect(await settings.flag(SettingKeys.askedForPermission), isTrue);
    });

    testWidgets('does not ask again on the next launch', (tester) async {
      notifications
        ..canPost = false
        ..canScheduleExactly = false;

      await launch(tester);
      await launch(tester);
      await launch(tester);

      expect(
        notifications.requests,
        1,
        reason: 'being thrown into system settings every launch is the bug',
      );
    });

    testWidgets('latches even when the user grants nothing', (tester) async {
      // Walking away from the settings screen without granting is the exact
      // case that used to produce an ask on every single cold start.
      notifications
        ..canPost = false
        ..canScheduleExactly = false
        ..grantOnRequest = null;

      await launch(tester);
      expect(notifications.canPost, isFalse);
      expect(await settings.flag(SettingKeys.askedForPermission), isTrue);
    });

    testWidgets('does not ask at all when both grants are already in', (
      tester,
    ) async {
      await launch(tester);

      expect(notifications.requests, 0);
      expect(
        await settings.flag(SettingKeys.askedForPermission),
        isFalse,
        reason: 'nothing was asked, so nothing should be recorded as asked',
      );
    });

    testWidgets('asks when only the exact-alarm grant is missing', (
      tester,
    ) async {
      notifications.canScheduleExactly = false;

      await launch(tester);
      expect(notifications.requests, 1);
    });
  });

  group('the standing banner', () {
    testWidgets('says nothing when Van can do its job', (tester) async {
      await launch(tester);
      expect(find.textContaining('cannot send notifications'), findsNothing);
      expect(find.textContaining('up to an hour late'), findsNothing);
    });

    testWidgets('warns plainly when Van cannot reach the user', (
      tester,
    ) async {
      notifications
        ..canPost = false
        ..canScheduleExactly = false;

      await launch(tester);
      expect(find.textContaining('cannot send notifications'), findsOneWidget);
    });

    testWidgets('understates the merely-imprecise case', (tester) async {
      // Overstating this would train the user to ignore the banner, and the
      // banner is the only thing left once Van has stopped asking.
      notifications.canScheduleExactly = false;

      await launch(tester);
      expect(find.textContaining('up to an hour late'), findsOneWidget);
      expect(find.textContaining('cannot send notifications'), findsNothing);
    });

    testWidgets('clears once permission is granted from it', (tester) async {
      // A later launch: Van has already had its one ask and declined to nag,
      // so the banner is the only route back to the permission screen.
      await settings.setFlag(SettingKeys.askedForPermission);
      notifications
        ..canPost = false
        ..canScheduleExactly = false
        ..grantOnRequest = true;

      await launch(tester);
      expect(
        notifications.requests,
        0,
        reason: 'the latch is set, so nothing should have asked automatically',
      );
      expect(find.textContaining('cannot send notifications'), findsOneWidget);

      await tester.tap(find.textContaining('cannot send notifications'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot send notifications'), findsNothing);
    });
  });
}
