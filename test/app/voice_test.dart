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
  late SessionRepo sessions;

  /// Wednesday 19 August 2026, 09:00 UTC.
  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    notifications = FakeNotifications();
    speech = FakeSpeech()..granted = true;
    events = EventRepo(db, clock);
    sessions = SessionRepo(db);

    service = VanService(
      tasks: TaskRepo(db),
      sessions: sessions,
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

  group('answering a nudge by voice', () {
    /// A block that came due and was not started, which is what opens the
    /// stall prompt the moment Chat is shown.
    Future<WorkSession> stalled() async {
      final captured = await service.capture('write the report 45 minutes');
      clock.advance(const Duration(hours: 2));
      return captured.sessions.single;
    }

    testWidgets('a spoken "not today" does what the button does', (
      tester,
    ) async {
      final session = await stalled();
      speech.willHear('not today');

      await showChat(tester);
      expect(find.textContaining("What's in the way?"), findsOneWidget);
      await speak(tester);

      // The acceptance criterion is "exactly the same state change,
      // including the event rows" - so this asserts the row, not just the
      // status.
      final after = await sessions.byId(session.id);
      expect(after?.status, SessionStatus.skipped);
      final row = (await events.all()).lastWhere(
        (e) => e.type == EventType.sessionMissed,
      );
      expect(row.payload['reason'], 'not_today');
      expect(find.text('Left for today.'), findsOneWidget);
    });

    testWidgets('a spoken "I have started" starts it', (tester) async {
      final session = await stalled();
      speech.willHear("I've started");

      await showChat(tester);
      await speak(tester);

      expect((await sessions.byId(session.id))?.hasStarted, isTrue);
      expect(find.text('Started.'), findsOneWidget);
    });

    testWidgets('a spoken "in twenty minutes" moves it by twenty', (
      tester,
    ) async {
      final session = await stalled();
      speech.willHear('give me twenty minutes');

      await showChat(tester);
      await speak(tester);

      // A snooze does not move a block; it stands the old one down and plans
      // a replacement, which is what keeps the log honest about what was
      // actually agreed and when.
      expect(
        (await sessions.byId(session.id))?.status,
        SessionStatus.rescheduled,
      );
      final replacement = (await sessions.forTask(
        session.taskId,
      )).firstWhere((s) => s.id != session.id);
      expect(
        replacement.plannedStart,
        clock.now().add(const Duration(minutes: 20)),
      );
      expect(find.textContaining('Moved to'), findsOneWidget);
    });

    testWidgets('something Van cannot follow asks rather than acting', (
      tester,
    ) async {
      final session = await stalled();
      speech.willHear('I need to talk to Priya about it first');

      await showChat(tester);
      await speak(tester);

      // Nothing moved. Applying the wrong action moves work the user never
      // agreed to move, in a log that never deletes.
      final after = await sessions.byId(session.id);
      expect(after?.status, SessionStatus.planned);
      expect(after?.hasStarted, isFalse);
      expect(find.textContaining('I did not follow that'), findsOneWidget);
      // And the words are still there to send as a reason instead.
      expect(
        find.widgetWithText(
          TextField,
          'I need to talk to Priya about it first',
        ),
        findsOneWidget,
      );
    });

    testWidgets('speech is still only a draft when no nudge is open', (
      tester,
    ) async {
      // The direct-action rule is scoped to answering a nudge. Said into an
      // empty Chat, "not today" is a task nobody asked Van to act on.
      speech.willHear('not today');

      await showChat(tester);
      await speak(tester);

      expect(find.widgetWithText(TextField, 'not today'), findsOneWidget);
      expect(find.text('Left for today.'), findsNothing);
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
