import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

void main() {
  const reader = SpokenAnswerReader();

  SpokenIntent intentOf(String said) => reader.read(said).intent;

  group('the three things a nudge can be answered with', () {
    test('starting', () {
      for (final said in const [
        "I've started",
        'starting now',
        'on it',
        'doing it now',
        'yes',
      ]) {
        expect(intentOf(said), SpokenIntent.start, reason: said);
      }
    });

    test('not today', () {
      for (final said in const [
        'not today',
        'tomorrow',
        'skip it',
        'another day',
        'forget it',
      ]) {
        expect(intentOf(said), SpokenIntent.notToday, reason: said);
      }
    });

    test('later, with a length', () {
      expect(
        reader.read('in an hour'),
        const SpokenAnswer(
          SpokenIntent.snooze,
          minutes: 60,
        ),
      );
      expect(
        reader.read('give me twenty minutes'),
        const SpokenAnswer(
          SpokenIntent.snooze,
          minutes: 20,
        ),
      );
      expect(
        reader.read('in 45 mins'),
        const SpokenAnswer(
          SpokenIntent.snooze,
          minutes: 45,
        ),
      );
      expect(
        reader.read('half an hour'),
        const SpokenAnswer(
          SpokenIntent.snooze,
          minutes: 30,
        ),
      );
    });

    test('later, without one', () {
      // No number said, so none is invented - the caller's own default is a
      // better answer than a figure made up here.
      expect(reader.read('later'), const SpokenAnswer(SpokenIntent.snooze));
      expect(reader.read('in a bit').minutes, isNull);
    });
  });

  group('the orderings that matter', () {
    test('"not right now" is a snooze, not a refusal', () {
      // It contains "not", and the whole point of testing the day-sized
      // answer first is that "not today" and "not right now" are opposite
      // amounts of no.
      expect(intentOf('not right now'), SpokenIntent.snooze);
      expect(intentOf('not today'), SpokenIntent.notToday);
    });

    test('"tomorrow" outranks a duration in the same sentence', () {
      // "tomorrow, give me an hour" is not an hour.
      expect(intentOf('tomorrow, give me an hour'), SpokenIntent.notToday);
    });

    test('having started outranks a duration', () {
      // "I've started, twenty minutes in" must not become a snooze.
      expect(intentOf("I've started, twenty minutes in"), SpokenIntent.start);
    });
  });

  group('when Van cannot tell', () {
    test('it says so rather than picking', () {
      // Applying the wrong action moves work the user did not agree to move,
      // in a log that never deletes. Silence is the cheaper mistake.
      for (final said in const [
        'the dog ate it',
        'mmm',
        '',
        '   ',
        'what',
        'I need to talk to Priya about it first',
      ]) {
        expect(intentOf(said), SpokenIntent.unclear, reason: '"$said"');
      }
    });

    test('a bare number in a sentence is not minutes', () {
      // "give me 5" is probably five minutes and might be five of anything;
      // "in 2018" is certainly not. Only a stated unit counts.
      expect(intentOf('in 2018 I would have'), SpokenIntent.unclear);
    });

    test('but a bare duration on its own is a snooze', () {
      // Answering "are you starting?" with "twenty minutes" cannot mean
      // anything else.
      expect(
        reader.read('20 minutes'),
        const SpokenAnswer(
          SpokenIntent.snooze,
          minutes: 20,
        ),
      );
    });
  });
}
