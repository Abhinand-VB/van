import 'package:meta/meta.dart';
import 'package:van_core/src/text/depth_reader.dart';

/// Cuts one typed sentence into the separate jobs it actually contains.
///
/// **The problem this exists for, in the owner's own words:** *"Go to the shop
/// take a stroll cook lunch and do my remaining works also I need to do
/// taxes"*. Van made one task with a 25-word title. So did the on-device
/// model, except it kept only the first four words and threw the rest away.
/// Neither could do better, because `ExtractTask` returns one `TaskDraft` and
/// a `TaskDraft` is one task - the contract was the whole bug.
///
/// **Over-splitting is much worse than under-splitting**, and the rule is
/// built around that. Under-splitting leaves today's behaviour, which is a
/// known and visible cost. Over-splitting invents work the user never asked
/// for, in a log that never deletes, and it does so silently. So a cut is only
/// made where two things are both true: there is an explicit separator, *and*
/// what follows it can stand on its own as an instruction.
///
/// That is deliberately conservative and it does not get everything. The
/// sentence above splits into three, not five: "go to the shop take a stroll
/// cook lunch" has no separator in it at all, and finding the boundaries
/// inside it would mean cutting on bare verbs - which is exactly what turns
/// "call the bank and ask about the mortgage" into two tasks. Three beats one;
/// five is not worth that risk. See `DECISIONS_PENDING.md` D83.
@immutable
class SentenceSplitter {
  /// Creates a splitter.
  const SentenceSplitter();

  /// Words that mark a boundary between two jobs.
  ///
  /// Ordinary conjunctions only. "but", "because" and "so" are deliberately
  /// absent: they join a clause to the one before it rather than starting a
  /// new errand, and "pay the bill so I can cancel the card" is one thing.
  static final _separator = RegExp(
    r'\s+(?:and\s+also|and\s+then|and|also|then|plus)\s+',
    caseSensitive: false,
  );

  /// Verbs that begin an instruction but are too ordinary for the depth
  /// reader's lists.
  ///
  /// Only ever consulted *after* a separator has already been found, which is
  /// what makes them safe. On their own they are far too common to cut on -
  /// "take" appears in the middle of half of all sentences - but "… and take
  /// the bins out" is a second job by any reading.
  ///
  /// **"get" and "go" were here and had to come out**, on the evidence in
  /// `splitter_survey_test.dart`. They are verbs of *obtaining* and *travelling*
  /// rather than of doing, and in a second clause they almost always name a
  /// step of the errand already given: "go to the shop and get bread", "ring
  /// the surgery and get an appointment", "wake up early and get the train",
  /// "get the tickets and go to the show". Every one of those was cut in two
  /// and none of them is two jobs. Nothing in the survey needed either word to
  /// split correctly, so this costs nothing that was measured and fixes four
  /// things that were. See `DECISIONS_PENDING.md` D87.
  static const _commonStarters = <String>{
    'archive',
    'bring',
    'collect',
    'cook',
    'do',
    'drop',
    'finish',
    'fix',
    'hand',
    'make',
    'pack',
    'pick',
    'put',
    'read',
    'sell',
    'sort',
    'start',
    'take',
    'wash',
    'watch',
  };

  /// A clause that points back at the last one is a continuation.
  ///
  /// "Write the report and send **it** to Priya" is one job: the pronoun is
  /// the report. So is "book the flight and pay for **it** later", which is
  /// why the pronoun is looked for in the first two or three words rather
  /// than only immediately after the verb - a preposition often sits between.
  ///
  /// Only pronouns that are never determiners. "that" and "this" were in this
  /// list and had to come out: "pay **that** bill" is a new job and they were
  /// blocking it.
  ///
  /// This is what stops a perfectly good verb list from cutting a sentence in
  /// half at the word that finishes it.
  static final _refersBack = RegExp(
    r"^(?:[a-z']+\s+){1,2}(?:it|them|they|him|her|us)\b",
    caseSensitive: false,
  );

  /// "I need to …", and the handful of ways people write the same thing.
  ///
  /// Not a verb, but unmistakably the start of a new job - it is how the
  /// owner's own sentence introduced its last one.
  static final _firstPerson = RegExp(
    r"^i(?:'ve|\s+have)?\s+(?:need|have|want|should|must|got)\s+to\s+\S",
    caseSensitive: false,
  );

  /// Splits [text] into one or more jobs, in the order they were written.
  ///
  /// Never returns an empty list, and never returns an empty clause: a
  /// sentence that cannot be split is one job, which is the common case and
  /// must stay cheap.
  List<String> split(String text) {
    final whole = text.trim();
    if (whole.isEmpty) return const [];

    // Newlines are a separator on their own and need no verb test. Somebody
    // who pressed return meant two things; that is not a guess.
    final lines = whole
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    final parts = <String>[];
    for (final line in lines) {
      parts.addAll(_splitLine(line));
    }
    return parts.isEmpty ? [whole] : parts;
  }

  /// Walks the separators in [line], cutting only at the ones that earn it.
  ///
  /// A separator that fails the test is *skipped*, not treated as the end of
  /// the clause - "call the bank and ask about the mortgage" has to come back
  /// as one string with its "and" still in it.
  List<String> _splitLine(String line) {
    final parts = <String>[];
    var start = 0;

    for (final match in _separator.allMatches(line)) {
      // A separator inside the part already consumed is not a boundary here.
      if (match.start < start) continue;

      final clause = line.substring(start, match.start).trim();
      final rest = line.substring(match.end).trim();
      if (clause.isEmpty || rest.isEmpty || !_standsAlone(rest)) continue;

      parts.add(clause);
      start = match.end;
    }

    final tail = line.substring(start).trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  /// Whether [clause] reads as an instruction in its own right.
  bool _standsAlone(String clause) {
    if (_firstPerson.hasMatch(clause)) return true;
    if (_refersBack.hasMatch(clause)) return false;
    final first = RegExp(
      '^[a-zA-Z]+',
    ).firstMatch(clause)?.group(0)?.toLowerCase();
    if (first == null) return false;
    return DepthReader.isKnownVerb(first) || _commonStarters.contains(first);
  }
}
