import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:van/platform/calendars.dart';
import 'package:van/ui/now_screen.dart';
import 'package:van/ui/settings_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_calendars.dart';
import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeCalendars calendars;
  late FakeNotifications notifications;
  late CalendarPreferences preferences;
  late VanService service;
  late FakeClock clock;

  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    calendars = FakeCalendars();
    notifications = FakeNotifications();
    preferences = CalendarPreferences(SettingsRepo(db));

    final events = EventRepo(db, clock);
    service = VanService(
      tasks: TaskRepo(db),
      sessions: SessionRepo(db),
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
      notifications: notifications,
      calendars: calendars,
      calendarPreferences: preferences,
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

  void withCalendars(List<CalendarSource> sources) {
    calendars
      ..granted = true
      ..sourceList.addAll(sources);
  }

  const work = CalendarSource(
    id: '1',
    name: 'Work',
    accountName: 'me@work.example',
  );
  const birthdays = CalendarSource(
    id: '2',
    name: 'Birthdays',
    accountName: 'me@personal.example',
  );

  Future<void> showSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(calendars: calendars, preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showNow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NowScreen(
          service: service,
          clock: clock,
          notifications: notifications,
          calendars: calendars,
          calendarPreferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('without the grant', () {
    testWidgets('says what Van is missing rather than showing nothing', (
      tester,
    ) async {
      await showSettings(tester);

      expect(find.textContaining('as if nothing else is on'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('Allow asks the OS and reloads', (tester) async {
      calendars
        ..grantOnRequest = true
        ..sourceList.add(work);

      await showSettings(tester);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(calendars.requests, 1);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('a refusal leaves the explanation up', (tester) async {
      calendars.grantOnRequest = false;

      await showSettings(tester);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(find.text('Allow'), findsOneWidget);
    });
  });

  group('the calendar list', () {
    testWidgets('every calendar is included to begin with', (tester) async {
      withCalendars([work, birthdays]);

      await showSettings(tester);

      // The default that makes the feature work on the day it is granted.
      // An opt-in list starting empty would silently plan around nothing.
      final boxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(boxes, hasLength(2));
      expect(boxes.every((box) => box.value ?? false), isTrue);
    });

    testWidgets('the account is shown, because names collide', (tester) async {
      withCalendars([work]);

      await showSettings(tester);

      expect(find.text('me@work.example'), findsOneWidget);
    });

    testWidgets('unticking one stores an exclusion', (tester) async {
      withCalendars([work, birthdays]);

      await showSettings(tester);
      await tester.tap(find.text('Birthdays'));
      await tester.pumpAndSettle();

      expect(await preferences.excluded(), {'2'});
    });

    testWidgets('ticking it again removes the exclusion', (tester) async {
      withCalendars([work, birthdays]);
      await preferences.setIncluded('2', included: false);

      await showSettings(tester);
      await tester.tap(find.text('Birthdays'));
      await tester.pumpAndSettle();

      expect(await preferences.excluded(), isEmpty);
    });

    testWidgets('an exclusion is still there when the page reopens', (
      tester,
    ) async {
      withCalendars([work, birthdays]);
      await preferences.setIncluded('2', included: false);

      await showSettings(tester);

      final boxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(boxes[0].value, isTrue);
      expect(boxes[1].value, isFalse);
    });

    testWidgets('a provider that throws says so rather than looking empty', (
      tester,
    ) async {
      calendars
        ..granted = true
        ..failure = Exception('the provider is not responding');

      await showSettings(tester);

      expect(
        find.textContaining('could not read the calendar'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('reaching it from the Now screen', () {
    testWidgets('the app bar opens the page', (tester) async {
      withCalendars([work]);

      await showNow(tester);
      await tester.tap(find.byTooltip('Calendars'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('nothing is said when the calendar is simply not granted', (
      tester,
    ) async {
      await service.capture('write the report 60 minutes');

      await showNow(tester);

      expect(find.textContaining('could not read your calendar'), findsNothing);
    });

    testWidgets('a plan made without a calendar Van has says so', (
      tester,
    ) async {
      // Granted, and then unreadable: the case that is otherwise invisible,
      // because the plan on screen looks entirely normal and is wrong.
      calendars
        ..granted = true
        ..failure = Exception('permission revoked mid-session');
      await service.capture('write the report 60 minutes');

      await showNow(tester);

      expect(
        find.textContaining('could not read your calendar'),
        findsOneWidget,
      );
    });
  });
}
