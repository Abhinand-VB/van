import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/settings_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van/main.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/platform/model_file.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/prompts.dart';

/// A phone that has somewhere to put a model but has not got one.
///
/// `UnsupportedModelFile` reports an empty path, which is Van's signal that
/// there is nowhere to install one - so it cannot be used to test the offer.
class _EmptySlot implements ModelFile {
  int opened = 0;

  @override
  Future<ModelFileStatus> status() async => const ModelFileStatus(
    present: false,
    path: '/data/user/0/dev.van.app/files/models/model.litertlm',
    bytes: 0,
    expectedName: 'model.litertlm',
  );

  @override
  Future<ModelFileStatus> install() async => status();

  @override
  Future<ModelFileStatus> remove() async => status();

  @override
  Future<void> openSourcePage() async => opened++;

  @override
  Future<DownloadProgress> startDownload() async => DownloadProgress.idle;

  @override
  Future<DownloadProgress> downloadProgress() async => DownloadProgress.idle;

  @override
  Future<DownloadProgress> cancelDownload() async => DownloadProgress.idle;

  @override
  Future<ModelFileStatus> adoptDownload() async => status();
}

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
      prompts: testPrompts(),
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
        calendars: const UnsupportedCalendars(),
        calendarPreferences: CalendarPreferences(settings),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the on-device model offer', () {
    Future<void> showWithSlot(
      WidgetTester tester, {
      required _EmptySlot model,
      bool usesModel = false,
    }) async {
      await tester.pumpWidget(
        VanApp(
          service: service,
          clock: FakeClock(DateTime.utc(2026, 8, 19, 9)),
          notifications: notifications,
          settings: settings,
          calendars: const UnsupportedCalendars(),
          calendarPreferences: CalendarPreferences(settings),
          modelFile: model,
          usesModel: usesModel,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is made once, and says the model is optional', (
      tester,
    ) async {
      await showWithSlot(tester, model: _EmptySlot());

      expect(find.text('Run a model on your phone?'), findsOneWidget);
      // The honest version of today's state. Selling a 2.6 GB download for a
      // capability that is switched off is a lie the user discovers the
      // moment they install it and nothing changes.
      expect(find.textContaining('nothing uses it yet'), findsOneWidget);
      expect(find.textContaining('works fully without it'), findsOneWidget);
    });

    testWidgets('claims more once something is actually routed to it', (
      tester,
    ) async {
      await showWithSlot(tester, model: _EmptySlot(), usesModel: true);

      expect(find.textContaining('word its nudges'), findsOneWidget);
      expect(find.textContaining('nothing uses it yet'), findsNothing);
    });

    testWidgets('declining leaves everything alone, and does not repeat', (
      tester,
    ) async {
      await showWithSlot(tester, model: _EmptySlot());
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.text('Run a model on your phone?'), findsNothing);

      // An offer that comes back on every cold start is not an offer.
      await showWithSlot(tester, model: _EmptySlot());
      expect(find.text('Run a model on your phone?'), findsNothing);
    });

    testWidgets('accepting opens the page that installs it', (tester) async {
      await showWithSlot(tester, model: _EmptySlot());
      await tester.tap(find.text('Set it up'));
      await tester.pumpAndSettle();

      expect(find.text('On-device model'), findsWidgets);
      expect(find.text('Not installed'), findsOneWidget);
    });

    testWidgets('is not made on a build with nowhere to put one', (
      tester,
    ) async {
      // `UnsupportedModelFile` reports an empty path. Inviting someone to
      // install a model on a platform that cannot hold one is worse than
      // saying nothing at all.
      await launch(tester);

      expect(find.text('Run a model on your phone?'), findsNothing);
    });
  });

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
