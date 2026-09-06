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
import 'package:van/platform/notifications.dart';
import 'package:van/ui/task_list_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late EventRepo events;
  late SessionRepo sessions;
  late TaskRepo tasks;
  late VanService service;
  late FakeClock clock;

  /// Wednesday 19 August 2026, 09:00 UTC.
  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    notifications = FakeNotifications();
    events = EventRepo(db, clock);
    sessions = SessionRepo(db);
    tasks = TaskRepo(db);

    service = VanService(
      tasks: tasks,
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
      ids: SequentialIds('t'),
      waking: const WakingHours(utcOffset: Duration.zero),
    );
  });

  tearDown(() async => db.close());

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskListScreen(service: service, clock: clock),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String title) async {
    final row = find.ancestor(
      of: find.text(title),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
  }

  group('deleting a task', () {
    testWidgets('is offered, and says what it is not', (tester) async {
      await service.capture('call the bank 30 minutes');

      await show(tester);
      await openMenu(tester, 'Call the bank');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // The alternative to deleting is finishing, and the two mean opposite
      // things to a log trying to learn what this person follows through on.
      // The dialog says so rather than letting the wrong one get picked.
      expect(find.textContaining('Use Done instead'), findsOneWidget);
    });

    testWidgets('keeps the task when declined', (tester) async {
      await service.capture('call the bank 30 minutes');

      await show(tester);
      await openMenu(tester, 'Call the bank');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect((await service.openTasks()).single.title, 'Call the bank');
    });

    testWidgets('removes the task, its blocks and its nudges', (tester) async {
      final captured = await service.capture('call the bank 30 minutes');
      final session = captured.sessions.single;
      expect(notifications.scheduled, isNotEmpty);

      await show(tester);
      await openMenu(tester, 'Call the bank');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await service.openTasks(), isEmpty);
      expect(await sessions.forTask(captured.task.id), isEmpty);
      for (final id in LadderIds.forSession(session.id)) {
        expect(notifications.cancelled, contains(id));
      }
    });

    testWidgets('is not recorded as giving up', (tester) async {
      // `abandoned` means the user quit on the work, and that distinction is
      // the only signal the status carries. Clearing a mistake off the list
      // is not quitting, and recording it as such would poison it.
      final captured = await service.capture('call the bank 30 minutes');

      await show(tester);
      await openMenu(tester, 'Call the bank');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      final row = (await events.all()).lastWhere(
        (e) => e.type == EventType.taskUpdated,
      );
      expect(row.payload['status'], 'deleted');
      expect(row.payload['taskId'], captured.task.id);
      // And the capture itself is still in the log, which never deletes.
      expect(
        (await events.all()).map((e) => e.type),
        contains(EventType.taskCreated),
      );
    });
  });

  group('what it actually took', () {
    testWidgets('a finished task shows up, and invites the time', (
      tester,
    ) async {
      final captured = await service.capture('call the bank 30 minutes');
      await service.completeTask(captured.task.id);

      await show(tester);

      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Call the bank'), findsOneWidget);
      // The invitation. A finished task with no recorded time is the common
      // case, and a button that says so is the only thing that will ever get
      // one filled in.
      expect(find.text('Add time'), findsOneWidget);
    });

    testWidgets('tapping it records the time, and shows both numbers', (
      tester,
    ) async {
      final captured = await service.capture('call the bank 30 minutes');
      await service.completeTask(captured.task.id);

      await show(tester);
      await tester.tap(find.text('Add time'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '2h'));
      await tester.pumpAndSettle();

      expect((await tasks.byId(captured.task.id))?.actualMinutes, 120);
      // Both, because "took 2h" alone says nothing about whether the plan was
      // wrong. This is the only place in Van an estimate meets what happened.
      // `findsWidgets` because the confirmation snackbar says it too.
      expect(find.textContaining('took 2h'), findsWidgets);
      expect(find.textContaining('estimated 30m'), findsOneWidget);
    });

    testWidgets('an open task can be told too, without finishing it', (
      tester,
    ) async {
      // Three hours in and not done is a thing you have learned about the
      // estimate, and it is worth recording before it is forgotten.
      final captured = await service.capture('call the bank 30 minutes');

      await show(tester);
      await openMenu(tester, 'Call the bank');
      await tester.tap(find.text('Time taken…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '3h'));
      await tester.pumpAndSettle();

      final task = await tasks.byId(captured.task.id);
      expect(task?.actualMinutes, 180);
      expect(task?.status, TaskStatus.active, reason: 'still open');
    });

    testWidgets('the sheet is seeded with what Van actually watched', (
      tester,
    ) async {
      // Van knows how long a block ran. It does not know how long the work
      // took, because most of it happens outside the app - so the measured
      // number seeds the question rather than answering it.
      final captured = await service.capture('call the bank 30 minutes');
      final session = captured.sessions.single;
      await service.startSession(session.id);
      clock.advance(const Duration(minutes: 20));
      await service.completeSession(session.id);
      await service.completeTask(captured.task.id);

      await show(tester);
      await tester.tap(find.text('Add time'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '20'), findsOneWidget);
      expect(find.textContaining('Van watched 20 minutes'), findsOneWidget);
    });

    testWidgets('nothing is recorded when the sheet is dismissed', (
      tester,
    ) async {
      final captured = await service.capture('call the bank 30 minutes');
      await service.completeTask(captured.task.id);

      await show(tester);
      await tester.tap(find.text('Add time'));
      await tester.pumpAndSettle();
      // Dismiss without choosing. Finishing must never be held hostage to a
      // number nobody has.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect((await tasks.byId(captured.task.id))?.actualMinutes, isNull);
      expect(find.text('Add time'), findsOneWidget);
    });
  });

  group('the finished section', () {
    testWidgets('is absent until something is finished', (tester) async {
      await service.capture('call the bank 30 minutes');

      await show(tester);

      expect(find.text('Finished'), findsNothing);
    });

    testWidgets('cannot be re-estimated, only timed', (tester) async {
      // Replanning something that is done would put blocks on the calendar
      // for work that has stopped.
      final captured = await service.capture('call the bank 30 minutes');
      await service.completeTask(captured.task.id);

      await show(tester);
      await openMenu(tester, 'Call the bank');

      expect(find.text('Time taken…'), findsOneWidget);
      expect(find.text('Estimate…'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
