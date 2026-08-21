import 'package:meta/meta.dart';
import 'package:van_core/src/model/task.dart';

/// A task pulled out of a sentence, before anything has been persisted.
///
/// This is what both the model and the deterministic fallback produce, so the
/// rest of the app cannot tell which one ran.
@immutable
class TaskDraft {
  /// Creates a draft.
  const TaskDraft({
    required this.title,
    this.deadline,
    this.estimatedMinutes,
    this.priority = Priority.normal,
  });

  /// What to call it, with any date or duration phrasing removed.
  final String title;

  /// When it is due, in UTC, if the text said.
  final DateTime? deadline;

  /// How long it will take, if the text said.
  final int? estimatedMinutes;

  /// How much it matters.
  final Priority priority;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskDraft &&
          title == other.title &&
          deadline == other.deadline &&
          estimatedMinutes == other.estimatedMinutes &&
          priority == other.priority;

  @override
  int get hashCode => Object.hash(title, deadline, estimatedMinutes, priority);

  @override
  String toString() =>
      'TaskDraft("$title", due=$deadline, ${estimatedMinutes}m, '
      '${priority.name})';
}

/// Pulls dates, durations and urgency out of ordinary sentences.
///
/// This is the deterministic fallback behind the `extract_task` capability,
/// and in a build with no model it is the whole of task capture. It covers the
/// phrasings people actually type - "by wednesday", "tomorrow evening",
/// "2 hours", "asap" - and gives up gracefully on anything else rather than
/// guessing, because a wrong deadline is worse than no deadline.
class TemporalParser {
  /// Creates a parser reading wall-clock time at [utcOffset] from UTC.
  const TemporalParser({this.utcOffset = Duration.zero});

  /// Local time minus UTC. IST is `Duration(hours: 5, minutes: 30)`.
  final Duration utcOffset;

  static const _weekdays = <String, int>{
    'monday': DateTime.monday,
    'mon': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'tue': DateTime.tuesday,
    'tues': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'wed': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'thu': DateTime.thursday,
    'thurs': DateTime.thursday,
    'friday': DateTime.friday,
    'fri': DateTime.friday,
    'saturday': DateTime.saturday,
    'sat': DateTime.saturday,
    'sunday': DateTime.sunday,
    'sun': DateTime.sunday,
  };

  /// Default wall-clock hour for each part of the day.
  static const _endOfDay = 23;
  static const _morning = 9;
  static const _afternoon = 15;
  static const _evening = 20;

  /// Parses [text] as of [now] (UTC).
  TaskDraft parse(String text, {required DateTime now}) {
    assert(now.isUtc, 'now must be UTC');
    final lower = text.toLowerCase();
    final consumed = <_Span>[];

    final minutes = _parseDuration(lower, consumed);
    final priority = _parsePriority(lower, consumed);
    final deadline = _parseDeadline(lower, now, consumed);

    return TaskDraft(
      title: _titleFrom(text, consumed),
      deadline: deadline,
      estimatedMinutes: minutes,
      priority: priority,
    );
  }

  // --- duration -------------------------------------------------------------

  static final _durationPatterns = <RegExp>[
    RegExp(r'\b(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b'),
    RegExp(r'\b(\d+)\s*(?:minutes?|mins?|m)\b'),
    RegExp(r'\bhalf an hour\b'),
    RegExp(r'\ban hour\b'),
  ];

  int? _parseDuration(String lower, List<_Span> consumed) {
    // Hours first: "2 hours" must not be read as the "2 h" of "2 hrs".
    final hours = _durationPatterns[0].firstMatch(lower);
    if (hours != null) {
      consumed.add(_Span(hours.start, hours.end));
      final value = double.parse(hours.group(1)!);
      return (value * Duration.minutesPerHour).round();
    }

    final mins = _durationPatterns[1].firstMatch(lower);
    if (mins != null) {
      consumed.add(_Span(mins.start, mins.end));
      return int.parse(mins.group(1)!);
    }

    final half = _durationPatterns[2].firstMatch(lower);
    if (half != null) {
      consumed.add(_Span(half.start, half.end));
      return 30;
    }

    final one = _durationPatterns[3].firstMatch(lower);
    if (one != null) {
      consumed.add(_Span(one.start, one.end));
      return 60;
    }
    return null;
  }

  // --- priority -------------------------------------------------------------

  static final _highPriority = RegExp(
    r'\b(urgent|urgently|asap|critical|important)\b',
  );

  Priority _parsePriority(String lower, List<_Span> consumed) {
    final match = _highPriority.firstMatch(lower);
    if (match == null) return Priority.normal;
    consumed.add(_Span(match.start, match.end));
    return Priority.high;
  }

  // --- deadline -------------------------------------------------------------

  static final _inDays = RegExp(r'\bin\s+(\d+)\s*days?\b');
  static final _inWeeks = RegExp(r'\bin\s+(\d+)\s*weeks?\b');
  // "by next week" and "next week" both, so the preposition is consumed with
  // the phrase rather than stranded in the title.
  static final _weekOffset = RegExp(
    r'\b(?:by|before|within)?\s*(next|this)\s+week\b',
  );
  static final _inHours = RegExp(r'\bin\s+(\d+)\s*(?:hours?|hrs?)\b');
  static final _tonight = RegExp(r'\b(tonight|this evening)\b');
  static final _thisMorning = RegExp(r'\bthis morning\b');
  static final _thisAfternoon = RegExp(r'\bthis afternoon\b');
  static final _tomorrowPart = RegExp(
    r'\btomorrow(?:\s+(morning|afternoon|evening|night))?\b',
  );
  static final _todayWord = RegExp(r'\btoday\b');
  static final _weekdayPattern = RegExp(
    r'\b(?:by|on|next|this)?\s*'
    r'(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thu|'
    r'friday|fri|saturday|sat|sunday|sun)'
    r'(?:\s+(morning|afternoon|evening|night))?\b',
  );

