import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van/platform/notifications.dart';
import 'package:van_core/van_core.dart';

/// Records what would have been shown, so the loop can be driven without a
/// phone. Everything above this line is the same code the device runs.
class FakeNotifications implements Notifications {
  final scheduled = <PendingNudge>[];
  final cancelled = <int>[];
  bool permitted = true;

  @override
  Future<void> init(
    void Function(String sessionId, NudgeAction action) onAction,
  ) async {}

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<bool> requestPermission() async => permitted;

  @override
  Future<void> schedule(PendingNudge nudge) async => scheduled.add(nudge);

  @override
  Future<void> showNow(PendingNudge nudge) async => scheduled.add(nudge);

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> cancelForSession(String sessionId) async {
    final ids = scheduled
        .where((n) => n.sessionId == sessionId)
        .map((n) => n.id)
        .toList();
    for (final id in ids) {
      await cancel(id);
    }
  }

  @override
  Future<List<int>> pending() async => scheduled.map((n) => n.id).toList();
}

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late EventRepo events;
  late SessionRepo sessions;
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

    service = VanService(
      tasks: TaskRepo(db),
      sessions: sessions,
      events: events,
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

  /// Inference logging is deliberately fire-and-forget so a slow write can
  /// never delay the call it describes. That means tests have to let the
  /// microtask queue drain before asserting on it.
  Future<void> flushLog() => Future<void>.delayed(Duration.zero);

  Future<List<String>> eventTypes() async {
    await flushLog();
    return (await events.all()).map((e) => e.type.name).toList();
  }

  group('the whole loop, with no model at all', () {
    test('a sentence becomes a plan, a ladder and an event trail', () async {
      final result = await service.capture(
        'finish the database assignment by friday, 3 hours',
      );

      // Captured with the heuristic parser.
      expect(result.task.title, 'Finish the database assignment');
      expect(result.task.estimatedMinutes, 180);
      expect(result.task.deadline, DateTime.utc(2026, 8, 21, 23, 59));

      // Broken into blocks, none of them enormous.
      expect(result.sessions, isNotEmpty);
      for (final session in result.sessions) {
        expect(session.plannedMinutes, lessThanOrEqualTo(90));
      }

      // The escalation ladder is armed ahead of time, three rungs per block.
      expect(notifications.scheduled.length, result.sessions.length * 3);
      final levels = notifications.scheduled.map((n) => n.level).toSet();
      expect(levels, {
        InterventionLevel.l0Gentle,
        InterventionLevel.l1Check,
        InterventionLevel.l2Diagnose,
      });

      // Every scheduled nudge has real copy, no placeholders left in.
      for (final nudge in notifications.scheduled) {
        expect(nudge.body, isNotEmpty);
        expect(nudge.body, isNot(contains('{')));
      }

      // And the whole thing is on the record.
      final types = await eventTypes();
      expect(types, contains('taskCreated'));
      expect(types, contains('sessionPlanned'));
      expect(types, contains('nudgeScheduled'));
      expect(types, contains('inferenceFallback'));
    });

    test('starting stands the rest of the ladder down', () async {
      final result = await service.capture('read the paper 45 minutes');
      final session = result.sessions.first;
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        hasLength(3),
      );

      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 4)));
      final started = await service.startSession(session.id);

      expect(started!.hasStarted, isTrue);
      expect(started.status, SessionStatus.started);
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isEmpty,
        reason: 'an answered nudge must not escalate behind the user',
      );
      expect(await eventTypes(), contains('sessionStarted'));
    });

    test('the ladder rungs are spaced as the policy says', () async {
      final result = await service.capture('write notes 30 minutes');
      final session = result.sessions.first;
      final forSession =
          notifications.scheduled
              .where((n) => n.sessionId == session.id)
              .toList()
            ..sort((a, b) => a.at.compareTo(b.at));

      expect(forSession[0].at, session.plannedStart);
      expect(
        forSession[1].at,
        session.plannedStart.add(const Duration(minutes: 10)),
      );
      expect(
        forSession[2].at,
        session.plannedStart.add(const Duration(minutes: 25)),
      );
    });

    test('snoozing moves the work and re-arms', () async {
      final result = await service.capture('gym 45 minutes');
      final session = result.sessions.first;

      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 12)));
      final next = await service.snooze(session.id);

      expect(next!.rescheduleCount, 1);
      expect(next.parentSessionId, session.id);
      expect(next.plannedStart, clock.now().add(const Duration(minutes: 10)));

      // Old rungs gone, new ones armed.
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isEmpty,
      );
      expect(
        notifications.scheduled.where((n) => n.sessionId == next.id),
        isNotEmpty,
      );
      expect(await eventTypes(), contains('rescheduleApplied'));
    });

    test('not today closes the session without a replacement', () async {
      final result = await service.capture('call the bank 20 minutes');
      final session = result.sessions.first;

      await service.notToday(session.id);

      final reloaded = await sessions.byId(session.id);
      expect(reloaded!.status, SessionStatus.skipped);
      expect(notifications.scheduled, isEmpty);
      expect(await eventTypes(), contains('sessionMissed'));
    });

    test('completing the last block finishes the task', () async {
      final result = await service.capture('tidy the desk 20 minutes');
      expect(result.sessions, hasLength(1));

      await service.startSession(result.sessions.first.id);
      await service.completeSession(result.sessions.first.id);

      final open = await service.openTasks();
      expect(open, isEmpty, reason: 'task should have closed itself');
      expect(await eventTypes(), contains('sessionCompleted'));
    });

    test('a task with more work than time still schedules what fits', () async {
      // Twenty hours of work due tomorrow cannot fit. Van should place what it
      // can and say so, rather than silently dropping most of it.
      final result = await service.capture(
        'impossible project by tomorrow 20 hours',
      );
      expect(result.isPartial, isTrue);
      expect(result.shortfallMinutes, greaterThan(0));
      expect(result.sessions, isNotEmpty);
    });

    test('the Now screen shows a running session over a planned one', () async {
      await service.capture('first task 30 minutes');
      final second = await service.capture('second task 30 minutes');

      await service.startSession(second.sessions.first.id);
      final next = await service.next();

      expect(next!.session.id, second.sessions.first.id);
      expect(next.session.hasStarted, isTrue);
    });

    test('every model call fell back, and every one was recorded', () async {
      await service.capture('anything at all 30 minutes');
      await flushLog();
      final fallbacks = await events.ofType(EventType.inferenceFallback);
      expect(fallbacks, isNotEmpty);
      for (final event in fallbacks) {
        expect(event.field<String>('backend'), 'none');
        expect(event.field<String>('reason'), 'unavailable');
      }
      expect(await events.ofType(EventType.inferenceOk), isEmpty);
    });
  });
}
