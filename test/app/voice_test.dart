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
import 'package:van/platform/speech.dart';
import 'package:van/ui/chat_screen.dart';
import 'package:van/ui/now_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/fake_speech.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late FakeSpeech speech;
  late VanService service;
  late FakeClock clock;
  late EventRepo events;

  /// Wednesday 19 August 2026, 09:00 UTC.
  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    notifications = FakeNotifications();
    speech = FakeSpeech()..granted = true;
    events = EventRepo(db, clock);

    service = VanService(
      tasks: TaskRepo(db),
      sessions: SessionRepo(db),
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
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

  Future<void> showNow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NowScreen(
          service: service,
          clock: clock,
          notifications: notifications,
          calendars: const UnsupportedCalendars(),
          calendarPreferences: CalendarPreferences(SettingsRepo(db)),
          speech: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showChat(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(service: service, clock: clock, speech: speech),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> speak(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Say it instead'));
    await tester.pumpAndSettle();
  }

  group('saying it instead of typing it', () {
    testWidgets('what was heard lands in the field, not in a task', (
      tester,
    ) async {
      speech.willHear('finish the assignment by friday, two hours');

      await showNow(tester);
      await speak(tester);

      // A draft, not a command. Recognition is wrong often enough that
      // capturing straight from it would put tasks nobody said into a log
      // that never deletes.
      expect(
        find.widgetWithText(
          TextField,
          'finish the assignment by friday, two hours',
        ),
        findsOneWidget,
      );
      expect(await service.openTasks(), isEmpty);
      expect(await events.count(), 0);
    });

    testWidgets('and capturing it produces the same task typing would', (
      tester,
    ) async {
      speech.willHear('finish the assignment by friday, 2 hours');

      await showNow(tester);
      await speak(tester);
      // Pressing the capture button rather than the keyboard's done action:
      // the transcript arrives in the controller without the field ever being
      // focused, which is exactly how someone speaking rather than typing
      // reaches it.
      await tester.tap(find.byTooltip('Capture'));
      await tester.pumpAndSettle();

      final spoken = (await service.openTasks()).single;
      expect(spoken.title, 'Finish the assignment');
      expect(spoken.estimatedMinutes, 120);
      expect(spoken.deadline, isNotNull);
    });

    testWidgets('speech never replaces what is already typed', (tester) async {
      speech.willHear('by friday');

      await showNow(tester);
      await tester.enterText(find.byType(TextField).first, 'finish the essay');
      await speak(tester);

      // Silently overwriting someone's half-typed sentence with a
      // recogniser's guess is the one thing worse than not hearing them.
      expect(
        find.widgetWithText(TextField, 'finish the essay by friday'),
        findsOneWidget,
      );
    });

    testWidgets('the microphone is on the chat composer too', (tester) async {
      speech.willHear('call the bank');

      await showChat(tester);
      await speak(tester);

      expect(find.widgetWithText(TextField, 'call the bank'), findsOneWidget);
      // Still a draft here as well: nothing was sent.
      expect(await service.openTasks(), isEmpty);
    });
  });

  group('when it cannot listen', () {
    testWidgets('silence says so and writes nothing', (tester) async {
      speech.next = SpeechResult.nothing;

      await showNow(tester);
      await speak(tester);

      expect(find.text('Did not catch that.'), findsOneWidget);
      expect(await events.count(), 0);
    });

    testWidgets('a phone with no offline recogniser explains itself', (
      tester,
    ) async {
      speech.availableOnDevice = false;

      await showNow(tester);

      // Present and disabled rather than absent. A button that vanished would
      // leave the user thinking Van has no voice input at all; one that
      // quietly used the networked recogniser would be far worse.
      expect(find.byTooltip('Say it instead'), findsNothing);
      expect(
        find.byTooltip(
          'This phone has no offline speech recognition, and Van will not '
          'send your voice anywhere.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('and it never falls back to anything', (tester) async {
      speech.availableOnDevice = false;

      await showNow(tester);
      await tester.tap(
        find.byTooltip(
          'This phone has no offline speech recognition, and Van will not '
          'send your voice anywhere.',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('will not send your voice'), findsWidgets);
      expect(speech.listens, 0, reason: 'nothing may be recorded at all');
    });

    testWidgets('refusing the microphone removes the button', (tester) async {
      speech
        ..granted = false
        ..grantOnRequest = false;

      await showNow(tester);
      await speak(tester);

      expect(speech.requests, 1);
      expect(find.byTooltip('Say it instead'), findsNothing);
      // And nothing else about the screen is broken by it.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Van needs the microphone to listen.'), findsOneWidget);
    });

    testWidgets('granting it on the first press then listens', (tester) async {
      speech
        ..granted = false
        ..grantOnRequest = true
        ..willHear('call the bank');

      await showNow(tester);
      await speak(tester);

      expect(speech.requests, 1);
      expect(find.widgetWithText(TextField, 'call the bank'), findsOneWidget);
    });

    testWidgets('a recogniser that fails mid-press keeps the button', (
      tester,
    ) async {
      speech.next = SpeechResult.failed;

      await showNow(tester);
      await speak(tester);

      expect(
        find.text('The microphone did not work that time.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Say it instead'), findsOneWidget);
    });

    testWidgets('a device with no plugin shows no microphone at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NowScreen(
            service: service,
            clock: clock,
            notifications: notifications,
            calendars: const UnsupportedCalendars(),
            calendarPreferences: CalendarPreferences(SettingsRepo(db)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The default is `UnsupportedSpeech`, so every screen that has not been
      // given a recogniser behaves like a phone that cannot listen - rather
      // than throwing, or offering a button that always fails.
      expect(find.byTooltip('Say it instead'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
