import 'package:meta/meta.dart';
import 'package:van_core/src/text/temporal_parser.dart';

/// What a person said back to a nudge.
///
/// Exactly the three things the notification's own buttons do, plus the
/// admission that Van did not follow. **The action space is closed on purpose
/// and is not the place to be clever**: applying the wrong one moves work the
/// user did not agree to move, in a log that never deletes.
enum SpokenIntent {
  /// They are starting now. Same as pressing START.
  start,

  /// Later, by some amount. Same as pressing Snooze.
  snooze,

  /// Not today at all. Same as pressing Not today.
  notToday,

  /// Van could not tell. **Ask; do not pick.**
  unclear,
}

/// A nudge answer, read off what was said.
@immutable
class SpokenAnswer {
  /// Creates an answer.
  const SpokenAnswer(this.intent, {this.minutes});

  /// Van did not follow it.
  static const unclear = SpokenAnswer(SpokenIntent.unclear);

  /// What they meant.
  final SpokenIntent intent;

  /// How long to put it off, for [SpokenIntent.snooze]. Null means "no
  /// number was said", and the caller uses its own default.
  final int? minutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpokenAnswer &&
          intent == other.intent &&
          minutes == other.minutes;

  @override
  int get hashCode => Object.hash(intent, minutes);

  @override
  String toString() => 'SpokenAnswer(${intent.name}, $minutes)';
}

/// Reads a spoken reply to a nudge as one of the actions Van already has.
///
/// **Deterministic, and that is enough here.** "not today", "in an hour",
/// "I've started" is a handful of phrasings over a space of three, which is
/// the opposite of the open-ended reading `extract_task` does. A model would
/// improve the wording of what Van says back; it would not improve this.
///
/// The [TemporalParser] does the arithmetic, so "in twenty minutes" and "20
/// mins" resolve the same way a typed deadline would, and there is one place
/// in the app that knows how long "an hour" is.
///
/// Pure, and separate from the recogniser: this reads strings, and where the
/// string came from is not its business. That is what lets the whole thing be
/// tested without a microphone.
@immutable
class SpokenAnswerReader {
  /// Creates the reader.
  const SpokenAnswerReader({TemporalParser parser = const TemporalParser()})
    : _parser = parser;

  final TemporalParser _parser;

  /// Said before anything else and taken to mean "not today", because a day
  /// is the unit these all name.
  static final _notToday = RegExp(
    r'\b(not today|tomorrow|another day|next week|skip( it| this)?|'
    r'forget it|drop it|cancel( it)?|no+t? now)\b',
  );

  /// "Starting" beats "later" when both appear: someone who says they have
  /// started has said the one thing Van most wants to hear.
  static final _start = RegExp(
    r"\b(start(ing|ed)?|i'?m on it|on it|doing it( now)?|"
    r"i have started|i've started|going now|yes)\b",
  );

  static final _later = RegExp(
    r'\b(later|in a (bit|minute|moment)|snooze|hold on|give me|'
    r'not (yet|right now)|soon|after)\b',
  );

  /// Reads [text]. Returns [SpokenAnswer.unclear] rather than guessing.
  SpokenAnswer read(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return SpokenAnswer.unclear;

    // Order is the rule and it is not alphabetical. "not today" contains
    // "not", and "not right now" is a snooze rather than a refusal, so the
    // day-sized answer is tested first and the near-term one second.
    if (_notToday.hasMatch(lower)) {
      return const SpokenAnswer(SpokenIntent.notToday);
    }
    if (_start.hasMatch(lower)) return const SpokenAnswer(SpokenIntent.start);

    // A bare duration is a snooze: "twenty minutes" answering "are you
    // starting?" cannot mean anything else.
    final minutes = _parser.durationIn(lower) ?? _minutesIn(lower);
    if (minutes != null) {
      return SpokenAnswer(SpokenIntent.snooze, minutes: minutes);
    }
    if (_later.hasMatch(lower)) {
      // Said "later" without saying how much later. The caller's own default
      // is a better answer than a number invented here.
      return const SpokenAnswer(SpokenIntent.snooze);
    }

    return SpokenAnswer.unclear;
  }

  /// A duration inside a longer sentence, which `durationIn` will not read.
  ///
  /// `durationIn` answers a question whose whole content is a length. This
  /// one runs over a reply that also contains words, so it takes the units
  /// only - never a bare number, or "give me 5" and "in 2018" would both
  /// become minutes.
  int? _minutesIn(String lower) {
    final hours = RegExp(
      r'\b(?:an?|one|(\d+))\s*(?:hours?|hrs?)\b',
    ).firstMatch(lower);
    if (hours != null) {
      return int.parse(hours.group(1) ?? '1') * Duration.minutesPerHour;
    }
    final mins = RegExp(
      r'\b(\d+)\s*(?:minutes?|mins?)\b',
    ).firstMatch(lower);
    if (mins != null) return int.parse(mins.group(1)!);

    // Words, because people say them and a recogniser writes them down.
    const spelled = <String, int>{
      'five': 5,
      'ten': 10,
      'fifteen': 15,
      'twenty': 20,
      'thirty': 30,
      'forty': 40,
      'forty five': 45,
      'fifty': 50,
      'half an hour': 30,
    };
    for (final entry in spelled.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(lower) &&
          RegExp(r'\b(minutes?|mins?)\b').hasMatch(lower)) {
        return entry.value;
      }
      if (entry.key == 'half an hour' && lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}
