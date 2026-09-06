import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

void main() {
  const rules = NegotiationRules();

  NegotiationProposal defer({int by = 30}) => NegotiationProposal(
    action: NegotiationAction.defer,
    message: 'Push it to this afternoon?',
    deferByMinutes: by,
  );

  NegotiationContext at({
    required NegotiationEvidence evidence,
    InterventionLevel level = InterventionLevel.l5Concede,
    int minutes = 60,
    double? hoursToDeadline,
  }) => NegotiationContext(
    level: level,
    currentMinutes: minutes,
    hoursToDeadline: hoursToDeadline,
    evidence: evidence,
  );

  group('when moving has stopped being an answer', () {
    test('a fourth move on work never once started is refused', () {
      // The behaviour WP_JUDGEMENT 13c exists for: "move it again" was the
      // reflex for exactly the block where the record says moving does not
      // help.
      final rejection = rules.reject(
        defer(),
        at(
          evidence: const NegotiationEvidence(moves: 4, everStarted: false),
        ),
      );

      expect(rejection, NegotiationRejection.deferAgainstEvidence);
    });

    test('the same block, once started, may still be moved', () {
      // Four moves where the work was actually begun each time is a plan
      // adapting, which is what Van is for. Moves alone are not evidence.
      expect(
        rules.reject(
          defer(),
          at(
            evidence: const NegotiationEvidence(moves: 4, everStarted: true),
          ),
        ),
        isNull,
      );
    });

    test('a first or second move is not refused', () {
      for (final moves in const [0, 1, 2]) {
        expect(
          rules.reject(
            defer(),
            at(evidence: NegotiationEvidence(moves: moves)),
          ),
          isNull,
          reason: '$moves moves',
        );
      }
    });

    test('the threshold is where Van already starts naming the pattern', () {
      // Matched to InterventionPolicy.renegotiateAfterMoves. Refusing to keep
      // moving at the same moment Van starts talking about the moving is the
      // consistent position.
      expect(
        const InterventionPolicy().renegotiateAfterMoves,
        rules.stopDeferringAfterMoves,
      );
    });

    test('shrinking and letting go stay on the table', () {
      // This narrows the answer; it does not refuse to answer. Both of the
      // honest alternatives remain.
      final evidence = const NegotiationEvidence(moves: 5, everStarted: false);

      expect(
        rules.reject(
          const NegotiationProposal(
            action: NegotiationAction.shrink,
            message: 'Twenty minutes on it?',
            shrinkToMinutes: 20,
          ),
          at(evidence: evidence),
        ),
        isNull,
      );
      expect(
        rules.reject(
          const NegotiationProposal(
            action: NegotiationAction.release,
            message: 'Let it go for today.',
          ),
          at(evidence: evidence),
        ),
        isNull,
      );
    });

    test('evidence never widens what the ladder permits', () {
      // The rule that makes letting a model near this defensible. A reading
      // of the log may take an option away; it may never add one.
      final everything = const NegotiationEvidence(
        moves: 0,
        everStarted: true,
        startsAtThisHour: 9,
        blocksAtThisHour: 9,
      );

      expect(
        rules.reject(
          const NegotiationProposal(
            action: NegotiationAction.release,
            message: 'Let it go.',
          ),
          at(evidence: everything, level: InterventionLevel.l0Gentle),
        ),
        NegotiationRejection.actionExceedsLevel,
      );
    });

    test('the size of a delay is still judged separately', () {
      // deferAgainstEvidence is about the delay being the wrong idea;
      // deferOutOfRange is about it being the wrong length. A proposal that
      // is both should report the length, which is checked first and is the
      // more specific complaint.
      expect(
        rules.reject(
          defer(by: 1),
          at(evidence: const NegotiationEvidence(moves: 9)),
        ),
        NegotiationRejection.deferOutOfRange,
      );
    });
  });

  group('what the evidence says about itself', () {
    test('an hour with too little history reports no rate at all', () {
      const thin = NegotiationEvidence(
        startsAtThisHour: 1,
        blocksAtThisHour: 2,
      );

      expect(thin.hasHourHistory, isFalse);
      expect(thin.startRateAtHour, isNull);
    });

    test('an hour with history reports the share that started', () {
      const seen = NegotiationEvidence(
        startsAtThisHour: 2,
        blocksAtThisHour: 8,
      );

      expect(seen.startRateAtHour, 0.25);
    });

    test('an unread calendar is nought dense, not unknown', () {
      // Zero of zero minutes is the honest answer, and it keeps every caller
      // from having to handle a null that means the same thing.
      expect(NegotiationEvidence.none.calendarDensity, 0);
    });

    test('a half-committed window reads as half', () {
      const busy = NegotiationEvidence(
        calendarBusyMinutes: 120,
        calendarWindowMinutes: 240,
      );

      expect(busy.calendarDensity, 0.5);
    });

    test('knowing nothing is the default, and it refuses nothing', () {
      expect(
        rules.reject(defer(), at(evidence: NegotiationEvidence.none)),
        isNull,
      );
    });
  });
}
