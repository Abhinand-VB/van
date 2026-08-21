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

      // The status ends as `rescheduled`, not `partial`: _stuck stops the
      // block early and then snoozes it, and the second call overwrites the
      // first one's status. `actualStart` survives, and the sessionPartial
      // event is in the append-only log, so nothing is truly lost - but the
      // session row alone no longer says they got started. See issue 17.
      expect(original.status, SessionStatus.rescheduled);

      final next = (await service.upcoming()).single;
      expect(next.parentSessionId, live.session.id);
      expect(next.hasStarted, isFalse);
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
