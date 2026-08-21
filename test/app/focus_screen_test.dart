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
import 'package:van/ui/focus_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late SessionRepo sessions;
  late VanService service;
  late FakeClock clock;

  /// Wednesday 19 August 2026, 09:00 UTC.
  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    notifications = FakeNotifications();
    sessions = SessionRepo(db);
    final events = EventRepo(db, clock);

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

  /// Captures a task and starts its block.
  Future<({WorkSession session, Task task})> running(String sentence) async {
    final captured = await service.capture(sentence);
    final started = await service.startSession(captured.sessions.first.id);
    return (session: started!, task: captured.task);
  }

  Future<void> show(
    WidgetTester tester,
    ({WorkSession session, Task task}) live,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FocusScreen(
          service: service,
          clock: clock,
          session: live.session,
          task: live.task,
        ),
      ),
    );
    await tester.pump();
  }

  group('the timer', () {
    testWidgets('starts at the length of the block', (tester) async {
      final live = await running('write the report 45 minutes');
      await show(tester, live);

      expect(find.text('45:00'), findsOneWidget);
      expect(find.text('Write the report'), findsOneWidget);
    });

    testWidgets('counts what is left, not the full block again', (
      tester,
    ) async {
      // The Now card offers RESUME on a running block, so this screen is
      // routinely reached partway through. Restarting the clock at the full
      // length each time would quietly turn a 45-minute block into as much
      // time as you liked.
      final live = await running('write the report 45 minutes');
      clock.advanceTo(clock.now().add(const Duration(minutes: 20)));

      await show(tester, live);

      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('45:00'), findsNothing);
    });

    testWidgets('stops at zero rather than going negative', (tester) async {
      final live = await running('write the report 45 minutes');
      clock.advanceTo(clock.now().add(const Duration(hours: 2)));

      await show(tester, live);

      expect(find.text('00:00'), findsOneWidget);
    });
  });

  group('the three outcomes', () {
    testWidgets('Done completes the session and the task', (tester) async {
      final live = await running('write the report 45 minutes');
      await show(tester, live);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(
        (await sessions.byId(live.session.id))!.status,
        SessionStatus.completed,
      );
      expect(await service.openTasks(), isEmpty);
    });

    testWidgets('Need more time records a partial, not a failure', (
      tester,
    ) async {
      // Stopping early still counts as having started, which is the behaviour
      // Van most wants to reinforce.
      final live = await running('write the report 45 minutes');
      await show(tester, live);

      await tester.tap(find.text('Need more time'));
      await tester.pumpAndSettle();

      final stopped = await sessions.byId(live.session.id);
      expect(stopped!.status, SessionStatus.partial);
      expect(
        stopped.hasStarted,
        isTrue,
        reason: 'the record that they began must survive stopping early',
      );
    });

    testWidgets("I'm stuck keeps the start and offers another go", (
      tester,
    ) async {
      final live = await running('write the report 45 minutes');
      await show(tester, live);

      await tester.tap(find.text("I'm stuck"));
      await tester.pumpAndSettle();

      final original = await sessions.byId(live.session.id);
      expect(
        original!.hasStarted,
        isTrue,
        reason: 'being stuck is not the same as never having tried',
      );

      // `partial`, not `rescheduled`. The block was worked on, and the
      // replacement records the link through parentSessionId - so the row
      // keeps the more informative of the two facts. This used to come out
      // as `rescheduled`, because _stuck stopped the block and then snoozed
      // it and the second call overwrote the first's status.
      expect(original.status, SessionStatus.partial);

      final next = (await service.upcoming()).single;
      expect(next.parentSessionId, live.session.id);
      expect(next.hasStarted, isFalse);
    });
  });

  group('a fumbled thumb', () {
    // All three buttons write to the database and then pop, and until the pop
    // lands all three stay tappable. These sequences are one mis-tap away.

    test('Need more time cannot erase a completion', () async {
      final live = await running('write the report 45 minutes');
      await service.completeSession(live.session.id);
      final finishedAt = (await sessions.byId(live.session.id))!.actualEnd;

      await service.stopEarly(live.session.id);

      final still = await sessions.byId(live.session.id);
      expect(still!.status, SessionStatus.completed);
      expect(still.actualEnd, finishedAt);
    });

    test('Done cannot rewrite a partial as finished', () async {
      final live = await running('write the report 45 minutes');
      await service.stopEarly(live.session.id);

      await service.completeSession(live.session.id);

      expect(
        (await sessions.byId(live.session.id))!.status,
        SessionStatus.partial,
      );
    });

    test('Done twice records one completion', () async {
      final live = await running('write the report 45 minutes');

      await service.completeSession(live.session.id);
      clock.advanceTo(clock.now().add(const Duration(minutes: 5)));
      await service.completeSession(live.session.id);

      expect(
        await EventRepo(db, clock).ofType(EventType.sessionCompleted),
        hasLength(1),
      );
    });

    testWidgets('one press ends the visit, so there is no second', (
      tester,
    ) async {
      // The screen pops as soon as a decision lands, which is what stops a
      // second button being reachable at all. _deciding is the belt to that
      // brace: the three buttons stay tappable during the write itself.
      final live = await running('write the report 45 minutes');
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => FocusScreen(
                service: service,
                clock: clock,
                session: live.session,
                task: live.task,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text("I'm stuck"), findsNothing);
      expect(
        await EventRepo(db, clock).ofType(EventType.sessionCompleted),
        hasLength(1),
      );
    });
  });

  group('an action arriving twice', () {
    // Reachable rather than theoretical. With Van killed nothing cancels a
    // notification until an action is actually processed, so the 09:00 and
    // 09:10 rungs of one ladder can both be sitting in the shade. Pressing
    // the same button on each used to move the work twice.

    test('a second Snooze does not move the work again', () async {
      final captured = await service.capture('write the report 45 minutes');
      final session = captured.sessions.first;

      final first = await service.snooze(session.id);
      final second = await service.snooze(session.id);

      expect(first, isNotNull);
      expect(second, isNull, reason: 'the block was already moved');
      expect(
        await service.upcoming(),
        hasLength(1),
        reason: 'two replacements for one block is the bug',
      );
    });

    test('a second Not today does not reopen and re-skip', () async {
      final captured = await service.capture('write the report 45 minutes');
      final session = captured.sessions.first;

      await service.notToday(session.id);
      await service.notToday(session.id);

      expect((await sessions.byId(session.id))!.status, SessionStatus.skipped);
      expect(
        await EventRepo(db, clock).ofType(EventType.sessionMissed),
        hasLength(1),
      );
    });

    test('Snooze cannot resurrect finished work', () async {
      final live = await running('write the report 45 minutes');
      await service.completeSession(live.session.id);

      expect(await service.snooze(live.session.id), isNull);
      expect(
        (await sessions.byId(live.session.id))!.status,
        SessionStatus.completed,
      );
      expect(await service.upcoming(), isEmpty);
    });

    test('being stuck twice does not queue two retries', () async {
      final live = await running('write the report 45 minutes');

      final first = await service.stuck(live.session.id);
      final second = await service.stuck(live.session.id);

      expect(first, isNotNull);
      expect(second, isNull);
      expect(await service.upcoming(), hasLength(1));
    });
  });

  group('resuming a block already under way', () {
    // The defect this closes. The Now card wires RESUME to the same call as
    // START, and startSession had no guard - so backing out of this screen
    // and tapping again overwrote actualStart with whenever you came back.

    test('does not move the moment they actually began', () async {
      final live = await running('write the report 45 minutes');
      final began = live.session.actualStart;

      clock.advanceTo(clock.now().add(const Duration(minutes: 20)));
      final resumed = await service.startSession(live.session.id);

      expect(resumed!.actualStart, began);
      expect((await sessions.byId(live.session.id))!.actualStart, began);
    });

    test('does not record a second start', () async {
      final live = await running('write the report 45 minutes');
      clock.advanceTo(clock.now().add(const Duration(minutes: 20)));

      await service.startSession(live.session.id);

      expect(
        await EventRepo(db, clock).ofType(EventType.sessionStarted),
        hasLength(1),
      );
    });

    test('closed work cannot be reopened', () async {
      // A stale notification action can arrive for a block the sweep already
      // moved. START on it must not resurrect it.
      final captured = await service.capture('call the bank 30 minutes');
      final session = captured.sessions.first;
      await service.notToday(session.id);

      expect(await service.startSession(session.id), isNull);
      expect(
        (await sessions.byId(session.id))!.status,
        SessionStatus.skipped,
      );
    });
  });
}
