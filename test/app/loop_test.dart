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
  late NudgeRepo nudges;
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
    nudges = NudgeRepo(db);

    service = VanService(
      tasks: TaskRepo(db),
      sessions: sessions,
      events: events,
      nudges: nudges,
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

  group('the nudge record and fatigue', () {
    /// Captures a task and walks the clock past the point where the nudge
    /// engine has given up on the resulting block.
    Future<WorkSession> abandon(String sentence) async {
      final result = await service.capture(sentence);
      final session = result.sessions.first;
      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 90)));
      return session;
    }

    test('every armed rung is written down, not just fired', () async {
      final result = await service.capture('read the paper 45 minutes');
      final session = result.sessions.first;

      final recorded = await nudges.forSession(session.id);
      expect(recorded, hasLength(3));
      expect(
        recorded.map((n) => n.level),
        [
          InterventionLevel.l0Gentle,
          InterventionLevel.l1Check,
          InterventionLevel.l2Diagnose,
        ],
      );
      for (final nudge in recorded) {
        expect(nudge.copy, isNotEmpty);
        expect(nudge.templateId, isNotNull);
        expect(nudge.wasSuppressed, isFalse);
        expect(nudge.deliveredAt, isNull, reason: 'none of these have fired');
      }
    });

    test('the recorded rung carries a real score, not the baseline', () async {
      final first = await service.capture('read the paper 45 minutes');
      final opening = (await nudges.forSession(
        first.sessions.first.id,
      )).firstWhere((n) => n.type == NudgeType.sessionStart);
      expect(opening.importance, NudgeType.sessionStart.baseImportance);

      // Once the work has been moved, the same rung scores higher: a block on
      // its second attempt matters more than one on its first.
      clock.advanceTo(
        first.sessions.first.plannedStart.add(const Duration(minutes: 90)),
      );
      final moved = (await service.sweepStaleSessions()).moved.single;
      final second = (await nudges.forSession(
        moved.id,
      )).firstWhere((n) => n.type == NudgeType.sessionStart);

      expect(second.importance, greaterThan(opening.importance));
      expect(second.importance, lessThanOrEqualTo(10));
    });

    test('starting records a delivery and a started response', () async {
      final result = await service.capture('read the paper 45 minutes');
      final session = result.sessions.first;

      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 4)));
      await service.startSession(session.id);

      final recorded = await nudges.forSession(session.id);
      final fired = recorded.where((n) => n.wasDelivered).toList();
      expect(fired, hasLength(1), reason: 'only the l0 rung had come due');
      expect(fired.single.level, InterventionLevel.l0Gentle);

      final replies = await nudges.responsesFor(fired.single.id);
      expect(replies, hasLength(1));
      expect(replies.single.response, ResponseType.started);
      expect(replies.single.latencySeconds, 4 * 60);

      final types = await eventTypes();
      expect(types, contains('nudgeDelivered'));
      expect(types, contains('nudgeResponded'));
    });

    test('rungs stood down before firing are kept, marked why', () async {
      final result = await service.capture('read the paper 45 minutes');
      final session = result.sessions.first;

      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 4)));
      await service.startSession(session.id);

      final standDowns = (await nudges.forSession(
        session.id,
      )).where((n) => n.wasSuppressed).toList();
      expect(standDowns, hasLength(2));
      for (final nudge in standDowns) {
        expect(nudge.suppressionReason, 'answeredBeforeItFired');
      }
    });

    test('answering before anything fired records no response', () async {
      await service.capture('first thing 60 minutes');
      final later = await service.capture('second thing 45 minutes');
      final session = later.sessions.first;
      expect(session.plannedStart.isAfter(clock.now()), isTrue);

      // Started ahead of time: nothing has interrupted them at all.
      await service.startSession(session.id);

      final recorded = await nudges.forSession(session.id);
      expect(recorded.where((n) => n.wasDelivered), isEmpty);
      for (final nudge in recorded) {
        expect(await nudges.responsesFor(nudge.id), isEmpty);
      }
      expect(
        await eventTypes(),
        isNot(contains('nudgeResponded')),
        reason: 'an unearned fatigue tick would silence Van for no reason',
      );
    });

    test('the sweep is what records an ignore', () async {
      final session = await abandon('read the paper 45 minutes');
      await service.sweepStaleSessions();

      final fired = (await nudges.forSession(
        session.id,
      )).where((n) => n.wasDelivered).toList();
      expect(fired, hasLength(3), reason: 'all three rungs had come due');

      final replies = await nudges.responsesFor(fired.last.id);
      expect(replies.single.response, ResponseType.ignored);
    });

    test('one ignored ladder is not yet fatigue', () async {
      await abandon('read the paper 45 minutes');
      await service.sweepStaleSessions();

      expect(
        await nudges.consecutiveDismissals(
          NudgeType.sessionMissed,
          DateTime.utc(2026, 8, 19),
        ),
        lessThan(3),
      );
    });

    test('two ignored ladders and Van stops chasing', () async {
      // The payoff. Ignore everything twice and the follow-up rungs stop
      // being armed at all - Van still says the block is due, but it no
      // longer chases you about it.
      await abandon('read the paper 45 minutes');
      final first = await service.sweepStaleSessions();

      clock.advanceTo(
        first.moved.single.plannedStart.add(const Duration(minutes: 90)),
      );
      final second = await service.sweepStaleSessions();
      final survivor = second.moved.single;

      final armed = await nudges.forSession(survivor.id);
      final chases = armed
          .where((n) => n.type == NudgeType.sessionMissed)
          .toList();
      expect(chases, isNotEmpty);
      for (final chase in chases) {
        expect(
          chase.wasSuppressed,
          isTrue,
          reason: 'the ${chase.level.name} rung should have been held back',
        );
        expect(
          chase.suppressionReason,
          SuppressionReason.dismissalFatigue.name,
        );
      }

      // Held back means not handed to the OS, not merely logged.
      expect(
        notifications.scheduled.where((n) => n.sessionId == survivor.id),
        hasLength(1),
        reason: 'only the opening prompt should still be armed',
      );
      expect(await eventTypes(), contains('nudgeSuppressed'));
    });

    test('fatigue is a today measure, not a permanent verdict', () async {
      await abandon('read the paper 45 minutes');
      await service.sweepStaleSessions();

      final yesterday = DateTime.utc(2026, 8, 18);
      final tomorrow = DateTime.utc(2026, 8, 20);
      expect(
        await nudges.consecutiveDismissals(NudgeType.sessionMissed, yesterday),
        greaterThan(0),
      );
      expect(
        await nudges.consecutiveDismissals(NudgeType.sessionMissed, tomorrow),
        0,
        reason: "yesterday's swipes must not silence Van this morning",
      );
    });
  });

  group('finishing and undoing a task', () {
    test('completing from the list closes the task and its blocks', () async {
      final result = await service.capture('write the report 3 hours');
      expect(result.sessions.length, greaterThan(1));

      final done = await service.completeTask(result.task.id);

      expect(done!.status, TaskStatus.done);
      expect(await service.openTasks(), isEmpty);
      for (final session in await sessions.forTask(result.task.id)) {
        expect(
          session.status,
          SessionStatus.skipped,
          reason: 'a block that never ran must not be recorded as completed',
        );
      }
    });

    test('completing stands down every armed nudge', () async {
      final result = await service.capture('write the report 3 hours');
      expect(notifications.scheduled, isNotEmpty);

      await service.completeTask(result.task.id);

      expect(
        notifications.scheduled,
        isEmpty,
        reason: 'Van must not nudge about work already finished',
      );
    });

    test('completing counts as engagement, not as an ignored nudge', () async {
      // The trap: finish the work late, from the list, after the ladder has
      // already fired. Leaving those rungs unanswered would build fatigue
      // against someone who did exactly what Van asked.
      final result = await service.capture('write the report 45 minutes');
      final session = result.sessions.first;
      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 30)));

      await service.completeTask(result.task.id);

      final fired = (await nudges.forSession(
        session.id,
      )).where((n) => n.wasDelivered).toList();
      expect(fired, isNotEmpty);
      final replies = await nudges.responsesFor(fired.last.id);
      expect(replies.single.response, ResponseType.started);
      expect(
        await nudges.consecutiveDismissals(
          NudgeType.sessionMissed,
          DateTime.utc(2026, 8, 19),
        ),
        0,
      );
    });

    test('completing a task that does not exist is harmless', () async {
      expect(await service.completeTask('nope'), isNull);
    });

    test('undo removes the task, its blocks and its nudges', () async {
      final result = await service.capture('call the bank 30 minutes');
      final session = result.sessions.first;
      expect(await nudges.forSession(session.id), isNotEmpty);

      expect(await service.undoCapture(result.task.id), isTrue);

      expect(await service.openTasks(), isEmpty);
      expect(await sessions.forTask(result.task.id), isEmpty);
      expect(await sessions.byId(session.id), isNull);
      expect(await nudges.forSession(session.id), isEmpty);
      expect(notifications.scheduled, isEmpty);
    });

    test('undo does not record the work as abandoned', () async {
      // `abandoned` means the user gave up on something. Undoing a capture is
      // Van having misread a sentence, and conflating the two would poison the
      // only signal that status exists to carry.
      final result = await service.capture('call the bank 30 minutes');
      await service.undoCapture(result.task.id);

      final statuses = (await events.ofType(
        EventType.taskUpdated,
      )).map((e) => e.field<String>('status')).toList();
      expect(statuses, contains('undone'));
      expect(statuses, isNot(contains(TaskStatus.abandoned.name)));
    });

    test('undo leaves the capture itself on the record', () async {
      final result = await service.capture('call the bank 30 minutes');
      await service.undoCapture(result.task.id);

      // The task table forgets. The append-only log does not.
      final types = await eventTypes();
      expect(types, contains('taskCreated'));
      expect(types, contains('sessionPlanned'));
    });

    test('undoing twice is harmless', () async {
      final result = await service.capture('call the bank 30 minutes');
      expect(await service.undoCapture(result.task.id), isTrue);
      expect(await service.undoCapture(result.task.id), isFalse);
    });
  });

  group('negotiating a stalled block', () {
    /// Captures a task and puts the clock [late] minutes past its block.
    Future<WorkSession> stall(String sentence, {int late = 30}) async {
      final result = await service.capture(sentence);
      final session = result.sessions.first;
      clock.advanceTo(session.plannedStart.add(Duration(minutes: late)));
      return session;
    }

    test('proposes something, and changes nothing on its own', () async {
      final session = await stall('write the report 60 minutes');

      final outcome = await service.negotiate(session.id);

      expect(outcome, isNotNull);
      expect(outcome!.proposal.message, isNotEmpty);
      final untouched = await sessions.byId(session.id);
      expect(
        untouched!.status,
        SessionStatus.planned,
        reason: 'negotiate proposes; only applyNegotiation may act',
      );
    });

    test('the ladder picks the level, and it climbs with lateness', () async {
      final early = await stall('write the report 60 minutes', late: 5);
      expect(
        (await service.negotiate(early.id))!.level,
        InterventionLevel.l0Gentle,
      );

      clock.advanceTo(early.plannedStart.add(const Duration(minutes: 30)));
      expect(
        (await service.negotiate(early.id))!.level,
        InterventionLevel.l2Diagnose,
      );
    });

    test('giving a reason is met with a smaller ask, not a repeat', () async {
      final session = await stall('write the report 60 minutes', late: 5);

      final outcome = await service.negotiate(
        session.id,
        reason: 'too tired to face an hour of it',
      );

      expect(outcome!.level, InterventionLevel.l3Shrink);
      expect(outcome.proposal.action, NegotiationAction.shrink);
      expect(outcome.proposal.shrinkToMinutes, 30);
    });

    test('applying a shrink replaces the block with a smaller one', () async {
      final session = await stall('write the report 60 minutes', late: 5);
      final outcome = await service.negotiate(session.id, reason: 'too tired');

      final next = await service.applyNegotiation(
        session.id,
        outcome!.proposal,
        reason: 'too tired',
      );

      expect(next!.plannedMinutes, 30);
      expect(next.parentSessionId, session.id);
      expect(next.rescheduleCount, 1);
      expect(
        (await sessions.byId(session.id))!.status,
        SessionStatus.rescheduled,
      );
      expect(
        notifications.scheduled.where((n) => n.sessionId == next.id),
        isNotEmpty,
        reason: 'the replacement needs its own ladder',
      );
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isEmpty,
      );
    });

    test('a shrunken block never lands in the past', () async {
      final session = await stall('write the report 60 minutes', late: 45);
      final outcome = await service.negotiate(session.id, reason: 'too tired');

      final next = await service.applyNegotiation(
        session.id,
        outcome!.proposal,
        reason: 'too tired',
      );

      expect(next!.plannedStart.isAfter(clock.now()), isTrue);
    });

    test('applying a hold changes nothing but records the answer', () async {
      final session = await stall('write the report 60 minutes', late: 5);
      final outcome = await service.negotiate(session.id);
      expect(outcome!.proposal.action, NegotiationAction.hold);

      final same = await service.applyNegotiation(
        session.id,
        outcome.proposal,
        reason: 'still on it',
      );

      expect(same!.id, session.id);
      expect(same.status, SessionStatus.planned);
      expect(await eventTypes(), contains('nudgeResponded'));
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isNotEmpty,
        reason: 'holding means the ladder carries on, not that it stands down',
      );
    });

    test('the level Van chose is on the record', () async {
      final session = await stall('write the report 60 minutes');
      await service.negotiate(session.id, reason: 'stuck');

      final chosen = await events.ofType(EventType.interventionSelected);
      expect(chosen, hasLength(1));
      expect(chosen.single.field<String>('level'), isNotNull);
      expect(chosen.single.field<String>('source'), 'fallback');
      expect(chosen.single.field<bool>('gaveReason'), isTrue);
    });

    test('a block already underway cannot be renegotiated', () async {
      // Found by review, and worse than the bug being looked for. A started
      // session is neither resolved nor stale, so the only guard was
      // isResolved - and accepting a shrink would have replaced work in
      // progress with a smaller block later on, cancelling what the user was
      // doing at that moment.
      final session = await stall('write the report 60 minutes');
      final outcome = await service.negotiate(session.id, reason: 'too tired');
      await service.startSession(session.id);

      expect(
        await service.applyNegotiation(
          session.id,
          outcome!.proposal,
          reason: 'too tired',
        ),
        isNull,
      );

      final running = await sessions.byId(session.id);
      expect(running!.status, SessionStatus.started);
      expect(running.plannedMinutes, 60);
    });

    test('a running block is not offered a negotiation at all', () async {
      final session = await stall('write the report 60 minutes');
      await service.startSession(session.id);

      expect(await service.negotiate(session.id, reason: 'too tired'), isNull);
    });

    test('a resolved block cannot be renegotiated', () async {
      final session = await stall('write the report 60 minutes');
      await service.startSession(session.id);
      await service.completeSession(session.id);

      const overreach = NegotiationProposal(
        action: NegotiationAction.hold,
        message: 'still on for this?',
      );
      expect(await service.applyNegotiation(session.id, overreach), isNull);
    });

    test('a proposal the ladder does not permit is refused', () async {
      // The whole reason negotiate can be pointed at a cloud model later. A
      // gentle first prompt must not be able to cancel the afternoon, however
      // well-formed the JSON was.
      final session = await stall('write the report 60 minutes', late: 2);
      const cancelTheDay = NegotiationProposal(
        action: NegotiationAction.release,
        message: 'Forget it, take the day off.',
      );

      expect(
        await service.applyNegotiation(session.id, cancelTheDay),
        isNull,
      );
      expect((await sessions.byId(session.id))!.status, SessionStatus.planned);
    });

    test('a release the ladder permits closes the block and says so', () async {
      // Reaching l5 through the public API needs three moves, a deadline
      // inside a day and a prior refusal, which is a lot of scaffolding to
      // test one return value. Forcing the level is the smaller lie: the
      // rules, the apply path and the persistence are all the real ones.
      final conceding = VanService(
        tasks: TaskRepo(db),
        sessions: sessions,
        events: events,
        nudges: nudges,
        router: InferenceRouter(defaultBackend: const NullBackend()),
        notifications: notifications,
        templates: NudgeTemplates.fromJson(
          File('assets/nudge_templates/templates.json').readAsStringSync(),
        ),
        prompts: testPrompts(),
        clock: clock,
        ids: SequentialIds('c'),
        waking: const WakingHours(utcOffset: Duration.zero),
        policy: const _AlwaysConcede(),
      );

      final captured = await conceding.capture('write the report 45 minutes');
      final session = captured.sessions.first;
      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 30)));

      const release = NegotiationProposal(
        action: NegotiationAction.release,
        message: 'Leaving it for today.',
      );
      final closed = await conceding.applyNegotiation(session.id, release);

      // The bug this pins: release used to return null on success as well as
      // on refusal, so the chat card could not tell them apart and reported
      // "Let go for today" over a block it had failed to release.
      expect(closed, isNotNull);
      expect(closed!.status, SessionStatus.skipped);
      expect((await sessions.byId(session.id))!.status, SessionStatus.skipped);
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isEmpty,
      );
    });

    test('null from applyNegotiation means refused, and only that', () async {
      final session = await stall('write the report 60 minutes', late: 2);
      const release = NegotiationProposal(
        action: NegotiationAction.release,
        message: 'Leaving it for today.',
      );

      expect(await service.applyNegotiation(session.id, release), isNull);
      expect((await sessions.byId(session.id))!.status, SessionStatus.planned);
    });

    test('a reason does not unlock actions the level still forbids', () async {
      // Explaining yourself earns a smaller ask, not a blank cheque. Shrink
      // becomes permitted at l3; release does not until l5.
      final session = await stall('write the report 60 minutes', late: 5);
      const release = NegotiationProposal(
        action: NegotiationAction.release,
        message: 'Leaving it for today.',
      );

      expect(
        await service.applyNegotiation(
          session.id,
          release,
          reason: 'genuinely too tired',
        ),
        isNull,
      );
      expect((await sessions.byId(session.id))!.status, SessionStatus.planned);
    });

    test('negotiating a session that does not exist is harmless', () async {
      expect(await service.negotiate('nope'), isNull);
    });
  });

  group('the stale-session sweep', () {
    /// Captures a task and walks the clock past the point where the nudge
    /// engine has given up on the resulting block.
    Future<WorkSession> abandon(String sentence) async {
      final result = await service.capture(sentence);
      final session = result.sessions.first;
      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 90)));
      return session;
    }

    test('an abandoned block gets a new home and a new ladder', () async {
      final session = await abandon('read the paper 45 minutes');

      final report = await service.sweepStaleSessions();

      expect(report.moved, hasLength(1));
      expect(report.dropped, isEmpty);

      final replacement = report.moved.single;
      expect(replacement.parentSessionId, session.id);
      expect(replacement.rescheduleCount, 1);
      expect(replacement.plannedMinutes, session.plannedMinutes);
      expect(replacement.plannedStart.isAfter(clock.now()), isTrue);

      expect(
        notifications.scheduled.where((n) => n.sessionId == replacement.id),
        hasLength(3),
        reason: 'the moved block needs its own ladder',
      );
    });

    test('the original is closed and its rungs stood down', () async {
      final session = await abandon('write the report 45 minutes');
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isNotEmpty,
      );

      await service.sweepStaleSessions();

      final reloaded = await sessions.byId(session.id);
      expect(reloaded!.status, SessionStatus.rescheduled);
      expect(reloaded.isResolved, isTrue);
      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isEmpty,
        reason: 'a block that has been moved must stop nudging',
      );
    });

    test('it records both the miss and the move', () async {
      await abandon('practise scales 45 minutes');
      await service.sweepStaleSessions();

      final missed = await events.ofType(EventType.sessionMissed);
      expect(missed, hasLength(1));
      expect(missed.single.field<String>('reason'), 'stale');
      expect(missed.single.field<String>('outcome'), 'rescheduled');
      expect(missed.single.field<int>('minutesLate'), 90);

      final moves = await events.ofType(EventType.rescheduleApplied);
      expect(moves, hasLength(1));
      expect(moves.single.field<String>('reason'), 'sweep');
      expect(moves.single.field<int>('moves'), 1);
    });

    test('a block Van is still nudging about is left alone', () async {
      final result = await service.capture('stretch 30 minutes');
      final session = result.sessions.first;
      // Half an hour late: the ladder has not finished with it yet.
      clock.advanceTo(session.plannedStart.add(const Duration(minutes: 30)));

      expect((await service.sweepStaleSessions()).isEmpty, isTrue);
      expect((await sessions.byId(session.id))!.status, SessionStatus.planned);
    });

    test('a session the user actually started is never swept', () async {
      final result = await service.capture('deep work 60 minutes');
      final session = result.sessions.first;
      await service.startSession(session.id);

      clock.advanceTo(session.plannedStart.add(const Duration(hours: 4)));

      expect((await service.sweepStaleSessions()).isEmpty, isTrue);
      expect((await sessions.byId(session.id))!.status, SessionStatus.started);
    });

    test('sweeping again straight away does nothing', () async {
      await abandon('inbox zero 45 minutes');
      expect((await service.sweepStaleSessions()).moved, hasLength(1));
      expect(
        (await service.sweepStaleSessions()).isEmpty,
        isTrue,
        reason: 'the sweep must not churn work it has just placed',
      );
    });

    test('work that can no longer meet its deadline is dropped', () async {
      final result = await service.capture(
        'submit the form by tomorrow 30 minutes',
      );
      final session = result.sessions.first;
      // Well past both the block and the deadline it existed to protect.
      clock.advanceTo(result.task.deadline!.add(const Duration(hours: 2)));

      final report = await service.sweepStaleSessions();

      expect(report.moved, isEmpty);
      expect(report.dropped, hasLength(1));
      expect(report.dropped.single.reason, SweepSkipReason.pastDeadline);

      final reloaded = await sessions.byId(session.id);
      expect(reloaded!.status, SessionStatus.skipped);

      final missed = await events.ofType(EventType.sessionMissed);
      expect(missed.single.field<String>('outcome'), 'dropped');
      expect(missed.single.field<String>('skipReason'), 'pastDeadline');
      expect(await events.ofType(EventType.rescheduleApplied), isEmpty);
    });

    test('two abandoned blocks are both rescued, without colliding', () async {
      final first = await service.capture('task one 45 minutes');
      final second = await service.capture('task two 45 minutes');
      final latest = [
        first.sessions.first.plannedStart,
        second.sessions.first.plannedStart,
      ].reduce((a, b) => a.isAfter(b) ? a : b);
      clock.advanceTo(latest.add(const Duration(minutes: 90)));

      final report = await service.sweepStaleSessions();

      expect(report.moved, hasLength(2));
      final a = report.moved[0];
      final b = report.moved[1];
      expect(
        a.plannedEnd.isAfter(b.plannedStart) &&
            b.plannedEnd.isAfter(a.plannedStart),
        isFalse,
        reason: 'rescued blocks must not be double-booked: $a vs $b',
      );
    });
  });
}

/// Forces the ladder to its top rung, so the release path can be exercised
/// without three snoozes and a refusal first.
class _AlwaysConcede extends InterventionPolicy {
  const _AlwaysConcede();

  @override
  InterventionLevel select(InterventionContext context) =>
      InterventionLevel.l5Concede;
}
