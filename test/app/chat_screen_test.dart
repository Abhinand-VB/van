import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van/ui/chat_screen.dart';
import 'package:van/ui/task_list_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late VanService service;
  late FakeClock clock;

  /// Wednesday 19 August 2026, 09:00 UTC.
  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    notifications = FakeNotifications();
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

  Future<void> showChat(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(service: service, clock: clock),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
  }

  group('the chat screen', () {
    testWidgets('starts empty and says what it is for', (tester) async {
      await showChat(tester);
      expect(find.textContaining('Say what needs doing'), findsOneWidget);
    });

    testWidgets('a sentence becomes a task and a plan card', (tester) async {
      await showChat(tester);
      await send(tester, 'write the report 45 minutes');

      // What they typed, echoed back.
      expect(find.text('write the report 45 minutes'), findsOneWidget);
      // What Van understood, which is the point of the card.
      expect(find.text('Write the report'), findsOneWidget);
      expect(find.textContaining('45 min'), findsWidgets);

      final open = await service.openTasks();
      expect(open.single.title, 'Write the report');
    });

    testWidgets('the card shows every block it scheduled', (tester) async {
      await showChat(tester);
      await send(tester, 'write the report 3 hours');

      final sessions = await service.upcoming();
      expect(sessions.length, greaterThan(1));
      expect(find.byIcon(Icons.schedule), findsNWidgets(sessions.length));
    });

    testWidgets('says so when the work would not fit', (tester) async {
      await showChat(tester);
      await send(tester, 'impossible project by tomorrow 20 hours');

      expect(find.textContaining('would not fit'), findsOneWidget);
    });

    testWidgets('undo takes the whole capture back', (tester) async {
      await showChat(tester);
      await send(tester, 'call the bank 30 minutes');
      expect(await service.openTasks(), isNotEmpty);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(await service.openTasks(), isEmpty);
      expect(await service.upcoming(), isEmpty);
      expect(
        notifications.scheduled,
        isEmpty,
        reason: 'an undone capture must not leave nudges armed',
      );
    });

    testWidgets('an undone card stays visible, marked as removed', (
      tester,
    ) async {
      // The card is the record of what was asked for. Deleting it would make
      // the conversation lie about what happened.
      await showChat(tester);
      await send(tester, 'call the bank 30 minutes');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Call the bank'), findsOneWidget);
      expect(find.text('Removed.'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('the composer clears so the next thing can be typed', (
      tester,
    ) async {
      await showChat(tester);
      await send(tester, 'write the report 45 minutes');

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('an empty sentence does nothing', (tester) async {
      await showChat(tester);
      await send(tester, '   ');

      expect(await service.openTasks(), isEmpty);
      expect(find.textContaining('Say what needs doing'), findsOneWidget);
    });
  });

  group('renegotiating a stalled block in chat', () {
    /// Captures a task and walks the clock past its block without starting it.
    Future<WorkSession> stall(String sentence, {int late = 20}) async {
      final result = await service.capture(sentence);
      final session = result.sessions.first;
      clock.advanceTo(session.plannedStart.add(Duration(minutes: late)));
      return session;
    }

    testWidgets('chat opens the conversation about a block that stalled', (
      tester,
    ) async {
      await stall('write the report 60 minutes');

      await showChat(tester);

      expect(find.text('Write the report'), findsOneWidget);
      expect(find.textContaining('Not started'), findsOneWidget);
      expect(find.text("What's in the way?"), findsWidgets);
    });

    testWidgets('says nothing when no block has stalled', (tester) async {
      await service.capture('write the report 60 minutes');

      await showChat(tester);

      expect(find.textContaining('Not started'), findsNothing);
      expect(find.textContaining('Say what needs doing'), findsOneWidget);
    });

    testWidgets('what you type is an answer, not a new task', (tester) async {
      await stall('write the report 60 minutes');
      await showChat(tester);

      await send(tester, 'too tired to face an hour of it');

      expect(
        await service.openTasks(),
        hasLength(1),
        reason: 'answering a stall must not capture a task called "too tired"',
      );
      expect(find.text('Shrink it'), findsOneWidget);
    });

    testWidgets('the proposal changes nothing until it is accepted', (
      tester,
    ) async {
      final session = await stall('write the report 60 minutes');
      await showChat(tester);
      await send(tester, 'too tired');

      final untouched = await SessionRepo(db).byId(session.id);
      expect(untouched!.status, SessionStatus.planned);
      expect(untouched.plannedMinutes, 60);
    });

    testWidgets('accepting a shrink actually shrinks the block', (
      tester,
    ) async {
      final session = await stall('write the report 60 minutes');
      await showChat(tester);
      await send(tester, 'too tired');

      await tester.tap(find.text('Shrink it'));
      await tester.pumpAndSettle();

      final replaced = await SessionRepo(db).byId(session.id);
      expect(replaced!.status, SessionStatus.rescheduled);

      final live = (await service.upcoming()).single;
      expect(live.plannedMinutes, 30);
      expect(live.parentSessionId, session.id);
      expect(find.textContaining('Moved to'), findsOneWidget);
    });

    testWidgets('declining leaves the block exactly as it was', (tester) async {
      final session = await stall('write the report 60 minutes');
      await showChat(tester);
      await send(tester, 'too tired');

      await tester.tap(find.text('Leave it'));
      await tester.pumpAndSettle();

      final untouched = await SessionRepo(db).byId(session.id);
      expect(untouched!.status, SessionStatus.planned);
      expect(untouched.plannedMinutes, 60);
      expect(find.text('Left as it is.'), findsOneWidget);
    });

    testWidgets('never claims a change it did not make', (tester) async {
      // The card can sit on screen while the block moves on. Accepting then
      // has to report the refusal, not the proposal - the old code asked what
      // was proposed before asking whether it happened, so a release over an
      // already-started block still said "Let go for today".
      final session = await stall('write the report 60 minutes');
      await showChat(tester);
      await send(tester, 'too tired');

      await service.startSession(session.id);

      await tester.tap(find.text('Shrink it'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already moved on'), findsOneWidget);
      expect(find.textContaining('Moved to'), findsNothing);
      expect(
        (await SessionRepo(db).byId(session.id))!.plannedMinutes,
        60,
        reason: 'the block was started, so nothing may have shrunk it',
      );
    });

    testWidgets('once answered, typing captures a task again', (tester) async {
      await stall('write the report 60 minutes');
      await showChat(tester);
      await send(tester, 'too tired');
      await tester.tap(find.text('Leave it'));
      await tester.pumpAndSettle();

      await send(tester, 'call the bank 20 minutes');

      final open = await service.openTasks();
      expect(open.map((t) => t.title), contains('Call the bank'));
    });

    testWidgets('the accept button names what it will do', (tester) async {
      // "OK" on a card that might cancel your afternoon is not consent.
      await stall('write the report 60 minutes');
      await showChat(tester);
      await send(tester, 'too tired');

      expect(find.text('Shrink it'), findsOneWidget);
      expect(find.text('OK'), findsNothing);
    });
  });

  group('the task list', () {
    Future<void> showList(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskListScreen(service: service, clock: clock),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is flat: every open task, no grouping', (tester) async {
      await service.capture('first thing 30 minutes');
      await service.capture('second thing 30 minutes');
      await service.capture('third thing 30 minutes');

      await showList(tester);

      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('First thing'), findsOneWidget);
      expect(find.text('Third thing'), findsOneWidget);
    });

    testWidgets('says so when there is nothing open', (tester) async {
      await showList(tester);
      expect(find.text('Nothing open.'), findsOneWidget);
    });

    testWidgets('swiping right finishes a task', (tester) async {
      final captured = await service.capture('call the bank 30 minutes');
      await showList(tester);

      await tester.drag(find.text('Call the bank'), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(await service.openTasks(), isEmpty);
      final reloaded = await TaskRepo(db).byId(captured.task.id);
      expect(reloaded!.status, TaskStatus.done);
      expect(find.text('Nothing open.'), findsOneWidget);
    });

    testWidgets('finishing a task stands its nudges down', (tester) async {
      await service.capture('call the bank 30 minutes');
      expect(notifications.scheduled, isNotEmpty);

      await showList(tester);
      await tester.drag(find.text('Call the bank'), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(
        notifications.scheduled,
        isEmpty,
        reason: 'Van must not nudge about work already finished',
      );
    });

    testWidgets('finishing one task leaves the others alone', (tester) async {
      await service.capture('call the bank 30 minutes');
      await service.capture('write the report 30 minutes');
      await showList(tester);

      await tester.drag(find.text('Call the bank'), const Offset(500, 0));
      await tester.pumpAndSettle();

      final open = await service.openTasks();
      expect(open.single.title, 'Write the report');
      expect(find.text('Write the report'), findsOneWidget);
    });

    testWidgets('a deadline is shown, because it is why order matters', (
      tester,
    ) async {
      await service.capture('submit the form by friday 30 minutes');
      await showList(tester);

      expect(find.textContaining('due 21 Aug'), findsOneWidget);
    });
  });
}
