import 'package:meta/meta.dart';
import 'package:van_core/src/scheduling/time_window.dart';

/// What the user said when they were invited.
///
/// Modelled on what a device calendar actually reports rather than on what
/// would be tidy: [none] is the common case, because most entries in a
/// personal calendar have no attendees at all.
enum Attendance {
  /// Nobody was invited, or the provider does not track an answer.
  none,

  /// The user accepted.
  accepted,

  /// The user was invited and has not answered.
  invited,

  /// The user answered maybe.
  tentative,

  /// The user declined.
  declined,
}

/// One occurrence of a device-calendar event.
///
/// **The title is for the screen and for nothing else.** Van's `events` table
/// is append-only and never deletes, so a meeting title that reaches it is
/// there permanently. The rule is therefore not "handle it carefully" but a
/// boundary: it may be drawn, and it may never be persisted, logged, put in a
/// notification, or counted in the week report. `calendar_test.dart` asserts
/// that against the serialised log rather than trusting review.
///
/// It was originally not read at all, which was a stronger guarantee and a
/// worse calendar: a day view that draws every meeting as an anonymous grey
/// band cannot be read at a glance, which is the only thing a calendar is
/// for. See `docs/DECISIONS_PENDING.md` D70 and D71.
///
/// Nothing in *planning* uses it. [CalendarFilter.commitments] deliberately
/// produces nameless commitments, so the layer that writes to the event log
/// has no title to write even by accident.
///
/// [start] and [end] are UTC instants for a timed entry. For an all-day entry
/// they are UTC midnights *naming local dates*, which is how calendar
/// providers store them - the same convention Android's `CalendarContract`
/// uses. [CalendarFilter.span] resolves them against an offset; nothing else
/// should try to.
@immutable
class CalendarEntry {
  /// Creates an entry.
  CalendarEntry({
    required this.calendarId,
    required this.start,
    required this.end,
    this.title = '',
    this.isAllDay = false,
    this.isBusy = true,
    this.attendance = Attendance.none,
  }) : assert(start.isUtc && end.isUtc, 'calendar entries must be in UTC'),
       assert(!end.isBefore(start), 'an entry cannot end before it starts');

  /// Which device calendar this came from, so it can be excluded.
  final String calendarId;

  /// What the event is called. **Display only** - see the class comment.
  ///
  /// Empty is normal rather than exceptional: providers allow untitled
  /// events, and the screen has to have something to draw for one.
  final String title;

  /// When it begins.
  final DateTime start;

  /// When it ends, exclusive.
  final DateTime end;

  /// Whether the provider marks this as an all-day entry.
  final bool isAllDay;

  /// Whether the entry is marked busy rather than free.
  ///
  /// This is the transparency the user already sets on the event, and it is
  /// the whole signal for whether time is spoken for. See [CalendarFilter].
  final bool isBusy;

  /// The user's own answer, when there was something to answer.
  final Attendance attendance;

  @override
  String toString() =>
      'CalendarEntry(${start.toIso8601String()}..${end.toIso8601String()}, '
      'calendar=$calendarId, allDay=$isAllDay, busy=$isBusy, '
      '${attendance.name})';
}

/// Decides which calendar entries are claims on the user's time.
///
/// Pure, and separate from the platform code that reads the calendar, because
/// these two rules decide far more about how Van behaves than the plumbing
/// does and they deserve to be unit-tested rather than buried in an `if`
/// beside a database cursor.
///
/// **Transparency decides, not duration.** An entry blocks if it is marked
/// busy and does not if it is marked free. That one rule handles the case
/// that would otherwise make Van useless: most all-day entries are labels
/// rather than occupancy - a birthday, a quarter starting, someone else's
/// leave - and blocking a whole day for each of them would empty the calendar
/// of usable time roughly one day in five. An all-day entry marked *busy* is
/// unusual and deliberate, and it blocks the whole day. Duration was never
/// the signal.
///
/// **A declined entry does not block; an unanswered one does.** The asymmetry
/// is the argument: over-blocking costs some planning room and is visible,
/// while under-blocking schedules the user into a meeting they are already
/// sitting in - the exact failure Van exists to prevent. When in doubt,
/// block.
@immutable
class CalendarFilter {
  /// Creates a filter that resolves all-day entries against [utcOffset].
  const CalendarFilter({this.utcOffset = Duration.zero});

  /// Local time minus UTC, used only to place all-day entries.
  ///
  /// Explicit rather than ambient for the same reason [WakingHours] takes
  /// one: the core must behave identically on the phone and on CI.
  final Duration utcOffset;

  /// The same rules, read in a different timezone.
  CalendarFilter withUtcOffset(Duration newOffset) =>
      CalendarFilter(utcOffset: newOffset);

  /// Whether [entry] is time the user has already spoken for.
  bool blocks(CalendarEntry entry) =>
      entry.isBusy && entry.attendance != Attendance.declined;

  /// The blocking entries of [entries], as commitments the planner can use.
  ///
  /// **The label is a constant, not a description, even though a title is now
  /// available.** This is the seam between the part of Van that may see a
  /// meeting's name and the part that writes an append-only log. Dropping the
  /// name here means the planning and logging code physically has nothing to
  /// leak, rather than being trusted not to.
  List<Commitment> commitments(Iterable<CalendarEntry> entries) => [
    for (final entry in entries)
      if (blocks(entry))
        if (span(entry) case final at?)
          Commitment(start: at.start, end: at.end, label: 'calendar'),
  ];

  /// The real instants [entry] occupies, or null when it occupies none.
  ///
  /// Public because a calendar view has to place an all-day entry on exactly
  /// the day the planner blocked out, and two implementations of that
  /// arithmetic would eventually disagree by a timezone.
  ///
  /// An entry with no duration is dropped rather than asserted on. Providers
  /// do emit them - a zero-length marker, an instance clipped to the edge of
  /// the query window - and a commitment must have a duration.
  ({DateTime start, DateTime end})? span(CalendarEntry entry) {
    final start = entry.isAllDay
        ? entry.start.subtract(utcOffset)
        : entry.start;
    final end = entry.isAllDay ? entry.end.subtract(utcOffset) : entry.end;
    if (!start.isBefore(end)) return null;
    return (start: start, end: end);
  }

  @override
  String toString() => 'CalendarFilter(offset=$utcOffset)';
}
