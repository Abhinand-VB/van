import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

void main() {
  const questions = CaptureQuestions();
  const parser = TemporalParser();

  DateTime now() => DateTime.utc(2026, 9, 6, 12);

  group('what Van asks about', () {
    test('a sentence with no duration in it leaves Van guessing', () {
      final draft = parser.parse('finish the assignment', now: now());

      expect(draft.estimatedMinutes, isNull);
      expect(
        questions.about(draft),
        const Clarification(field: TaskField.duration),
      );
    });

    test('a sentence that says how long is not asked about', () {
      final draft = parser.parse('finish the assignment, 2 hours', now: now());

      expect(draft.estimatedMinutes, 120);
      expect(questions.about(draft), isNull);
    });

    test('a deadline is not enough - the planner still has to invent one', () {
      final draft = parser.parse('finish the assignment by friday', now: now());

      expect(draft.deadline, isNotNull);
      expect(
        questions.about(draft),
        const Clarification(field: TaskField.duration),
      );
    });

    test('a missing deadline on its own is a silence Van can live with', () {
      final draft = parser.parse('email the landlord, 15 mins', now: now());

      // Work with no deadline is scheduled soon rather than wrongly. Only a
      // missing duration forces the planner to make something up, so only a
      // missing duration is worth interrupting anyone over - and asking about
      // both would be the form this rule exists to prevent.
      expect(draft.deadline, isNull);
      expect(questions.about(draft), isNull);
    });

    test('a model can ask its own question and it is carried', () {
      const asked = Clarification(
        field: TaskField.duration,
        question: 'Is this the whole assignment or the first draft?',
      );
      const draft = TaskDraft(title: 'the assignment', clarification: asked);

      expect(draft.clarification, asked);
    });
  });

  group('reading an answer', () {
    test('a stated duration is read the same way a capture would read it', () {
      expect(parser.durationIn('2 hours'), 120);
      expect(parser.durationIn('about 45 minutes'), 45);
      expect(parser.durationIn('half an hour'), 30);
      expect(parser.durationIn('an hour'), 60);
    });

    test('a bare number answering "how long" is minutes', () {
      expect(parser.durationIn('45'), 45);
      expect(parser.durationIn('  90  '), 90);
    });

    test('a bare number inside a captured sentence is still ignored', () {
      // The bare-number rule belongs to answering a question, not to reading
      // a sentence. Left in the parser proper it would start pulling digits
      // out of ordinary captures - "call flat 12" is not a twelve-minute job.
      final draft = parser.parse('call flat 12', now: now());

      expect(draft.estimatedMinutes, isNull);
    });

    test('an answer with no length in it is not guessed at', () {
      expect(parser.durationIn('dunno'), isNull);
      expect(parser.durationIn(''), isNull);
      expect(parser.durationIn('as long as it takes'), isNull);
    });
  });
}
