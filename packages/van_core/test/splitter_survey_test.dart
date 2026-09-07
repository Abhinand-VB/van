import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

/// What the splitter actually does to sentences a person would plausibly type.
///
/// **This exists because D83 claimed something that turned out to be too
/// strong.** It said over-splitting was avoided by requiring the clause after
/// a separator to "stand on its own as an instruction". Surveying fifty real
/// sentences showed that test is much weaker than it sounds: nearly every
/// English second clause opens with a verb and so stands alone grammatically,
/// including the ones that are plainly a *step* of the errand already given.
/// "Go to the shop and get bread" is one job by any reading, and was being cut
/// in two.
///
/// So this file pins the behaviour rather than asserting an ideal. Each
/// sentence is listed with the number of tasks it should produce, and the
/// cases still known to be wrong are named in `stillWrong`. That is
/// deliberately uncomfortable to read, which is the point: a list of failures
/// nobody can see is a list nobody fixes, and the only alternative was to
/// leave D83's claim standing.
///
/// See `DECISIONS_PENDING.md` D87.
void main() {
  const splitter = SentenceSplitter();

  /// Sentences that must come back whole, mostly for a stated reason.
  const oneJob = <String>[
    // "and" joining two nouns, not two jobs.
    'buy milk and eggs',
    'clean the kitchen and the bathroom',
    'ring mum and dad',
    'book the flights and hotels for the trip',
    'pick up the parcel and the dry cleaning',
    'sort out the shed and garden',
    'milk, bread and eggs',
    // A pronoun pointing back at the last clause.
    'write up the notes and send them round',
    'check the boiler and get it serviced',
    'find the receipt and take it back to the shop',
    'read the contract and sign it',
    'back up the laptop and then wipe it',
    'take the car in and wait for it',
    'draft the email 20 minutes then send it',
    'clean the car and make it shine',
    'pick a film and watch it with Sam',
    'book a table and make sure they know about the allergy',
    // The canonical counter-example, and its family.
    'call the school tomorrow and ask about the trip',
    'go to the bank and then the post office',
    // Verbs of obtaining and travelling, which name a step rather than a job.
    // These are what D87 fixed, by taking "get" and "go" out of the starters.
    'go to the shop and get bread',
    'ring the surgery and get an appointment',
    'wake up early and get the train',
    'get the tickets and go to the show',
    // A second clause whose verb is simply not known. Under-splitting, which
    // is the accepted direction to fail in.
    'finish the slides and practise the talk',
    'remember to cancel the subscription and to move the money',
    // A conjunction that joins rather than starts.
    'pay the bill so I can cancel the card',
    // Shapes with nowhere to cut.
    'finish the tax return by the 31st 2 hours',
    'and then the thing with the car',
    'plan the week and',
    'do it',
  ];

  /// Sentences that really are two jobs, and must be cut.
  const twoJobs = <String>[
    'pay the electricity bill and book the dentist',
    'renew the passport and call the garage',
    'submit the expenses then email Sarah',
    'water the plants also take the bins out',
    'do the washing up and put a wash on',
    'tidy the desk and start the report by friday',
    'cook dinner and do the dishes',
    'drop the parcel off and collect the post',
    'pay the rent and cancel the gym',
    'wash the car and book the service',
    'I need to book the MOT and I have to chase the invoice',
    "I've got to pick up the kids and make dinner",
  ];

  /// Sentences the splitter still gets wrong, named rather than hidden.
  ///
  /// Every one is a second clause that is a *step* of the first, opening with
  /// a verb that also opens plenty of genuine second jobs — "make an album"
  /// against "make dinner", "do the survey" against "do the dishes", "start
  /// the report" against "start the report by friday". There is no lexical
  /// signal separating them: the difference is what the person meant, and a
  /// word list cannot reach it.
  const stillWrong = <String>[
    'call the plumber and fix the date',
    'open the laptop and start the report',
    'log in and do the survey',
    'drive to the tip and drop off the old chairs',
    'sort the photos and make an album',
    'take the bins out and put the recycling in the blue bin',
    'unpack the boxes and put the books away',
    'find a recipe and cook something new',
  ];

  group('sentences that are one job', () {
    for (final sentence in oneJob) {
      test('"$sentence"', () {
        expect(splitter.split(sentence), hasLength(1), reason: sentence);
      });
    }
  });

  group('sentences that are two', () {
    for (final sentence in twoJobs) {
      test('"$sentence"', () {
        expect(splitter.split(sentence), hasLength(2), reason: sentence);
      });
    }
  });

  group('sentences it still gets wrong', () {
    for (final sentence in stillWrong) {
      test('"$sentence" is cut when it should not be', () {
        // Written the wrong way round on purpose. If a future change makes
        // one of these right, this test fails and somebody moves the line up
        // into the oneJob list — which is the whole mechanism.
        expect(
          splitter.split(sentence),
          hasLength(2),
          reason:
              'a known over-split; if it now returns one, move it to oneJob '
              'and delete it from here',
        );
      });
    }
  });

  group('what the survey is for', () {
    test('the founding sentence is untouched by any of this', () {
      const said =
          'Go to the shop take a stroll cook lunch and do my remaining works '
          'also I need to do taxes';

      expect(splitter.split(said), hasLength(3));
    });

    test('over-splitting is rarer than getting it right, measured', () {
      // The direction of failure D83 chose, restated as a measurement rather
      // than an intention.
      final wrong = stillWrong.length;
      final right = oneJob.length + twoJobs.length;

      expect(wrong * 4, lessThan(right));
    });
  });
}
