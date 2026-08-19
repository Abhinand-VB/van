import 'package:nova_core/nova_core.dart';
import 'package:test/test.dart';

DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, day, hour, minute);

Task aTask({DateTime? deadline, TaskStatus status = TaskStatus.inbox}) => Task(
  id: 't1',
  title: 'Database assignment',
  createdAt: at(19, 9),
  deadline: deadline,
  status: status,
);

WorkSession aSession({
  DateTime? plannedStart,
  int minutes = 45,
  int rescheduleCount = 0,
}) => WorkSession(
  id: 's1',
  taskId: 't1',
  plannedStart: plannedStart ?? at(19, 18),
  plannedMinutes: minutes,
  rescheduleCount: rescheduleCount,
);

void main() {
  group('Task', () {
    test('rejects an empty title', () {
      expect(
        () => Task(id: 't', title: '', createdAt: at(19, 9)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a non-UTC createdAt', () {
      expect(
        () => Task(id: 't', title: 'x', createdAt: DateTime(2026, 8, 19)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a non-positive estimate', () {
      expect(
        () => Task(
          id: 't',
          title: 'x',
          createdAt: at(19, 9),
          estimatedMinutes: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('is not overdue before the deadline', () {
      final task = aTask(deadline: at(21, 23));
      expect(task.isOverdue(at(19, 9)), isFalse);
    });

    test('is overdue after the deadline', () {
      final task = aTask(deadline: at(21, 23));
      expect(task.isOverdue(at(22, 9)), isTrue);
    });

    test('a done task is never overdue', () {
      final task = aTask(deadline: at(21, 23), status: TaskStatus.done);
      expect(task.isOverdue(at(22, 9)), isFalse);
    });

    test('a task without a deadline is never overdue', () {
      expect(aTask().isOverdue(at(30, 9)), isFalse);
    });

    test('hoursUntilDeadline is null without a deadline', () {
      expect(aTask().hoursUntilDeadline(at(19, 9)), isNull);
    });

    test('hoursUntilDeadline counts down and goes negative', () {
      final task = aTask(deadline: at(19, 18));
      expect(task.hoursUntilDeadline(at(19, 12)), 6.0);
      expect(task.hoursUntilDeadline(at(19, 20)), -2.0);
    });

    test('copyWith replaces only what is given', () {
      final task = aTask(deadline: at(21, 23));
      final moved = task.copyWith(status: TaskStatus.active);
      expect(moved.status, TaskStatus.active);
      expect(moved.title, task.title);
      expect(moved.deadline, task.deadline);
      expect(moved.id, task.id);
    });

    test('withoutDeadline clears the deadline copyWith cannot', () {
      final task = aTask(deadline: at(21, 23));
      expect(task.withoutDeadline().deadline, isNull);
      expect(task.copyWith().deadline, isNotNull);
    });

    test('compares by value', () {
      expect(aTask(), aTask());
      expect(aTask().hashCode, aTask().hashCode);
      expect(aTask(), isNot(aTask(status: TaskStatus.done)));
    });
  });

  group('WorkSession timing', () {
    test('plannedEnd is start plus duration', () {
      expect(aSession().plannedEnd, at(19, 18, 45));
    });

    test('minutesLate is zero before the planned start', () {
      expect(aSession().minutesLate(at(19, 17)), 0);
    });

    test('minutesLate counts from the planned start', () {
      expect(aSession().minutesLate(at(19, 18, 25)), 25);
    });

    test('minutesLate is zero once started, however late', () {
      final started = aSession().start(at(19, 18, 40));
      expect(started.minutesLate(at(19, 19)), 0);
    });

    test('isMissed only after the whole block has elapsed', () {
      final session = aSession();
      expect(session.isMissed(at(19, 18, 30)), isFalse);
      expect(session.isMissed(at(19, 19)), isTrue);
    });

    test('a started session is never missed', () {
      final started = aSession().start(at(19, 18));
      expect(started.isMissed(at(19, 23)), isFalse);
    });
  });

  group('WorkSession transitions', () {
    test('start records the instant and the status', () {
      final session = aSession().start(at(19, 18, 3));
      expect(session.actualStart, at(19, 18, 3));
      expect(session.status, SessionStatus.started);
      expect(session.hasStarted, isTrue);
    });

    test('complete keeps the original start', () {
      final session = aSession().start(at(19, 18)).complete(at(19, 18, 45));
      expect(session.actualStart, at(19, 18));
      expect(session.actualEnd, at(19, 18, 45));
      expect(session.status, SessionStatus.completed);
    });

    test('complete without a prior start backfills it', () {
      final session = aSession().complete(at(19, 18, 45));
      expect(session.actualStart, at(19, 18, 45));
    });

    test('stopEarly marks partial, which still counts as initiation', () {
      final session = aSession().start(at(19, 18)).stopEarly(at(19, 18, 12));
      expect(session.status, SessionStatus.partial);
      expect(session.hasStarted, isTrue);
    });

    test('skip and markRescheduled both resolve the session', () {
      expect(aSession().skip().isResolved, isTrue);
      expect(aSession().markRescheduled().isResolved, isTrue);
      expect(aSession().isResolved, isFalse);
      expect(aSession().start(at(19, 18)).isResolved, isFalse);
    });

    test('replacement increments the move count and links the parent', () {
      final original = aSession();
      final next = original.replacement(newId: 's2', newStart: at(20, 18));
      expect(next.rescheduleCount, 1);
      expect(next.parentSessionId, 's1');
      expect(next.plannedMinutes, 45);
      expect(next.taskId, 't1');
      expect(next.status, SessionStatus.planned);
    });

    test('replacement can shrink the block, which is what L3 does', () {
      final next = aSession().replacement(
        newId: 's2',
        newStart: at(20, 18),
        newMinutes: 10,
      );
      expect(next.plannedMinutes, 10);
    });

    test('move counts accumulate across repeated reschedules', () {
      var session = aSession();
      for (var i = 2; i <= 4; i++) {
        session = session.replacement(newId: 's$i', newStart: at(19 + i, 18));
      }
      expect(session.rescheduleCount, 3);
    });
  });

  group('Nudge', () {
    Nudge aNudge({bool suppressed = false, String? reason}) => Nudge(
      id: 'n1',
      type: NudgeType.sessionMissed,
      importance: 7,
      level: InterventionLevel.l1Check,
      scheduledAt: at(19, 18, 10),
      copy: 'Starting, or moving it?',
      wasSuppressed: suppressed,
      suppressionReason: reason,
    );

    test('base importance is attached to the type', () {
      expect(NudgeType.hydration.baseImportance, 2);
      expect(NudgeType.sessionStart.baseImportance, 6);
      expect(NudgeType.meetingImminent.baseImportance, 10);
    });

    test('a suppressed nudge must record why', () {
      expect(() => aNudge(suppressed: true), throwsA(isA<AssertionError>()));
      expect(
        () => aNudge(suppressed: true, reason: 'quiet hours'),
        returnsNormally,
      );
    });

    test('is not delivered until it is', () {
      expect(aNudge().wasDelivered, isFalse);
      expect(aNudge().deliver(at(19, 18, 11)).wasDelivered, isTrue);
    });

    test('a suppressed nudge is never counted as delivered', () {
      final suppressed = aNudge(suppressed: true, reason: 'focus in progress');
      expect(suppressed.wasDelivered, isFalse);
    });
  });

  group('NudgeResponse', () {
    test('a reason response must carry text', () {
      expect(
        () => NudgeResponse(
          id: 'r1',
          nudgeId: 'n1',
          response: ResponseType.reason,
          respondedAt: at(19, 18, 12),
          latencySeconds: 120,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects negative latency', () {
      expect(
        () => NudgeResponse(
          id: 'r1',
          nudgeId: 'n1',
          response: ResponseType.started,
          respondedAt: at(19, 18, 12),
          latencySeconds: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('only a start counts as leading to work', () {
      NudgeResponse of(ResponseType t) => NudgeResponse(
        id: 'r',
        nudgeId: 'n',
        response: t,
        respondedAt: at(19, 18),
        latencySeconds: 5,
      );
      expect(of(ResponseType.started).ledToStart, isTrue);
      expect(of(ResponseType.snoozed).ledToStart, isFalse);
      expect(of(ResponseType.dismissed).ledToStart, isFalse);
      expect(of(ResponseType.ignored).ledToStart, isFalse);
    });
  });

  group('NovaEvent', () {
    test('is unpersisted until it has a row id', () {
      final event = NovaEvent(
        type: EventType.taskCreated,
        timestamp: at(19, 9),
      );
      expect(event.isPersisted, isFalse);
      expect(
        NovaEvent(
          type: EventType.taskCreated,
          timestamp: at(19, 9),
          id: 7,
        ).isPersisted,
        isTrue,
      );
    });

    test('rejects a non-UTC timestamp', () {
      expect(
        () => NovaEvent(
          type: EventType.taskCreated,
          timestamp: DateTime(2026, 8, 19),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('field reads typed payload values and tolerates misses', () {
      final event = NovaEvent(
        type: EventType.nudgeSuppressed,
        timestamp: at(19, 18),
        payload: const {'reason': 'quiet hours', 'importance': 6},
      );
      expect(event.field<String>('reason'), 'quiet hours');
      expect(event.field<int>('importance'), 6);
      expect(event.field<String>('missing'), isNull);
      expect(event.field<int>('reason'), isNull);
    });
  });
}
