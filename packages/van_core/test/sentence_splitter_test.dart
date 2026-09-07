import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

void main() {
  const splitter = SentenceSplitter();

  group('the sentence this was built for', () {
    test('three jobs come out of it, where one used to', () {
      const said =
          'Go to the shop take a stroll cook lunch and do my remaining works '
          'also I need to do taxes';

      expect(splitter.split(said), [
        'Go to the shop take a stroll cook lunch',
        'do my remaining works',
        'I need to do taxes',
      ]);
    });

    test('and it is honest that three is not five', () {
      // "go to the shop take a stroll cook lunch" has no separator in it at
      // all. Cutting it would mean cutting on bare verbs, which is exactly
      // what turns "call the bank and ask about the mortgage" into two tasks.
      // Three beats one; five is not worth that.
      const said = 'Go to the shop take a stroll cook lunch';

      expect(splitter.split(said), hasLength(1));
    });
  });

  group('what it must not split', () {
    test('one instruction with a subordinate clause', () {
      for (final said in const [
        'Call the bank and ask about the mortgage',
        'Email the landlord and mention the boiler',
        // "it" is the report. A pronoun pointing back at the last clause is
        // what tells a perfectly good verb list that this is a continuation.
        'Write the report and send it to Priya',
        'Book the flight and pay for it later',
      ]) {
        expect(splitter.split(said), [said], reason: said);
      }
    });

    test('an "and" between two nouns', () {
      expect(splitter.split('Buy milk and bread'), ['Buy milk and bread']);
      expect(
        splitter.split('Review the plan and the budget'),
        ['Review the plan and the budget'],
      );
    });

    test('a conjunction that joins rather than starts', () {
      // "but", "because" and "so" attach a clause to the one before it. Pay
      // the bill so I can cancel the card is one thing.
      for (final said in const [
        'Pay the bill so I can cancel the card',
        'Call the dentist but not before ten',
        'Finish the draft because it is due friday',
      ]) {
        expect(splitter.split(said), [said], reason: said);
      }
    });

    test('an ordinary single task', () {
      expect(
        splitter.split('finish the assignment by friday, 2 hours'),
        ['finish the assignment by friday, 2 hours'],
      );
    });
  });

  group('what it does split', () {
    test('two instructions joined by and', () {
      expect(splitter.split('email the landlord and pay the gas bill'), [
        'email the landlord',
        'pay the gas bill',
      ]);
    });

    test('then, also, and plus', () {
      expect(splitter.split('book the dentist then call mum'), [
        'book the dentist',
        'call mum',
      ]);
      expect(splitter.split('tidy the desk also submit the form'), [
        'tidy the desk',
        'submit the form',
      ]);
      expect(splitter.split('print the tickets plus pack the bag'), [
        'print the tickets',
        'pack the bag',
      ]);
    });

    test('"and then" and "and also" are one separator, not two', () {
      expect(splitter.split('write the report and then call the bank'), [
        'write the report',
        'call the bank',
      ]);
    });

    test('a newline needs no verb test at all', () {
      // Somebody who pressed return meant two things. That is not a guess.
      expect(splitter.split('milk and bread\nthe thing about the car'), [
        'milk and bread',
        'the thing about the car',
      ]);
    });

    test('"I need to" starts a job even though it is not a verb', () {
      expect(splitter.split('pay the bill also I have to do taxes'), [
        'pay the bill',
        'I have to do taxes',
      ]);
    });

    test('three jobs in a row', () {
      expect(
        splitter.split('call the bank and email the landlord and pay the rent'),
        ['call the bank', 'email the landlord', 'pay the rent'],
      );
    });
  });

  group('edges', () {
    test('nothing typed is nothing captured', () {
      expect(splitter.split(''), isEmpty);
      expect(splitter.split('   '), isEmpty);
    });

    test('a trailing separator is not a boundary', () {
      expect(splitter.split('call the bank and'), ['call the bank and']);
    });

    test('a leading separator is not a boundary either', () {
      expect(splitter.split('and call the bank'), ['and call the bank']);
    });

    test('a clause is never empty and never loses its words', () {
      const said = 'email the landlord and pay the gas bill';
      final parts = splitter.split(said);

      expect(parts.every((p) => p.trim().isNotEmpty), isTrue);
      // Every word survives somewhere, minus the separator itself.
      expect(parts.join(' ').split(' ').length, said.split(' ').length - 1);
    });
  });
}