  DateTime? _parseDeadline(String lower, DateTime now, List<_Span> consumed) {
    final wall = now.add(utcOffset);

    final inHours = _inHours.firstMatch(lower);
    if (inHours != null) {
      consumed.add(_Span(inHours.start, inHours.end));
      return now.add(Duration(hours: int.parse(inHours.group(1)!)));
    }

    final inWeeks = _inWeeks.firstMatch(lower);
    if (inWeeks != null) {
      consumed.add(_Span(inWeeks.start, inWeeks.end));
      final weeks = int.parse(inWeeks.group(1)!);
      return _atHour(wall.add(Duration(days: weeks * 7)), _endOfDay);
    }

    final inDays = _inDays.firstMatch(lower);
    if (inDays != null) {
      consumed.add(_Span(inDays.start, inDays.end));
      final target = wall.add(Duration(days: int.parse(inDays.group(1)!)));
      return _atHour(target, _endOfDay);
    }

    final tomorrow = _tomorrowPart.firstMatch(lower);
    if (tomorrow != null) {
      consumed.add(_Span(tomorrow.start, tomorrow.end));
      final target = wall.add(const Duration(days: 1));
      return _atHour(target, _hourForPart(tomorrow.group(1)));
    }

    final tonight = _tonight.firstMatch(lower);
    if (tonight != null) {
      consumed.add(_Span(tonight.start, tonight.end));
      return _atHour(wall, _evening);
    }

    final morning = _thisMorning.firstMatch(lower);
    if (morning != null) {
      consumed.add(_Span(morning.start, morning.end));
      return _atHour(wall, _morning);
    }

    final afternoon = _thisAfternoon.firstMatch(lower);
    if (afternoon != null) {
      consumed.add(_Span(afternoon.start, afternoon.end));
      return _atHour(wall, _afternoon);
    }

    // "next week" is seven days out, not "the end of the coming week". Van
    // schedules against a deadline, and the later, vaguer reading would let
    // work sit untouched for nine days without being late.
    //
    // "this week" is deliberately the same. It is said when someone means
    // soon-but-not-today, and resolving it to Friday would make a Monday
    // "this week" four days looser than a Thursday one.
    final weekOffset = _weekOffset.firstMatch(lower);
    if (weekOffset != null) {
      consumed.add(_Span(weekOffset.start, weekOffset.end));
      return _atHour(wall.add(const Duration(days: 7)), _endOfDay);
    }

    final weekday = _weekdayPattern.firstMatch(lower);
    if (weekday != null) {
      consumed.add(_Span(weekday.start, weekday.end));
      final target = _nextWeekday(wall, _weekdays[weekday.group(1)]!);
      return _atHour(target, _hourForPart(weekday.group(2)));
    }

    final today = _todayWord.firstMatch(lower);
    if (today != null) {
      consumed.add(_Span(today.start, today.end));
      return _atHour(wall, _endOfDay);
    }

    return null;
  }

  int _hourForPart(String? part) => switch (part) {
    'morning' => _morning,
    'afternoon' => _afternoon,
    'evening' || 'night' => _evening,
    _ => _endOfDay,
  };

  /// The next occurrence of [weekday] strictly after today.
  ///
  /// "by friday" said on a Friday means next Friday, not five minutes ago.
  DateTime _nextWeekday(DateTime wall, int weekday) {
    var delta = (weekday - wall.weekday) % 7;
    if (delta == 0) delta = 7;
    return wall.add(Duration(days: delta));
  }

  /// Builds a UTC instant for [hour] wall-clock on the day of [wall].
  DateTime _atHour(DateTime wall, int hour) {
    final local = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      hour,
      hour == _endOfDay ? 59 : 0,
    );
    return local.subtract(utcOffset);
  }

  // --- title ----------------------------------------------------------------

  // Applied to the original text, which keeps its casing, so this must be
  // case-insensitive: people type "I need to" as often as "i need to".
  static final _leadIn = RegExp(
    r'^(?:i\s+)?(?:need|have|want|got)\s+to\s+|'
    r'^(?:remind me to|remember to|todo:?)\s*|'
    r'^(?:i\s+)?should\s+',
    caseSensitive: false,
  );
  static final _trailingFiller = RegExp(r'[\s,;:.\-]*$');
  static final _leadingFiller = RegExp(r'^[\s,;:.\-]*');

  String _titleFrom(String original, List<_Span> consumed) {
    final buffer = StringBuffer();
    final sorted = [...consumed]..sort((a, b) => a.start.compareTo(b.start));

    var cursor = 0;
    for (final span in sorted) {
      if (span.start < cursor) continue;
      buffer.write(original.substring(cursor, span.start));
      buffer.write(' ');
      cursor = span.end;
    }
    buffer.write(original.substring(cursor));

    var title = buffer
        .toString()
        .replaceAll(RegExp(r'\b(?:by|before|due|within|for)\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    title = title.replaceFirst(_leadIn, '');
    title = title
        .replaceFirst(_leadingFiller, '')
        .replaceFirst(_trailingFiller, '');
    // Drop a dangling preposition left behind by a removed phrase.
    title = title
        .replaceFirst(RegExp(r'\s+(?:by|before|due|within|on|in)$'), '')
        .trim();

    if (title.isEmpty) return 'Untitled task';
    return title[0].toUpperCase() + title.substring(1);
  }
}

@immutable
class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}
