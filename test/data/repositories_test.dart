import 'package:flutter_test/flutter_test.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van_core/van_core.dart';

DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, day, hour, minute);

void main() {
  late VanDatabase db;
  late TaskRepo tasks;
  late SessionRepo sessions;
  late NudgeRepo nudges;
  late EventRepo events;
  late FakeClock clock;

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(at(19, 9));
    tasks = TaskRepo(db);
    sessions = SessionRepo(db);
    nudges = NudgeRepo(db);
    events = EventRepo(db, clock);
  });

  tearDown(() async => db.close());

  Task makeTask({
    String id = 't1',
    DateTime? deadline,
    TaskStatus status = TaskStatus.inbox,
    int? estimate,
  }) => Task(
    id: id,
    title: 'Database assignment',
    createdAt: at(19, 9),
    deadline: deadline,
    status: status,
    estimatedMinutes: estimate,
    priority: Priority.high,
    source: TaskSource.chat,
  );

  WorkSession makeSession({
    String id = 's1',
    String taskId = 't1',
    DateTime? start,
    SessionStatus status = SessionStatus.planned,
    int moves = 0,
  }) => WorkSession(
    id: id,
    taskId: taskId,
    plannedStart: start ?? at(19, 18),
    plannedMinutes: 45,
    status: status,
    rescheduleCount: moves,
  );

  Nudge makeNudge({
    String id = 'n1',
    String? sessionId = 's1',
    NudgeType type = NudgeType.sessionMissed,
    DateTime? delivered,
    bool suppressed = false,
    String? reason,
  }) => Nudge(
    id: id,
    sessionId: sessionId,
    type: type,
    importance: 7,
    level: InterventionLevel.l1Check,
    scheduledAt: at(19, 18, 10),
    copy: 'Starting, or moving it?',
    deliveredAt: delivered,
    wasSuppressed: suppressed,
    suppressionReason: reason,
  );

  group('TaskRepo', () {
    test('round-trips every field', () async {
      final task = makeTask(deadline: at(21, 23), estimate: 240);
      await tasks.save(task);
      expect(await tasks.byId('t1'), task);
    });

    test('round-trips a task with no optional fields', () async {
      final task = Task(id: 't9', title: 'Minimal', createdAt: at(19, 9));
      await tasks.save(task);
      expect(await tasks.byId('t9'), task);
    });

    test('returns null for an unknown id', () async {
      expect(await tasks.byId('nope'), isNull);
    });

    test('save replaces an existing task', () async {
      await tasks.save(makeTask());
      await tasks.save(makeTask(status: TaskStatus.done));
      expect((await tasks.all()).length, 1);
      expect((await tasks.byId('t1'))!.status, TaskStatus.done);
    });

    test('open excludes finished and abandoned tasks', () async {
      await tasks.save(makeTask(id: 'a'));
      await tasks.save(makeTask(id: 'b', status: TaskStatus.done));
      await tasks.save(makeTask(id: 'c', status: TaskStatus.abandoned));
      expect((await tasks.open()).map((t) => t.id), ['a']);
    });

    test('open sorts by deadline with undated tasks last', () async {
      await tasks.save(makeTask(id: 'late', deadline: at(25, 12)));
      await tasks.save(makeTask(id: 'none'));
      await tasks.save(makeTask(id: 'soon', deadline: at(20, 12)));
      expect((await tasks.open()).map((t) => t.id), ['soon', 'late', 'none']);
    });

    test('dueBefore respects the cutoff and the status filter', () async {
      await tasks.save(makeTask(id: 'soon', deadline: at(20, 12)));
      await tasks.save(makeTask(id: 'later', deadline: at(28, 12)));
      await tasks.save(
        makeTask(id: 'done', deadline: at(20, 12), status: TaskStatus.done),
      );
      final due = await tasks.dueBefore(at(21, 0));
      expect(due.map((t) => t.id), ['soon']);
    });
  });

  group('timezone handling', () {
    test(
      'a local 23:59 deadline survives the round trip as the same instant',
      () async {
        // The classic bug: storing local time makes every query wrong twice a
        // year. Everything is persisted as UTC epoch millis.
        final localDeadline = DateTime(2026, 8, 21, 23, 59);
        final task = Task(
          id: 'tz',
          title: 'Due at the very end of the day',
          createdAt: at(19, 9),
          deadline: localDeadline.toUtc(),
        );
        await tasks.save(task);

        final loaded = await tasks.byId('tz');
        expect(loaded!.deadline!.isUtc, isTrue);
        expect(
          loaded.deadline!.millisecondsSinceEpoch,
          localDeadline.millisecondsSinceEpoch,
        );
        expect(loaded.deadline!.toLocal(), localDeadline);
      },
    );

    test('session instants stay UTC after reload', () async {
      await tasks.save(makeTask());
      await sessions.save(makeSession().start(at(19, 18, 4)));
      final loaded = await sessions.byId('s1');
      expect(loaded!.plannedStart.isUtc, isTrue);
      expect(loaded.actualStart!.isUtc, isTrue);
      expect(loaded.actualStart, at(19, 18, 4));
    });
  });

  group('SessionRepo', () {
    setUp(() async => tasks.save(makeTask()));

    test('round-trips a fully populated session', () async {
      final session = makeSession(
        moves: 2,
      ).start(at(19, 18, 2)).complete(at(19, 18, 47));
      await sessions.save(session);
      expect(await sessions.byId('s1'), session);
    });

    test('saveAll writes a whole plan at once', () async {
      await sessions.saveAll([
        makeSession(id: 'a', start: at(19, 18)),
        makeSession(id: 'b', start: at(20, 18)),
        makeSession(id: 'c', start: at(21, 18)),
      ]);
      expect((await sessions.forTask('t1')).length, 3);
    });

    test('forTask returns sessions in planned order', () async {
      await sessions.saveAll([
        makeSession(id: 'c', start: at(21, 18)),
        makeSession(id: 'a', start: at(19, 18)),
        makeSession(id: 'b', start: at(20, 18)),
      ]);
      expect((await sessions.forTask('t1')).map((s) => s.id), [
        'a',
        'b',
        'c',
      ]);
    });

    test('plannedBetween is half-open on the upper bound', () async {
      await sessions.saveAll([
        makeSession(id: 'before', start: at(19, 17)),
        makeSession(id: 'inside', start: at(19, 18)),
        makeSession(id: 'edge', start: at(19, 19)),
      ]);
      final found = await sessions.plannedBetween(at(19, 18), at(19, 19));
      expect(found.map((s) => s.id), ['inside']);
    });

    test('unresolved omits completed and skipped sessions', () async {
      await sessions.saveAll([
        makeSession(id: 'planned'),
        makeSession(id: 'started', status: SessionStatus.started),
        makeSession(id: 'done', status: SessionStatus.completed),
        makeSession(id: 'skipped', status: SessionStatus.skipped),
      ]);
      final open = await sessions.unresolved();
      expect(open.map((s) => s.id).toSet(), {'planned', 'started'});
    });

    test('inProgress finds a running session, or null', () async {
      await sessions.save(makeSession(id: 'planned'));
      expect(await sessions.inProgress(), isNull);
      await sessions.save(
        makeSession(id: 'running', status: SessionStatus.started),
      );
      expect((await sessions.inProgress())!.id, 'running');
    });

    test('next returns the earliest planned session at or after now', () async {
      await sessions.saveAll([
        makeSession(id: 'past', start: at(19, 8)),
        makeSession(id: 'soon', start: at(19, 18)),
        makeSession(id: 'later', start: at(19, 20)),
      ]);
      expect((await sessions.next(at(19, 9)))!.id, 'soon');
    });

    test('next ignores sessions that already resolved', () async {
      await sessions.save(
        makeSession(id: 'moved', status: SessionStatus.rescheduled),
      );
      expect(await sessions.next(at(19, 9)), isNull);
    });

    test('a replacement session persists its lineage', () async {
      final original = makeSession();
      await sessions.save(original.markRescheduled());
      final next = original.replacement(newId: 's2', newStart: at(20, 18));
      await sessions.save(next);

      final loaded = await sessions.byId('s2');
      expect(loaded!.parentSessionId, 's1');
      expect(loaded.rescheduleCount, 1);
    });
  });

  group('NudgeRepo', () {
    test('round-trips a delivered nudge', () async {
      final nudge = makeNudge(delivered: at(19, 18, 11));
      await nudges.save(nudge);
      expect(await nudges.byId('n1'), nudge);
    });

    test('round-trips a suppressed nudge with its reason', () async {
      final nudge = makeNudge(
        id: 'n2',
        suppressed: true,
        reason: 'focus session in progress',
      );
      await nudges.save(nudge);
      final loaded = await nudges.byId('n2');
      expect(loaded!.wasSuppressed, isTrue);
      expect(loaded.suppressionReason, 'focus session in progress');
    });

    test('lastDelivered ignores suppressed nudges', () async {
      await nudges.save(makeNudge(id: 'a', delivered: at(19, 10)));
      await nudges.save(
        makeNudge(
          id: 'b',
          delivered: at(19, 12),
          suppressed: true,
          reason: 'quiet hours',
        ),
      );
      expect((await nudges.lastDelivered())!.id, 'a');
    });

    test('lastDelivered is null when nothing has been delivered', () async {
      await nudges.save(makeNudge(id: 'pending'));
      expect(await nudges.lastDelivered(), isNull);
    });

    test('deliveredSince filters by time', () async {
      await nudges.save(makeNudge(id: 'old', delivered: at(19, 8)));
      await nudges.save(makeNudge(id: 'new', delivered: at(19, 14)));
      final recent = await nudges.deliveredSince(at(19, 12));
      expect(recent.map((n) => n.id), ['new']);
    });

    test('responses are stored against their nudge', () async {
      await nudges.save(makeNudge(delivered: at(19, 18, 10)));
      await nudges.saveResponse(
        NudgeResponse(
          id: 'r1',
          nudgeId: 'n1',
          response: ResponseType.reason,
          reasonText: 'watching netflix',
          respondedAt: at(19, 18, 12),
          latencySeconds: 120,
        ),
      );
      final replies = await nudges.responsesFor('n1');
      expect(replies.single.reasonText, 'watching netflix');
      expect(replies.single.latencySeconds, 120);
    });

    /// Saves a delivered nudge with a settled response, which is the shape
    /// every fatigue case below is made of.
    Future<void> settled(
      String id, {
      required String? sessionId,
      required ResponseType response,
      required int minute,
    }) async {
      await nudges.save(
        makeNudge(id: id, sessionId: sessionId, delivered: at(19, minute)),
      );
      await nudges.saveResponse(
        NudgeResponse(
          id: 'r_$id',
          nudgeId: id,
          response: response,
          respondedAt: at(19, minute),
          latencySeconds: 3,
        ),
      );
    }

    test('a whole ignored ladder counts once, not once per rung', () async {
      // The 21 August bug exactly: three rungs of one block, all swept as
      // ignored, tripping a limit of three by themselves.
      for (var i = 1; i <= 3; i++) {
        await settled(
          'n$i',
          sessionId: 's1',
          response: ResponseType.ignored,
          minute: 9 + i,
        );
      }
      expect(
        await nudges.consecutiveUnansweredLadders(
          NudgeType.sessionMissed,
          at(19, 0),
        ),
        1,
      );
    });

    test('separate ignored ladders each count', () async {
      for (var i = 1; i <= 3; i++) {
        await settled(
          'n$i',
          sessionId: 's$i',
          response: ResponseType.ignored,
          minute: 9 + i,
        );
      }
      expect(
        await nudges.consecutiveUnansweredLadders(
          NudgeType.sessionMissed,
          at(19, 0),
        ),
        3,
      );
    });

    test(
      'an engaged reply breaks the streak at the ladder before it',
      () async {
        await settled(
          'n1',
          sessionId: 's1',
          response: ResponseType.started,
          minute: 10,
        );
        await settled(
          'n2',
          sessionId: 's2',
          response: ResponseType.dismissed,
          minute: 11,
        );
        expect(
          await nudges.consecutiveUnansweredLadders(
            NudgeType.sessionMissed,
            at(19, 0),
          ),
          1,
        );
      },
    );

    test(
      'answering late clears the ladder its earlier rungs belong to',
      () async {
        // L0 answered, then L1 armed and left. The ladder was engaged with, so
        // it must not be held against the user by its own later rung.
        await settled(
          'n1',
          sessionId: 's1',
          response: ResponseType.started,
          minute: 10,
        );
        await settled(
          'n2',
          sessionId: 's1',
          response: ResponseType.ignored,
          minute: 11,
        );
        expect(
          await nudges.consecutiveUnansweredLadders(
            NudgeType.sessionMissed,
            at(19, 0),
          ),
          0,
        );
      },
    );

    test('nudges with no ladder count individually', () async {
      for (var i = 1; i <= 2; i++) {
        await settled(
          'n$i',
          sessionId: null,
          response: ResponseType.ignored,
          minute: 9 + i,
        );
      }
      expect(
        await nudges.consecutiveUnansweredLadders(
          NudgeType.sessionMissed,
          at(19, 0),
        ),
        2,
      );
    });
  });

  group('EventRepo (append-only)', () {
    test('append returns the persisted event with a row id', () async {
      final event = await events.append(EventType.taskCreated, {
        'taskId': 't1',
      });
      expect(event.isPersisted, isTrue);
      expect(event.field<String>('taskId'), 't1');
    });

    test('stamps the clock when no time is given', () async {
      final event = await events.append(EventType.appOpened);
      expect(event.timestamp, at(19, 9));
    });

    test('honours an explicit timestamp', () async {
      final event = await events.append(
        EventType.sessionStarted,
        const {},
        at(19, 18),
      );
      expect(event.timestamp, at(19, 18));
    });

    test('payload round-trips through JSON with mixed types', () async {
      await events.append(EventType.nudgeSuppressed, const {
        'reason': 'quiet hours',
        'importance': 6,
        'suppressed': true,
        'score': 4.5,
      });
      final loaded = (await events.all()).single;
      expect(loaded.field<String>('reason'), 'quiet hours');
      expect(loaded.field<int>('importance'), 6);
      expect(loaded.field<bool>('suppressed'), isTrue);
      expect(loaded.field<double>('score'), 4.5);
    });

    test('an empty payload is preserved', () async {
      await events.append(EventType.appBackgrounded);
      expect((await events.all()).single.payload, isEmpty);
    });

    test('the log only ever grows', () async {
      // There is no update and no delete on EventRepo. This is the property
      // the whole design depends on, so it is asserted rather than assumed.
      expect(await events.count(), 0);
      for (var i = 0; i < 5; i++) {
        await events.append(EventType.appOpened);
      }
      expect(await events.count(), 5);
      await events.append(EventType.appBackgrounded);
      expect(await events.count(), 6);
    });

    test('since is inclusive of its lower bound', () async {
      await events.append(EventType.appOpened, const {}, at(19, 8));
      await events.append(EventType.appOpened, const {}, at(19, 9));
      await events.append(EventType.appOpened, const {}, at(19, 10));
      expect((await events.since(at(19, 9))).length, 2);
    });

    test('ofType filters and returns newest first', () async {
      await events.append(EventType.appOpened, const {}, at(19, 8));
      await events.append(EventType.sessionStarted, const {}, at(19, 9));
      await events.append(EventType.appOpened, const {}, at(19, 10));
      final opens = await events.ofType(EventType.appOpened);
      expect(opens.length, 2);
      expect(opens.first.timestamp, at(19, 10));
    });

    test('ofType respects the limit', () async {
      for (var i = 0; i < 10; i++) {
        await events.append(EventType.appOpened, const {}, at(19, 8 + i));
      }
      expect((await events.ofType(EventType.appOpened, limit: 3)).length, 3);
    });

    test('forSession finds events by payload, in order', () async {
      await events.append(EventType.sessionPlanned, const {
        'sessionId': 's1',
      }, at(19, 8));
      await events.append(EventType.sessionPlanned, const {
        'sessionId': 's2',
      }, at(19, 9));
      await events.append(EventType.sessionStarted, const {
        'sessionId': 's1',
      }, at(19, 18));

      final trail = await events.forSession('s1');
      expect(trail.map((e) => e.type), [
        EventType.sessionPlanned,
        EventType.sessionStarted,
      ]);
    });

    test('appendAll writes a burst atomically', () async {
      await events.appendAll([
        VanEvent(type: EventType.sessionMissed, timestamp: at(19, 19)),
        VanEvent(type: EventType.interventionSelected, timestamp: at(19, 19)),
        VanEvent(type: EventType.nudgeScheduled, timestamp: at(19, 19)),
      ]);
      expect(await events.count(), 3);
    });

    test(
      'all returns the log oldest first, stable within a timestamp',
      () async {
        await events.appendAll([
          VanEvent(type: EventType.sessionMissed, timestamp: at(19, 19)),
          VanEvent(
            type: EventType.interventionSelected,
            timestamp: at(19, 19),
          ),
        ]);
        await events.append(EventType.appOpened, const {}, at(19, 8));

        expect((await events.all()).map((e) => e.type), [
          EventType.appOpened,
          EventType.sessionMissed,
          EventType.interventionSelected,
        ]);
      },
    );
  });

  group('foreign keys', () {
    test('a session cannot reference a task that does not exist', () async {
      await expectLater(
        sessions.save(makeSession(taskId: 'ghost')),
        throwsA(isA<Exception>()),
      );
    });
  });
}
