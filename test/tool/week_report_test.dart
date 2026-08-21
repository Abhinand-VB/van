import 'package:flutter_test/flutter_test.dart';
import 'package:van_core/van_core.dart';

import '../../tool/week_report.dart';

/// A review with everything at zero, so each test can say what it changes.
WeekReview review({
  int blocksPlanned = 0,
  int blocksStarted = 0,
  int nudgeScheduleFailures = 0,
  Map<String, int> suppressedByReason = const {},
  Map<String, int> missedByReason = const {},
}) => WeekReview(
  tasksCaptured: 0,
  blocksPlanned: blocksPlanned,
  blocksStarted: blocksStarted,
  blocksCompleted: 0,
  blocksPartial: 0,
  blocksMissed: 0,
  missedByReason: missedByReason,
  reschedulesByReason: const {},
  movedThenMissedAgain: 0,
  nudgesScheduled: 0,
  nudgesDelivered: 0,
  nudgesSuppressed: 0,
  suppressedByReason: suppressedByReason,
  nudgeScheduleFailures: nudgeScheduleFailures,
  responsesByType: const {},
  proposalsByAction: const {},
  proposalsFromModel: 0,
  proposalsRefused: 0,
  from: DateTime.utc(2026, 8, 17),
  to: DateTime.utc(2026, 8, 21),
);

void main() {
  group('the report', () {
    test('spans the dates it actually covers', () {
      expect(render(review(), 10), contains('2026-08-17 to 2026-08-21'));
    });

    test('prints a rate only when there is a denominator', () {
      expect(
        render(review(), 1),
        isNot(contains('%')),
        reason: 'a rate over no blocks would read as a week of total failure',
      );
      expect(
        render(review(blocksPlanned: 4, blocksStarted: 1), 1),
        contains('25% of planned'),
      );
    });

    test('an empty group says none rather than printing nothing', () {
      // A heading with no lines under it reads like the report broke, and
      // "no suppressions" versus "the report broke" is exactly the difference
      // someone tuning a limit needs to be sure of.
      expect(render(review(), 1), contains('none'));
    });

    test('a populated group is listed and sorted', () {
      final text = render(
        review(suppressedByReason: const {'tooSoonAfterLast': 2, 'dnd': 1}),
        1,
      );

      expect(text, contains('dnd'));
      expect(text, contains('tooSoonAfterLast'));
      expect(
        text.indexOf('dnd'),
        lessThan(text.indexOf('tooSoonAfterLast')),
        reason: 'sorted, so two runs can be diffed against each other',
      );
    });

    test('never presents the answered count as a delivery count', () {
      // Van cannot observe a notification appearing; nudgeDelivered is only
      // written when a rung is answered. Printing it as "delivered" next to
      // "scheduled" invites exactly the wrong conclusion - that nudges are
      // not arriving - when it may only mean nobody replied to them.
      final text = render(review(), 1);

      expect(text, isNot(contains('delivered  ')));
      expect(text, contains('answered'));
      expect(text, contains('is not a delivery count'));
    });

    test('platform refusals are called out, and only when there are any', () {
      expect(render(review(), 1), isNot(contains('REFUSED')));
      expect(
        render(review(nudgeScheduleFailures: 3), 1),
        contains('REFUSED BY ANDROID 3'),
      );
    });
  });
}
