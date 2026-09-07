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
      ids: SequentialIds('m'),
      waking: const WakingHours(utcOffset: Duration.zero),
    );
  });

  tearDown(() async => db.close());

  group('the sentence that started this', () {
    /// The owner's real capture, verbatim.
    const said =
        'Go to the shop take a stroll cook lunch and do my remaining works '
        'also I need to do taxes';

    test('produces three tasks where it used to produce one', () async {
      final result = await service.capture(said);

      // Not five. "go to the shop take a stroll cook lunch" has no separator
      // in it, and cutting on bare verbs is what turns "call the bank and ask
      // about the mortgage" into two tasks. Three beats one; D83 has the
      // argument.
      expect(result.captured, hasLength(3));
      expect(result.captured.map((c) => c.task.title), [
        'Go to the shop take a stroll cook lunch',
        'Do my remaining works',
        // "I need to" is stripped by the parser's own title cleanup, which is
        // better than keeping it: the task is "do taxes", not a report on how
        // the user felt about it.
        'Do taxes',
      ]);
    });

    test('every one of them is planned, not just the first', () async {
      final result = await service.capture(said);

      for (final one in result.captured) {
        expect(
          one.sessions,
          isNotEmpty,
          reason: '"${one.task.title}" got no blocks',
        );
      }
      expect(await service.openTasks(), hasLength(3));
    });

    test('it asks once, not three times', () async {
      // None of the three states a duration, so the old rule would have asked
      // about each. Five clauses asking five questions is the form
      // CaptureQuestions exists to prevent, arriving by another route.
      final result = await service.capture(said);

      expect(result.clarification, isNotNull);
      final asked = (await events.all())
          .where((e) => e.type == EventType.clarificationAsked)
          .length;
      expect(asked, 1);
    });

    test('one sentence takes one undo', () async {
      final result = await service.capture(said);

      final removed = await service.undoCaptureAll(result.taskIds);

      expect(removed, 3);
      expect(await service.openTasks(), isEmpty);
      // And the blocks went with them.
      for (final one in result.captured) {
        expect(await sessions.forTask(one.task.id), isEmpty);
      }
    });

    test('each task records the sentence it came out of', () async {
      // A split that went wrong is otherwise impossible to find later.
      final result = await service.capture(said);

      final rows = (await events.all())
          .where((e) => e.type == EventType.taskCreated)
          .toList();
      expect(rows, hasLength(3));
      for (final row in rows) {
        expect(row.payload['from'], said);
      }
      expect(result.isMany, isTrue);
    });
  });

  group('the question, and which task it is about', () {
    /// The first job states a duration. The second does not.
    const mixed = 'email the landlord 15 minutes and pay the rent';

    test('it is about the task that needs it, not the first one', () async {
      final result = await service.capture(mixed);

      expect(result.captured, hasLength(2));
      expect(result.clarification, isNotNull);
      // The event log always recorded the right task. The result did not
      // carry it, so the screen had nothing to go on and used the first -
      // and answering would have overwritten the 15 minutes the user gave.
      expect(result.clarificationTaskId, result.captured.last.task.id);
      expect(result.clarificationTaskId, isNot(result.task.id));
    });

    test('the log and the result name the same task', () async {
      final result = await service.capture(mixed);

      final asked = (await events.all()).firstWhere(
        (e) => e.type == EventType.clarificationAsked,
      );
      expect(asked.payload['taskId'], result.clarificationTaskId);
    });

    test('answering it moves that task and leaves the other alone', () async {
      final result = await service.capture(mixed);

      await service.answerDuration(result.clarificationTaskId!, '90 minutes');

      final open = await service.openTasks();
      final landlord = open.firstWhere((t) => t.title.startsWith('Email'));
      final rent = open.firstWhere((t) => t.title.startsWith('Pay'));
      // The stated duration survives; the guessed one is replaced.
      expect(landlord.estimatedMinutes, 15);
      expect(rent.estimatedMinutes, 90);
    });

    test('what the old behaviour actually did, kept as evidence', () async {
      // The screen used `result.task.id` - the first task. This is that call,
      // made directly, so the damage is on record rather than described: the
      // landlord's stated 15 minutes is overwritten with the length meant for
      // the rent, and the rent keeps its guess.
      final result = await service.capture(mixed);

      await service.answerDuration(result.task.id, '90 minutes');

      final open = await service.openTasks();
      expect(
        open.firstWhere((t) => t.title.startsWith('Email')).estimatedMinutes,
        90,
        reason: 'a duration the user stated, silently replaced',
      );
      expect(
        open.firstWhere((t) => t.title.startsWith('Pay')).estimatedMinutes,
        isNot(90),
        reason: 'and the task actually asked about never got the answer',
      );
    });

    test('with one task it is still that task', () async {
      final result = await service.capture('pay the rent');

      expect(result.clarification, isNotNull);
      expect(result.clarificationTaskId, result.task.id);
    });

    test('no question means no task to point at', () async {
      final result = await service.capture('pay the rent 30 minutes');

      expect(result.clarification, isNull);
      expect(result.clarificationTaskId, isNull);
    });
  });

  group('a sentence that is one job', () {
    test('is still one task, and records no origin sentence', () async {
      final result = await service.capture('call the bank and ask about it');

      expect(result.captured, hasLength(1));
      expect(result.isMany, isFalse);
      final row = (await events.all()).firstWhere(
        (e) => e.type == EventType.taskCreated,
      );
      // Nothing was split, so "from" would just be the title again.
      expect(row.payload.containsKey('from'), isFalse);
    });

    test('the old single-task reading still works', () async {
      // Everything written before splitting existed reads `.task` and
      // `.sessions`, and the common case is still exactly one job.
      final result = await service.capture('write the report 45 minutes');

      expect(result.task.title, 'Write the report');
      expect(result.sessions, isNotEmpty);
      expect(result.taskIds, hasLength(1));
    });

    test('a deadline on the sentence reaches every task it makes', () async {
      // "by friday" sits in the last clause and the parser reads each clause
      // on its own, so this is a real limit rather than a hidden feature -
      // asserted so that changing it is a decision.
      final result = await service.capture(
        'email the landlord and pay the rent by friday',
      );

      expect(result.captured, hasLength(2));
      expect(result.captured.first.task.deadline, isNull);
      expect(result.captured.last.task.deadline, isNotNull);
    });
  });

  group('what must not change', () {
    test('an empty sentence captures nothing at all', () async {
      final result = await service.capture('   ');

      expect(result.captured, isEmpty);
      expect(await service.openTasks(), isEmpty);
    });

    test('two jobs are two tasks with their own estimates', () async {
      final result = await service.capture(
        'email the landlord 15 minutes and pay the rent 30 minutes',
      );

      expect(result.captured, hasLength(2));
      expect(result.captured.first.task.estimatedMinutes, 15);
      expect(result.captured.last.task.estimatedMinutes, 30);
      // Both stated a duration, so there is nothing to ask about.
      expect(result.clarification, isNull);
    });
  });
}
