import 'package:van_core/van_core.dart';
import 'package:test/test.dart';

NegotiationProposal proposal(
  NegotiationAction action, {
  String message = 'Twenty minutes on it?',
  int? shrinkTo,
  int? deferBy,
}) => NegotiationProposal(
  action: action,
  message: message,
  shrinkToMinutes: shrinkTo,
  deferByMinutes: deferBy,
);

NegotiationContext context({
  InterventionLevel level = InterventionLevel.l5Concede,
  int minutes = 60,
  double? hoursToDeadline,
}) => NegotiationContext(
  level: level,
  currentMinutes: minutes,
  hoursToDeadline: hoursToDeadline,
);

void main() {
  const rules = NegotiationRules();

  group('what each level may offer', () {
    test('an early prompt may only ask again', () {
      for (final level in [
        InterventionLevel.l0Gentle,
        InterventionLevel.l1Check,
        InterventionLevel.l2Diagnose,
      ]) {
        expect(
          rules.allowedAt(level),
          {NegotiationAction.hold},
          reason: '${level.name} has not earned the right to give ground',
        );
      }
    });

    test('the shrink levels may offer something smaller, nothing more', () {
      for (final level in [
        InterventionLevel.l3Shrink,
        InterventionLevel.l4Renegotiate,
      ]) {
        expect(rules.allowedAt(level), {
          NegotiationAction.hold,
          NegotiationAction.shrink,
        });
      }
    });

    test('only conceding may let a block go', () {
      expect(
        rules.allowedAt(InterventionLevel.l5Concede),
        containsAll(NegotiationAction.values),
      );
      for (final level in InterventionLevel.values) {
        if (level == InterventionLevel.l5Concede) continue;
        expect(
          rules.allowedAt(level),
          isNot(contains(NegotiationAction.release)),
          reason: '${level.name} must not be able to cancel work',
        );
      }
    });
  });

  group('refusing a proposal', () {
    test('a permitted hold passes', () {
      expect(
        rules.reject(
          proposal(NegotiationAction.hold),
          context(level: InterventionLevel.l0Gentle),
        ),
        isNull,
      );
    });

    test('an action above the level is refused', () {
      // The case that matters if negotiate is ever routed to a cloud model:
      // a gentle first prompt must not be able to cancel the afternoon.
      expect(
        rules.reject(
          proposal(NegotiationAction.release),
          context(level: InterventionLevel.l0Gentle),
        ),
        NegotiationRejection.actionExceedsLevel,
      );
    });

    test('an empty message is refused however sound the action', () {
      expect(
        rules.reject(
          proposal(NegotiationAction.hold, message: '   '),
          context(),
        ),
        NegotiationRejection.emptyMessage,
      );
    });

    test('a message too long for a notification is refused', () {
      expect(
        rules.reject(
          proposal(NegotiationAction.hold, message: 'x' * 201),
          context(),
        ),
        NegotiationRejection.emptyMessage,
      );
    });

    group('shrink', () {
      test('a smaller block passes', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.shrink, shrinkTo: 30),
            context(minutes: 60),
          ),
          isNull,
        );
      });

      test('a shrink with no size is refused', () {
        expect(
          rules.reject(proposal(NegotiationAction.shrink), context()),
          NegotiationRejection.missingAmount,
        );
      });

      test('a shrink that is not smaller is refused', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.shrink, shrinkTo: 60),
            context(minutes: 60),
          ),
          NegotiationRejection.shrinkOutOfRange,
        );
        expect(
          rules.reject(
            proposal(NegotiationAction.shrink, shrinkTo: 90),
            context(minutes: 60),
          ),
          NegotiationRejection.shrinkOutOfRange,
        );
      });

      test('a shrink below the floor is refused', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.shrink, shrinkTo: 5),
            context(minutes: 60),
          ),
          NegotiationRejection.shrinkOutOfRange,
        );
      });
    });

    group('defer', () {
      test('a sensible delay passes', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.defer, deferBy: 60),
            context(),
          ),
          isNull,
        );
      });

      test('a delay with no amount is refused', () {
        expect(
          rules.reject(proposal(NegotiationAction.defer), context()),
          NegotiationRejection.missingAmount,
        );
      });

      test('an instant delay is refused', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.defer, deferBy: 1),
            context(),
          ),
          NegotiationRejection.deferOutOfRange,
        );
      });

      test('a delay long enough to be a quiet cancellation is refused', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.defer, deferBy: 60 * 24),
            context(),
          ),
          NegotiationRejection.deferOutOfRange,
        );
      });

      test('a delay past the deadline is refused', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.defer, deferBy: 180),
            context(hoursToDeadline: 2),
          ),
          NegotiationRejection.deferPastDeadline,
        );
      });

      test('a delay that still beats the deadline passes', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.defer, deferBy: 60),
            context(hoursToDeadline: 2),
          ),
          isNull,
        );
      });

      test('no deadline means nothing to be late for', () {
        expect(
          rules.reject(
            proposal(NegotiationAction.defer, deferBy: 400),
            context(),
          ),
          isNull,
        );
      });
    });

    test('permits agrees with reject', () {
      final good = proposal(NegotiationAction.hold);
      final bad = proposal(NegotiationAction.release);
      final gentle = context(level: InterventionLevel.l0Gentle);

      expect(rules.permits(good, gentle), isTrue);
      expect(rules.permits(bad, gentle), isFalse);
    });
  });
}
