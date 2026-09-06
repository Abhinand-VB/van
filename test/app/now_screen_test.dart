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

  Future<void> show(WidgetTester tester) async {
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
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  group('the overflow menu', () {
    testWidgets('opens the on-device model page', (tester) async {
      // Written after the menu appeared to do nothing on the phone. It
      // passes against the version that appeared broken, so it is a guard on
      // the route rather than a reproduction of that - the cause there was
      // most likely a missed tap, and the honest place to settle it is the
      // device, not here.
      await show(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('On-device model'));
      await tester.pumpAndSettle();

      expect(find.text('Not installed'), findsOneWidget);
    });
  });

  group('finishing a task', () {
    testWidgets('the circle in the list is a real tick, not a picture', (
      tester,
    ) async {
      await service.capture('write the report 45 minutes');
      await service.capture('call the bank 30 minutes');

      await show(tester);
      await tester.tap(find.byTooltip('Finish "Call the bank"'));
      await tester.pumpAndSettle();

      // It looked like a checkbox, sat where a checkbox sits, and did
      // nothing - so the only way to finish anything was a swipe on another
      // tab that nothing on screen mentions.
      expect(
        (await service.openTasks()).map((t) => t.title),
        isNot(contains('Call the bank')),
      );
    });

    testWidgets('the card can finish the thing it is showing', (tester) async {
      await service.capture('write the report 45 minutes');

      await show(tester);
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();

      expect(await service.openTasks(), isEmpty);
      expect(find.textContaining('Finished'), findsOneWidget);
    });

    testWidgets('finishing offers a way back out of it', (tester) async {
      // One tap, on the main screen, next to what you were reading. Without
      // an exit that is a trap.
      await service.capture('write the report 45 minutes');

      await show(tester);
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      final open = await service.openTasks();
      expect(open.map((t) => t.title), contains('Write the report'));
      // And it is planned again rather than sitting there with no blocks.
      expect(await service.next(), isNotNull);
    });
  });

  group('the estimate on the card', () {
    testWidgets('always shows a number, and says when it is a guess', (
      tester,
    ) async {
      await service.capture('finish the assignment');

      await show(tester);

      // The card used to say nothing at all about how long the work was when
      // nobody had stated it, which is the worst case: no figure to correct
      // and no sign that Van had picked one anyway.
      expect(find.text('1h (assumed)'), findsWidgets);
    });

    testWidgets('shows the stated figure plainly when there is one', (
      tester,
    ) async {
      await service.capture('finish the assignment, 2 hours');

      await show(tester);

      expect(find.text('2h'), findsWidgets);
      expect(find.textContaining('assumed'), findsNothing);
    });

    testWidgets('tapping it opens an editor prefilled with that number', (
      tester,
    ) async {
      await service.capture('finish the assignment');

      await show(tester);
      await tester.tap(find.text('1h (assumed)').first);
      await tester.pumpAndSettle();

      // Prefilled, so this is a correction rather than an invention.
      expect(find.widgetWithText(TextField, '60'), findsOneWidget);
      expect(find.textContaining('Van assumed this'), findsOneWidget);
    });

    testWidgets('the editor survives a raised keyboard', (tester) async {
      // On the phone the field autofocused, the keyboard came up over the
      // presets, and the sheet overflowed by 152 pixels. No widget test could
      // see it, because a test surface has no keyboard - so this one puts one
      // there. `viewInsets` is exactly what a keyboard does to a window.
      await service.capture('finish the assignment');

      // A phone-shaped window, because the default test surface is 800x600
      // logical and a keyboard does not fit in it in a way that resembles
      // anything. 1080x2340 at 3x is this project's actual device.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      // The insets go on before the sheet opens, so it is laid out against a
      // window that already has a keyboard in it - which is the real
      // sequence, since the field used to raise one on open.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);

      await show(tester);
      await tester.tap(find.text('1h (assumed)').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // And Save is still reachable, which is the point of it scrolling.
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    });

    testWidgets('picking a length replans the task', (tester) async {
      await service.capture('finish the assignment');

      await show(tester);
      await tester.tap(find.text('1h (assumed)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '3h'));
      await tester.pumpAndSettle();

      expect((await service.openTasks()).single.estimatedMinutes, 180);
      expect(find.textContaining('Replanned'), findsOneWidget);
    });

    testWidgets('editing it answers the standing question too', (tester) async {
      // Both routes are the same operation, so using one must close the
      // other - otherwise Van goes on asking about a task you just told it
      // the length of.
      await show(tester);
      await type(tester, 'finish the assignment');
      expect(find.textContaining('Roughly how long'), findsWidgets);

      await tester.tap(find.text('1h (assumed)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '1h 30m'));
      await tester.pumpAndSettle();

      expect((await service.openTasks()).single.estimatedMinutes, 90);
      expect(find.textContaining('Roughly how long'), findsNothing);
    });
  });

  group('a deep task on the Now card', () {
    testWidgets('opens with a short block, named for what it is for', (
      tester,
    ) async {
      await service.capture('write the dissertation, 4 hours');

      await show(tester);

      // The whole point of reading depth. Not "Van thinks this is deep" -
      // there is nowhere in the product that says that, and there should not
      // be - but a first block a person can actually begin.
      expect(find.text('Write the dissertation'), findsWidgets);
      expect(find.text('Work out where to start'), findsOneWidget);
      expect(find.textContaining('25 minutes'), findsOneWidget);
    });

    testWidgets('an errand is not given one, however long it is', (
      tester,
    ) async {
      await service.capture('email the whole list, 4 hours');

      await show(tester);

      expect(find.text('Work out where to start'), findsNothing);
    });
  });

  group('Van asking how long', () {
    testWidgets('capturing without a duration asks, and still captures', (
      tester,
    ) async {
      await show(tester);
      await type(tester, 'finish the assignment');

      expect(find.textContaining('Roughly how long'), findsWidgets);
      expect(find.textContaining('assumed 1 hour'), findsOneWidget);
      expect((await service.openTasks()).single.title, 'Finish the assignment');
    });

    testWidgets('capturing with a duration asks nothing', (tester) async {
      await show(tester);
      await type(tester, 'finish the assignment, 2 hours');

      expect(find.textContaining('Roughly how long'), findsNothing);
    });

    testWidgets('the next thing typed answers, and the plan is rebuilt', (
      tester,
    ) async {
      await show(tester);
      await type(tester, 'finish the assignment');
      await type(tester, '3 hours');

      expect(find.textContaining('Replanned'), findsOneWidget);
      expect((await service.openTasks()).single.estimatedMinutes, 180);
      // Question gone, so the field captures again.
      expect(find.textContaining('Roughly how long'), findsNothing);
    });

    testWidgets('dismissing the question leaves the guess standing', (
      tester,
    ) async {
      await show(tester);
      await type(tester, 'finish the assignment');

      await tester.tap(find.byTooltip('Leave it'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Roughly how long'), findsNothing);
      // And the next line is a capture rather than an answer.
      await type(tester, 'call the bank 20 minutes');
      expect(
        (await service.openTasks()).map((t) => t.title),
        contains('Call the bank'),
      );
    });

    testWidgets('an unreadable answer keeps the question up', (tester) async {
      await show(tester);
      await type(tester, 'finish the assignment');
      await type(tester, 'no idea');

      expect(find.textContaining('did not get a length'), findsOneWidget);
      expect(find.textContaining('Roughly how long'), findsWidgets);
    });
  });

  group('the "After that" list', () {
    testWidgets('never repeats the task already on the card', (tester) async {
      await service.capture('write the report 45 minutes');
      await service.capture('call the bank 30 minutes');

      await show(tester);

      final next = (await service.next())!;
      expect(
        find.text(next.task.title),
        findsOneWidget,
        reason: 'the next task belongs on the card, and nowhere else',
      );
    });

    testWidgets('repeats nothing when the next block is not the most urgent', (
      tester,
    ) async {
      // The device case. The card is session-ordered and the list is
      // deadline-ordered, so the two disagree: the block starting soonest
      // belongs to the task with the later deadline.
      await service.capture('start this one first 30 minutes');
      await service.capture('but this is due sooner by friday 30 minutes');

      await show(tester);

      final next = (await service.next())!;
      final open = await service.openTasks();
      expect(
        open.first.id,
        isNot(next.task.id),
        reason: 'this test is pointless unless the two orderings disagree',
      );

      for (final task in open) {
        expect(
          find.text(task.title),
          findsOneWidget,
          reason: '"${task.title}" should appear exactly once on screen',
        );
      }
    });

    testWidgets('hides itself when the card covers everything', (tester) async {
      await service.capture('the only thing 30 minutes');

      await show(tester);

      expect(find.text('After that'), findsNothing);
    });

    testWidgets('does not say "After that" when there is no card', (
      tester,
    ) async {
      // Every block already resolved, so the Now card is empty but the task
      // is still open. "After that" would be referring to nothing.
      final captured = await service.capture('unscheduled work 30 minutes');
      await service.notToday(captured.sessions.first.id);

      await show(tester);

      expect(await service.next(), isNull);
      expect(find.text('After that'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text(captured.task.title), findsOneWidget);
    });
  });
}
