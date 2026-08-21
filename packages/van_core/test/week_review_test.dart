import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 17, 9);

  VanEvent ev(
    EventType type,
    Map<String, Object?> payload, {
    int minutes = 0,
  }) => VanEvent(
    type: type,
    timestamp: t0.add(Duration(minutes: minutes)),
    payload: payload,
  );

  group('an empty log', () {
    test('is empty, and says so rather than reporting zeroes as facts', () {
      final review = WeekReview.from(const <VanEvent>[]);

      expect(review.isEmpty, isTrue);
      expect(review.from, isNull);
      expect(review.to, isNull);
      expect(
        review.startRate,
        isNull,
        reason: 'no blocks is a question with no answer, not a 0% week',
      );
      expect(review.completionRate, isNull);
    });
  });

  group('counting a week', () {
    final events = [
      ev(EventType.taskCreated, {'taskId': 't1', 'title': 'Write'}),
      ev(EventType.sessionPlanned, {
        'sessionId': 's1',
        'taskId': 't1',
      }, minutes: 1),
      ev(EventType.sessionPlanned, {
        'sessionId': 's2',
        'taskId': 't1',
      }, minutes: 2),
      ev(EventType.nudgeScheduled, {'sessionId': 's1'}, minutes: 3),
      ev(EventType.nudgeSuppressed, {
        'sessionId': 's2',
        'reason': 'dismissalLimit',
      }, minutes: 4),
      ev(EventType.nudgeDelivered, {'sessionId': 's1'}, minutes: 5),
      ev(EventType.nudgeResponded, {
        'sessionId': 's1',
        'response': 'started',
      }, minutes: 6),
      ev(EventType.sessionStarted, {'sessionId': 's1'}, minutes: 7),
      ev(EventType.sessionCompleted, {'sessionId': 's1'}, minutes: 8),
      ev(EventType.sessionMissed, {
        'sessionId': 's2',
        'reason': 'stale',
      }, minutes: 9),
      ev(EventType.rescheduleApplied, {
        'from': 's2',
        'to': 's3',
        'reason': 'sweep',
      }, minutes: 10),
    ];

    test('the basic tallies', () {
      final review = WeekReview.from(events);

      expect(review.tasksCaptured, 1);
      expect(review.blocksPlanned, 2);
      expect(review.blocksStarted, 1);
      expect(review.blocksCompleted, 1);
      expect(review.blocksMissed, 1);
      expect(review.nudgesScheduled, 1);
      expect(review.nudgesDelivered, 1);
      expect(review.nudgesSuppressed, 1);
      expect(review.isEmpty, isFalse);
    });

    test('rates are fractions of the right denominator', () {
      final review = WeekReview.from(events);

      expect(review.startRate, 0.5, reason: '1 of 2 planned');
      expect(review.completionRate, 1.0, reason: '1 of 1 started');
    });

    test('reasons are grouped, not just totalled', () {
      final review = WeekReview.from(events);

      expect(review.missedByReason, {'stale': 1});
      expect(review.reschedulesByReason, {'sweep': 1});
      expect(review.suppressedByReason, {'dismissalLimit': 1});
      expect(review.responsesByType, {'started': 1});
    });

    test('the window spans the first and last event', () {
      final review = WeekReview.from(events);

      expect(review.from, t0);
      expect(review.to, t0.add(const Duration(minutes: 10)));
    });

    test('order does not matter', () {
      final forwards = WeekReview.from(events);
      final backwards = WeekReview.from(events.reversed);

      expect(backwards.blocksPlanned, forwards.blocksPlanned);
      expect(backwards.from, forwards.from);
      expect(backwards.to, forwards.to);
      expect(backwards.missedByReason, forwards.missedByReason);
    });
  });

  group('moved, then missed again', () {
    test('counts a replacement that was itself missed', () {
      // The number that says rescheduling is not working: Van moved the work
      // and the move did not help.
      final review = WeekReview.from([
        ev(EventType.sessionMissed, {'sessionId': 's1', 'reason': 'stale'}),
        ev(EventType.rescheduleApplied, {
          'from': 's1',
          'to': 's2',
          'reason': 'sweep',
        }, minutes: 1),
        ev(EventType.sessionMissed, {
          'sessionId': 's2',
          'reason': 'stale',
        }, minutes: 2),
      ]);

      expect(review.movedThenMissedAgain, 1);
      expect(review.blocksMissed, 2);
    });

    test('does not count the original, only the replacement', () {
      final review = WeekReview.from([
        ev(EventType.sessionMissed, {'sessionId': 's1', 'reason': 'stale'}),
        ev(EventType.rescheduleApplied, {
          'from': 's1',
          'to': 's2',
          'reason': 'sweep',
        }, minutes: 1),
      ]);

      expect(review.movedThenMissedAgain, 0, reason: 's2 was never missed');
    });

    test('works when the miss is recorded before the move', () {
      // The sweep writes sessionMissed and then rescheduleApplied, so this is
      // the real ordering, not a contrived one.
      final review = WeekReview.from([
        ev(EventType.sessionMissed, {
          'sessionId': 's2',
          'reason': 'stale',
        }, minutes: 5),
        ev(EventType.rescheduleApplied, {
          'from': 's1',
          'to': 's2',
          'reason': 'sweep',
        }),
      ]);

      expect(review.movedThenMissedAgain, 1);
    });
  });

  group('negotiation', () {
    test('proposals are grouped by action, source and refusal', () {
      final review = WeekReview.from([
        ev(EventType.interventionSelected, {
          'action': 'shrink',
          'source': 'fallback',
        }),
        ev(EventType.interventionSelected, {
          'action': 'shrink',
          'source': 'model',
        }, minutes: 1),
        ev(EventType.interventionSelected, {
          'action': 'hold',
          'source': 'fallback',
          'refused': 'actionExceedsLevel',
        }, minutes: 2),
      ]);

      expect(review.proposalsByAction, {'shrink': 2, 'hold': 1});
      expect(review.proposalsFromModel, 1);
      expect(review.proposalsRefused, 1);
    });
  });

  group('a payload missing the field it should have', () {
    test('is counted in the total but not in any group', () {
      // The log is historical and append-only: a row written by an older
      // build may simply not have the key. That must not take the tally with
      // it, and it must not invent a bucket either.
      final review = WeekReview.from([
        ev(EventType.sessionMissed, {'sessionId': 's1'}),
        ev(EventType.nudgeSuppressed, {'sessionId': 's1'}, minutes: 1),
      ]);

      expect(review.blocksMissed, 1);
      expect(review.missedByReason, isEmpty);
      expect(review.nudgesSuppressed, 1);
      expect(review.suppressedByReason, isEmpty);
    });
  });
}
