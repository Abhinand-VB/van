import 'dart:io';

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
      ids: SequentialIds('x'),
      waking: const WakingHours(utcOffset: Duration.zero),
    );
  });

  tearDown(() async => db.close());

  Future<List<String>> eventTypes() async =>
      (await events.all()).map((e) => e.type.name).toList();

  group('asking', () {
    test('a sentence with no duration is captured and asked about', () async {
      final result = await service.capture('finish the assignment');

      // Both halves matter. Van asks, *and* the task exists with blocks on
      // the calendar - a question that held the capture hostage would lose
      // the thought, which is worse than the guess it replaces.
      expect(result.clarification?.field, TaskField.duration);
      expect(result.task.title, 'Finish the assignment');
      expect(result.sessions, isNotEmpty);
    });

    test(
      'the assumption Van made is named rather than left implicit',
      () async {
        final result = await service.capture('finish the assignment');

        // A plan built on a guess and a plan built on a statement look
        // identical on screen. This is the only thing that tells them apart.
        expect(result.assumedMinutes, 60);
      },
    );

    test('a sentence that says how long is not asked about', () async {
      final result = await service.capture('finish the assignment, 2 hours');

      expect(result.clarification, isNull);
      expect(result.assumedMinutes, isNull);
    });

    test('the question is recorded, so it can be counted later', () async {
      await service.capture('finish the assignment');

      expect(await eventTypes(), contains('clarificationAsked'));
    });

    test('no question, no row', () async {
      await service.capture('finish the assignment, 2 hours');

      expect(await eventTypes(), isNot(contains('clarificationAsked')));
    });
  });

  group('answering', () {
    test('an answer replaces the blocks planned on the guess', () async {
      final captured = await service.capture('finish the assignment');
      final guessed = captured.sessions;
      expect(guessed.map((s) => s.plannedMinutes).reduce((a, b) => a + b), 60);

      final answered = await service.answerDuration(
        captured.task.id,
        '3 hours',
      );

      expect(answered.outcome, AnswerOutcome.replanned);
      expect(answered.task?.estimatedMinutes, 180);
      expect(
        answered.sessions.map((s) => s.plannedMinutes).reduce((a, b) => a + b),
        180,
      );

      // The old blocks are gone rather than sitting alongside the new ones.
      final live = await sessions.forTask(captured.task.id);
      expect(
        live.map((s) => s.id),
        unorderedEquals(answered.sessions.map((s) => s.id)),
      );
      expect(live.map((s) => s.id), isNot(contains(guessed.first.id)));
    });

    test('the nudges armed for the guess are cancelled with it', () async {
      final captured = await service.capture('finish the assignment');
      final armed = notifications.scheduled.length;
      expect(armed, greaterThan(0));

      await service.answerDuration(captured.task.id, '3 hours');

      // Every session the guess produced has had its ladder stood down. A
      // block that no longer exists must not still be able to ring. Matched
      // on the derived ids rather than on a session field, because that is
      // all the real canceller ever gets - see FakeNotifications.
      for (final session in captured.sessions) {
        for (final id in LadderIds.forSession(session.id)) {
          expect(notifications.cancelled, contains(id));
          expect(notifications.pending(), completion(isNot(contains(id))));
        }
      }
    });

    test('a bare number is taken as minutes', () async {
      final captured = await service.capture('finish the assignment');

      final answered = await service.answerDuration(captured.task.id, '45');

      expect(answered.outcome, AnswerOutcome.replanned);
      expect(answered.task?.estimatedMinutes, 45);
    });

    test('an answer with no duration in it changes nothing', () async {
      final captured = await service.capture('finish the assignment');

      final answered = await service.answerDuration(
        captured.task.id,
        'as long as it takes',
      );

      expect(answered.outcome, AnswerOutcome.notUnderstood);
      final task = await tasks.byId(captured.task.id);
      expect(task?.estimatedMinutes, isNull);
      expect(
        (await sessions.forTask(captured.task.id)).map((s) => s.id),
        unorderedEquals(captured.sessions.map((s) => s.id)),
      );
    });

    test(
      'work already under way is not re-planned out from under you',
      () async {
        final captured = await service.capture('finish the assignment');
        await service.startSession(captured.sessions.first.id);

        final answered = await service.answerDuration(
          captured.task.id,
          '3 hours',
        );

        // Re-planning here would take away the block the user is sitting in.
        // An estimate that stays wrong is the cheaper of the two.
        expect(answered.outcome, AnswerOutcome.tooLate);
        expect(
          (await tasks.byId(captured.task.id))?.estimatedMinutes,
          isNull,
        );
      },
    );

    test('an answer is recorded with what it changed', () async {
      final captured = await service.capture('finish the assignment');

      await service.answerDuration(captured.task.id, '3 hours');

      final row = (await events.all()).lastWhere(
        (e) => e.type == EventType.clarificationAnswered,
      );
      expect(row.payload['minutes'], 180);
      expect(row.payload['taskId'], captured.task.id);
    });

    test('an answer that was not understood is not recorded as one', () async {
      final captured = await service.capture('finish the assignment');

      await service.answerDuration(captured.task.id, 'dunno');

      expect(await eventTypes(), isNot(contains('clarificationAnswered')));
    });
  });
}
