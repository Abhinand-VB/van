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
import 'package:van/ui/now_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';

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
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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
