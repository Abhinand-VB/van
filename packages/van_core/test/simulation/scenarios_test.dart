import 'package:van_core/van_core.dart';
import 'package:test/test.dart';

import 'simulation_harness.dart';

DateTime u(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, day, hour, minute);

SimulationHarness harnessAt(int day, int hour) =>
    SimulationHarness(startAt: u(day, hour));

void main() {
  group('the core escalation ladder', () {
    test('L0 to L1 to L2 to L3 as the user keeps not starting', () {
      final sim = harnessAt(19, 17)
        ..addTask('Database assignment', deadline: u(21, 23), minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 18));

      // Due now: a plain prompt.
      sim.advanceTo(u(19, 18));
      sim.expectNudge(
        level: InterventionLevel.l0Gentle,
        type: NudgeType.sessionStart,
      );
      sim.userIgnores();

      // Ten minutes late: is it starting, or moving?
      sim.advanceTo(u(19, 18, 10));
      sim.expectNudge(
        level: InterventionLevel.l1Check,
        type: NudgeType.sessionMissed,
      );
      sim.userIgnores();

      // Twenty-five minutes late: what is in the way?
      sim.advanceTo(u(19, 18, 25));
      sim.expectNudge(level: InterventionLevel.l2Diagnose);

      // They answer, so the next ask is smaller rather than louder.
      sim.userSays('watching netflix');
      sim.advanceBy(minutes: 15);
      sim.expectNudge(level: InterventionLevel.l3Shrink);
    });

    test('starting on time ends the conversation', () {
      final sim = harnessAt(19, 17)..addTask('Reading', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 18));

      sim.advanceTo(u(19, 18));
      sim.expectNudge(level: InterventionLevel.l0Gentle);
      sim.userStarts();

      // A running session must never be interrupted by Van itself.
      sim.advanceBy(hours: 1);
      sim.expectNoNudge();
      expect(sim.deliveredCount, 1);
    });
  });

  group('fatigue and spacing', () {
    test('three dismissals and Van stops raising that type today', () {
      final sim = harnessAt(19, 17)..addTask('Assignment', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 18));

      sim.advanceTo(u(19, 18));
      sim.expectNudge();
      sim.userIgnores();

      sim.advanceTo(u(19, 18, 10));
      sim.expectNudge();
      sim.userIgnores();

      sim.advanceTo(u(19, 18, 25));
      sim.expectNudge();
      sim.userIgnores();

      // Fourth is suppressed by fatigue and cannot be overridden.
      sim.advanceBy(hours: 3);
      sim.expectNoNudge();
      expect(sim.deliveredCount, 3, reason: sim.dumpTimeline());
    });

    test('a second nudge minutes after the first is held back', () {
      final sim = harnessAt(19, 17)
        ..addTask('First', minutes: 45)
        ..addTask('Second', minutes: 45);
      sim
        ..scheduleSession(taskId: 't1', start: u(19, 18))
        ..scheduleSession(taskId: 't2', start: u(19, 18, 5));

      sim.advanceTo(u(19, 18));
      sim.expectNudge();
      sim.userIgnores();

      // Five minutes later a different task comes due. Not urgent enough to
      // justify interrupting again so soon.
      sim.advanceTo(u(19, 18, 6));
      sim.expectNoNudge();
      expect(sim.deliveredCount, 1, reason: sim.dumpTimeline());
    });

    test('two blocks due at once produce one nudge, not two', () {
      final sim = harnessAt(19, 17)
        ..addTask('Urgent', deadline: u(19, 22), minutes: 45)
        ..addTask('Relaxed', minutes: 45);
      sim
        ..scheduleSession(taskId: 't1', start: u(19, 18))
        ..scheduleSession(taskId: 't2', start: u(19, 18));

      sim.advanceTo(u(19, 18));
      sim.expectNudge();
      // The one with the deadline four hours out wins on score.
      expect(sim.pendingSession!.taskId, 't1', reason: sim.dumpTimeline());
      expect(sim.deliveredCount, 1);
    });
  });

  group('quiet hours', () {
    test('a session block at 02:00 raises nothing', () {
      final sim = harnessAt(20, 1)..addTask('Late night', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(20, 2));

      sim.advanceTo(u(20, 3));
      sim.expectNoNudge();
      expect(sim.deliveredCount, 0, reason: sim.dumpTimeline());
    });

    test('a block missed overnight is not resurrected at breakfast', () {
      // It was due at 02:00 and is seven hours stale by morning. Firing then
      // would be an ambush about work whose moment has passed; the right
      // answer is to reschedule it, which is the app's job, not a nudge.
      final sim = harnessAt(20, 1)..addTask('Late night', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(20, 2));

      sim.advanceTo(u(20, 9));
      sim.expectNoNudge();
      expect(sim.deliveredCount, 0, reason: sim.dumpTimeline());
    });

    test('a block due just as waking hours begin does fire', () {
      final sim = harnessAt(20, 1)..addTask('Early start', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(20, 8, 30));

      sim.advanceTo(u(20, 9));
      sim.expectNudge();
      // The ladder legitimately runs while we advance; what matters is
      // that the block was raised once waking hours arrived at all.
      expect(
        sim.deliveredCount,
        greaterThanOrEqualTo(1),
        reason: sim.dumpTimeline(),
      );
    });
  });

  group('renegotiation', () {
    test('a block moved three times with a near deadline reaches L4', () {
      final sim = harnessAt(19, 17)
        ..addTask('Database assignment', deadline: u(20, 12), minutes: 45);
      sim.scheduleSession(
        taskId: 't1',
        start: u(19, 18),
        rescheduleCount: 3,
      );

      sim.advanceTo(u(19, 18));
      sim.expectNudge(level: InterventionLevel.l4Renegotiate);
    });

    test('refusing at the renegotiation stage makes Van concede', () {
      final sim = harnessAt(19, 17)
        ..addTask('Database assignment', deadline: u(20, 12), minutes: 45);
      sim.scheduleSession(
        taskId: 't1',
        start: u(19, 18),
        rescheduleCount: 3,
      );

      sim.advanceTo(u(19, 18));
      sim.expectNudge(level: InterventionLevel.l4Renegotiate);
      sim.userRefuses();

      sim.advanceBy(minutes: 20);
      sim.expectNudge(level: InterventionLevel.l5Concede);
    });

    test('the same block moved three times without a deadline does not', () {
      // Escalation is justified by the deadline closing in, not by the move
      // count alone. Pushing hard on undated work is just nagging.
      final sim = harnessAt(19, 17)..addTask('Someday', minutes: 45);
      sim.scheduleSession(
        taskId: 't1',
        start: u(19, 18),
        rescheduleCount: 3,
      );

      sim.advanceTo(u(19, 18));
      sim.expectNudge(level: InterventionLevel.l0Gentle);
    });
  });

  group('a full simulated week', () {
    test('produces a plausible, non-spammy volume of nudges', () {
      final sim = harnessAt(19, 8)
        ..addTask('Database assignment', deadline: u(23, 23), minutes: 240)
        ..addTask('Reading', deadline: u(24, 23), minutes: 120);
      final planned = sim.planSessions();

      expect(planned, isNotEmpty, reason: sim.dumpTimeline());
      for (final session in planned) {
        expect(session.plannedMinutes, lessThanOrEqualTo(90));
      }

      // Ignore everything for a week - the worst case for notification volume.
      sim.advanceBy(days: 7);

      // The real property is per session: ask, check, diagnose, then stop.
      // Five ignored blocks therefore cost at most fifteen interruptions
      // across a whole week, and none of them repeat.
      for (final session in planned) {
        final about = sim.timeline
            .where((l) => l.contains('NUDGE') && l.endsWith(session.id))
            .toList();
        expect(
          about.length,
          lessThanOrEqualTo(3),
          reason: 'session ${session.id} nagged too often',
        );
      }
      // The exact number is a product judgement, but the shape matters: a
      // week of total non-compliance must not produce dozens of alerts.
      expect(
        sim.deliveredCount,
        lessThanOrEqualTo(planned.length * 3),
        reason: 'too noisy over a week\n${sim.dumpTimeline()}',
      );
      expect(
        sim.deliveredCount,
        greaterThan(0),
        reason: 'silent for a whole week\n${sim.dumpTimeline()}',
      );
    });

    test('the timeline dump stays human-readable', () {
      final sim = harnessAt(19, 17)..addTask('Assignment', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 18));
      sim.advanceTo(u(19, 18));
      sim.expectNudge();
      sim.userStarts();

      final dump = sim.dumpTimeline();
      expect(dump, contains('task added: Assignment'));
      expect(dump, contains('NUDGE sessionStart l0Gentle'));
      expect(dump, contains('user STARTED s1'));
      expect(dump, contains('D19 18:00'));
    });
  });

  group('abandoned work', () {
    test('a block nobody started is moved, not lost', () {
      final sim = harnessAt(19, 8)
        ..addTask('Database assignment', deadline: u(23, 23), minutes: 45);
      final planned = sim.scheduleSession(taskId: 't1', start: u(19, 9));

      // Nudged, ignored, and then left alone: the engine gives up at 60.
      sim.advanceTo(u(19, 10, 30));
      final before = sim.deliveredCount;
      sim.advanceBy(hours: 2);
      expect(
        sim.deliveredCount,
        before,
        reason: 'the engine should have stopped asking\n${sim.dumpTimeline()}',
      );

      // Without the sweep this is where the work quietly disappears.
      final outcomes = sim.sweep();

      expect(outcomes, hasLength(1));
      expect(sim.sessions[planned.id]!.status, SessionStatus.rescheduled);
      final replacement = outcomes.single.replacement!;
      expect(replacement.plannedStart.isAfter(sim.now), isTrue);
      expect(replacement.plannedMinutes, 45);
    });

    test('the moved block gets nudged at its new time', () {
      final sim = harnessAt(19, 8)
        ..addTask('Database assignment', deadline: u(23, 23), minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 9));

      sim.advanceTo(u(19, 10, 30));
      final replacement = sim.sweep().single.replacement!;

      sim.advanceTo(replacement.plannedStart);
      sim.expectNudge(
        level: InterventionLevel.l0Gentle,
        type: NudgeType.sessionStart,
      );
      sim.userStarts();
      expect(sim.sessions[replacement.id]!.hasStarted, isTrue);
    });

    test('the sweep does not touch a conversation still in progress', () {
      final sim = harnessAt(19, 8)..addTask('Reading', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 9));

      sim.advanceTo(u(19, 9, 40));
      expect(sim.sweep(), isEmpty);
      expect(sim.sessions['s1']!.status, SessionStatus.planned);
    });

    test('work ignored all week is let go, not nagged about forever', () {
      // The failure mode this guards: sweep re-arms the ladder, user ignores
      // it again, sweep re-arms again - an accountability app that never
      // stops, which is an accountability app that gets uninstalled.
      final sim = harnessAt(19, 8)..addTask('Dreaded task', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 9));

      var opens = 0;
      while (sim.sessions.values.any((s) => !s.isResolved) && opens < 40) {
        sim.advanceBy(hours: 3);
        sim.sweep();
        opens++;
      }

      expect(
        opens,
        lessThan(40),
        reason: 'Van never stopped moving this\n${sim.dumpTimeline()}',
      );
      expect(
        sim.sessions.values.where((s) => s.status == SessionStatus.skipped),
        hasLength(1),
        reason: 'exactly one block should be the one Van gave up on',
      );
      expect(
        sim.deliveredCount,
        lessThanOrEqualTo(18),
        reason: 'too many nudges for one dodged task\n${sim.dumpTimeline()}',
      );
    });

    test('the move history survives every hop', () {
      final sim = harnessAt(19, 8)..addTask('Dreaded task', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 9));

      final chain = <String>['s1'];
      for (var hop = 0; hop < 3; hop++) {
        sim.advanceBy(hours: 3);
        final replacement = sim.sweep().single.replacement!;
        expect(replacement.parentSessionId, chain.last);
        expect(replacement.rescheduleCount, hop + 1);
        chain.add(replacement.id);
      }

      // Every hop is still on the record, none of them overwritten.
      for (final id in chain) {
        expect(sim.sessions[id], isNotNull);
      }
    });

    test('two abandoned blocks are not sent to the same slot', () {
      final sim = harnessAt(19, 8)
        ..addTask('Assignment', minutes: 45)
        ..addTask('Reading', minutes: 45);
      sim.scheduleSession(taskId: 't1', start: u(19, 9));
      sim.scheduleSession(taskId: 't2', start: u(19, 10));

      sim.advanceTo(u(19, 11, 30));
      final moved = sim
          .sweep()
          .where((o) => o.wasMoved)
          .map((o) => o.replacement!)
          .toList();

      expect(moved, hasLength(2));
      expect(
        moved[0].plannedEnd.isAfter(moved[1].plannedStart) &&
            moved[1].plannedEnd.isAfter(moved[0].plannedStart),
        isFalse,
        reason: 'double-booked by the sweep\n${sim.dumpTimeline()}',
      );
    });
  });

  group('performance', () {
    test('a simulated week runs in well under a second', () {
      final stopwatch = Stopwatch()..start();
      final sim = harnessAt(19, 8)
        ..addTask('Assignment', deadline: u(23, 23), minutes: 240);
      sim.planSessions();
      sim.advanceBy(days: 7);
      stopwatch.stop();

      // 10,080 virtual minutes, one engine tick each. If this ever creeps up,
      // tuning the weights stops being cheap and people stop doing it.
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
