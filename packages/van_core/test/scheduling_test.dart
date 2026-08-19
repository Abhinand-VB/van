import 'package:van_core/van_core.dart';
import 'package:test/test.dart';

DateTime u(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, day, hour, minute);

/// Offset-zero waking hours keep the arithmetic in these tests readable.
const utcWaking = WakingHours(utcOffset: Duration.zero);

Task task({int? minutes = 240, DateTime? deadline}) => Task(
  id: 't1',
  title: 'Database assignment',
  createdAt: u(19, 8),
  estimatedMinutes: minutes,
  deadline: deadline,
);

FreeSlot slot(DateTime start, DateTime end) => FreeSlot(start: start, end: end);

void main() {
  group('FreeSlot', () {
    test('reports its length in minutes', () {
      expect(slot(u(19, 18), u(19, 20)).minutes, 120);
    });

    test('clippedFrom trims the front, or vanishes', () {
      final s = slot(u(19, 18), u(19, 20));
      expect(s.clippedFrom(u(19, 17)), s);
      expect(s.clippedFrom(u(19, 19)), slot(u(19, 19), u(19, 20)));
      expect(s.clippedFrom(u(19, 20)), isNull);
      expect(s.clippedFrom(u(19, 21)), isNull);
    });

    test('clippedTo trims the back, or vanishes', () {
      final s = slot(u(19, 18), u(19, 20));
      expect(s.clippedTo(u(19, 21)), s);
      expect(s.clippedTo(u(19, 19)), slot(u(19, 18), u(19, 19)));
      expect(s.clippedTo(u(19, 18)), isNull);
    });
  });

  group('WakingHours', () {
    test('maps a UTC instant to the wall clock the user reads', () {
      const ist = WakingHours(utcOffset: Duration(hours: 5, minutes: 30));
      expect(ist.toLocalWall(u(19, 12)), DateTime.utc(2026, 8, 19, 17, 30));
    });

    test('produces the waking window for the local day, in UTC', () {
      const ist = WakingHours(
        startHour: 8,
        endHour: 23,
        utcOffset: Duration(hours: 5, minutes: 30),
      );
      // 19 Aug 18:00 UTC is 23:30 IST, i.e. still the 19th locally.
      final window = ist.windowForDayOf(u(19, 12));
      expect(window.start, DateTime.utc(2026, 8, 19, 2, 30)); // 08:00 IST
      expect(window.end, DateTime.utc(2026, 8, 19, 17, 30)); // 23:00 IST
    });
  });

  group('FreeSlotFinder', () {
    const finder = FreeSlotFinder(waking: utcWaking);

    test('an empty diary yields the whole waking window', () {
      final slots = finder.find(
        commitments: const [],
        from: u(19, 8),
        to: u(19, 23),
      );
      expect(slots, [slot(u(19, 8), u(19, 23))]);
    });

    test('never returns a slot outside waking hours', () {
      final slots = finder.find(
        commitments: const [],
        from: u(19, 0),
        to: u(20, 0),
      );
      expect(slots.single.start, u(19, 8));
      expect(slots.single.end, u(19, 23));
    });

    test('a commitment splits the window in two', () {
      final slots = finder.find(
        commitments: [Commitment(start: u(19, 10), end: u(19, 12))],
        from: u(19, 8),
        to: u(19, 23),
      );
      expect(slots, [slot(u(19, 8), u(19, 10)), slot(u(19, 12), u(19, 23))]);
    });

    test('overlapping commitments are merged, not double-counted', () {
      final slots = finder.find(
        commitments: [
          Commitment(start: u(19, 10), end: u(19, 12)),
          Commitment(start: u(19, 11), end: u(19, 14)),
        ],
        from: u(19, 8),
        to: u(19, 23),
      );
      expect(slots, [slot(u(19, 8), u(19, 10)), slot(u(19, 14), u(19, 23))]);
    });

    test('adjacent commitments collapse into one busy block', () {
      final slots = finder.find(
        commitments: [
          Commitment(start: u(19, 10), end: u(19, 12)),
          Commitment(start: u(19, 12), end: u(19, 13)),
        ],
        from: u(19, 8),
        to: u(19, 23),
      );
      expect(slots, [slot(u(19, 8), u(19, 10)), slot(u(19, 13), u(19, 23))]);
    });

    test('a commitment covering the whole window leaves nothing', () {
      final slots = finder.find(
        commitments: [Commitment(start: u(19, 7), end: u(20, 1))],
        from: u(19, 8),
        to: u(19, 23),
      );
      expect(slots, isEmpty);
    });

    test('a multi-day horizon never produces an overnight slot', () {
      // The important property: the gap from 23:00 to 08:00 is not free time.
      // A planner that thinks it is will schedule work at 3am.
      final slots = finder.find(
        commitments: const [],
        from: u(19, 8),
        to: u(21, 23),
      );
      expect(slots.length, 3);
      for (final s in slots) {
        expect(s.start.hour, 8);
        expect(s.end.hour, 23);
      }
    });

    test('an inverted horizon yields nothing', () {
      expect(
        finder.find(commitments: const [], from: u(19, 20), to: u(19, 8)),
        isEmpty,
      );
    });

    test('commitments outside the horizon are ignored', () {
      final slots = finder.find(
        commitments: [Commitment(start: u(25, 10), end: u(25, 12))],
        from: u(19, 8),
        to: u(19, 23),
      );
      expect(slots, [slot(u(19, 8), u(19, 23))]);
    });
  });

  group('SessionPlanner', () {
    late SequentialIds ids;
    late SessionPlanner planner;
    late FakeClock clock;

    setUp(() {
      ids = SequentialIds('s');
      clock = FakeClock(u(19, 8));
      planner = SessionPlanner(ids: ids, waking: utcWaking);
    });

    test('a 4 hour task becomes several blocks, never one', () {
      final result = planner.plan(
        task: task(minutes: 240),
        slots: [slot(u(19, 8), u(19, 23))],
        clock: clock,
      );
      final sessions = result.okOrNull!;
      expect(sessions.length, 3);
      for (final s in sessions) {
        expect(s.plannedMinutes, lessThanOrEqualTo(90));
      }
      expect(
        sessions.fold<int>(0, (sum, s) => sum + s.plannedMinutes),
        240,
      );
    });

    test('leaves a break between consecutive blocks', () {
      final sessions = planner
          .plan(
            task: task(minutes: 180),
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      for (var i = 1; i < sessions.length; i++) {
        final gap = sessions[i].plannedStart
            .difference(sessions[i - 1].plannedEnd)
            .inMinutes;
        expect(gap, greaterThanOrEqualTo(10));
      }
    });

    test('a task that fits exactly is fully placed', () {
      final result = planner.plan(
        task: task(minutes: 60),
        slots: [slot(u(19, 18), u(19, 19))],
        clock: clock,
      );
      expect(result.isOk, isTrue);
      expect(result.okOrNull!.single.plannedMinutes, 60);
    });

    test('reports the shortfall when the week is too full', () {
      final result = planner.plan(
        task: task(minutes: 240),
        slots: [slot(u(19, 18), u(19, 19))],
        clock: clock,
      );
      final failure = result.errOrNull!;
      expect(failure.kind, PlanFailureKind.insufficientTime);
      expect(failure.shortfallMinutes, 180);
      expect(failure.scheduled.single.plannedMinutes, 60);
    });

    test('refuses a deadline that has already passed', () {
      final result = planner.plan(
        task: task(deadline: u(18, 23)),
        slots: [slot(u(19, 8), u(19, 23))],
        clock: clock,
      );
      expect(result.errOrNull!.kind, PlanFailureKind.deadlinePassed);
    });

    test('with no slots at all, everything is shortfall', () {
      final result = planner.plan(
        task: task(minutes: 90),
        slots: const [],
        clock: clock,
      );
      expect(result.errOrNull!.shortfallMinutes, 90);
      expect(result.errOrNull!.scheduled, isEmpty);
    });

    test('skips a slot shorter than the minimum block', () {
      final result = planner.plan(
        task: task(minutes: 60),
        slots: [slot(u(19, 18), u(19, 18, 10)), slot(u(19, 20), u(19, 21))],
        clock: clock,
      );
      final sessions = result.okOrNull!;
      expect(sessions.single.plannedStart, u(19, 20));
    });

    test('places a final remainder smaller than the minimum block', () {
      // 100 minutes with a 90 cap leaves 10, which is below the 15 minute
      // minimum. Dropping it would silently lose work, so it is placed.
      final sessions = planner
          .plan(
            task: task(minutes: 100),
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      expect(sessions.map((s) => s.plannedMinutes), [90, 10]);
    });

    test('never schedules in the past', () {
      clock.advanceTo(u(19, 20));
      final sessions = planner
          .plan(
            task: task(minutes: 60),
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      expect(sessions.single.plannedStart, u(19, 20));
    });

    test('finishes well before the deadline, not at it', () {
      final sessions = planner
          .plan(
            task: task(minutes: 60, deadline: u(20, 23)),
            slots: [slot(u(19, 8), u(19, 23)), slot(u(20, 8), u(20, 23))],
            clock: clock,
          )
          .okOrNull!;
      final last = sessions.last.plannedEnd;
      expect(last.isBefore(u(20, 11)), isTrue); // 23:00 minus 12h buffer
    });

    test('caps how many blocks land on one day', () {
      final result = planner.plan(
        task: task(minutes: 600),
        slots: [slot(u(19, 8), u(19, 23))],
        clock: clock,
      );
      expect(result.errOrNull!.scheduled.length, 3);
    });

    test('spreads across days when one day is not enough', () {
      final sessions = planner
          .plan(
            task: task(minutes: 300),
            slots: [slot(u(19, 8), u(19, 23)), slot(u(20, 8), u(20, 23))],
            clock: clock,
          )
          .okOrNull!;
      final days = sessions.map((s) => s.plannedStart.day).toSet();
      expect(days.length, 2);
    });

    test('assumes a default estimate when the user never gave one', () {
      final sessions = planner
          .plan(
            task: task(minutes: null),
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      expect(sessions.single.plannedMinutes, 60);
    });

    test('every session points back at its task and starts unresolved', () {
      final sessions = planner
          .plan(
            task: task(minutes: 120),
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      for (final s in sessions) {
        expect(s.taskId, 't1');
        expect(s.status, SessionStatus.planned);
        expect(s.rescheduleCount, 0);
      }
    });

    test('ids come from the injected generator, so plans are reproducible', () {
      final sessions = planner
          .plan(
            task: task(minutes: 120),
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      expect(sessions.map((s) => s.id), ['s1', 's2']);
    });
  });

  group('Rescheduler', () {
    late Rescheduler rescheduler;
    late FakeClock clock;
    late WorkSession missed;

    setUp(() {
      rescheduler = Rescheduler(ids: SequentialIds('r'));
      clock = FakeClock(u(19, 19));
      missed = WorkSession(
        id: 's1',
        taskId: 't1',
        plannedStart: u(19, 18),
        plannedMinutes: 45,
      );
    });

    test('moves a missed block to the next slot that fits', () {
      final result = rescheduler.reschedule(
        missed: missed,
        slots: [slot(u(19, 20), u(19, 22))],
        clock: clock,
      );
      final next = result.okOrNull!;
      expect(next.plannedStart, u(19, 20));
      expect(next.plannedMinutes, 45);
    });

    test('the replacement records the move and its parent', () {
      final next = rescheduler
          .reschedule(
            missed: missed,
            slots: [slot(u(19, 20), u(19, 22))],
            clock: clock,
          )
          .okOrNull!;
      expect(next.rescheduleCount, 1);
      expect(next.parentSessionId, 's1');
      expect(next.id, 'r1');
    });

    test('never places the replacement in the past', () {
      final next = rescheduler
          .reschedule(
            missed: missed,
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      expect(next.plannedStart.isAfter(clock.now()), isTrue);
    });

    test('leaves a little breathing room rather than firing immediately', () {
      final next = rescheduler
          .reschedule(
            missed: missed,
            slots: [slot(u(19, 8), u(19, 23))],
            clock: clock,
          )
          .okOrNull!;
      expect(next.plannedStart, u(19, 19, 5));
    });

    test('skips a slot that is too small and takes the next', () {
      final next = rescheduler
          .reschedule(
            missed: missed,
            slots: [slot(u(19, 20), u(19, 20, 20)), slot(u(19, 21), u(19, 22))],
            clock: clock,
          )
          .okOrNull!;
      expect(next.plannedStart, u(19, 21));
    });

    test('shrinking lets the block fit where the full one would not', () {
      final tooSmall = [slot(u(19, 20), u(19, 20, 20))];
      expect(
        rescheduler
            .reschedule(missed: missed, slots: tooSmall, clock: clock)
            .isErr,
        isTrue,
      );

      final shrunk = rescheduler
          .reschedule(
            missed: missed,
            slots: tooSmall,
            clock: clock,
            shrinkTo: 10,
          )
          .okOrNull!;
      expect(shrunk.plannedMinutes, 10);
      expect(shrunk.rescheduleCount, 1);
    });

    test('reports when nothing is left at all', () {
      final result = rescheduler.reschedule(
        missed: missed,
        slots: const [],
        clock: clock,
      );
      expect(result.errOrNull!.kind, RescheduleFailureKind.noSlotAvailable);
    });

    test('distinguishes past the deadline from simply full', () {
      final result = rescheduler.reschedule(
        missed: missed,
        slots: [slot(u(21, 8), u(21, 23))],
        clock: clock,
        deadline: u(20, 12),
      );
      expect(result.errOrNull!.kind, RescheduleFailureKind.pastDeadline);
    });

    test('move counts keep climbing across repeated slips', () {
      var session = missed;
      for (var i = 0; i < 3; i++) {
        session = rescheduler
            .reschedule(
              missed: session,
              slots: [slot(u(20 + i, 8), u(20 + i, 23))],
              clock: clock,
            )
            .okOrNull!;
      }
      expect(session.rescheduleCount, 3);
    });
  });
}
