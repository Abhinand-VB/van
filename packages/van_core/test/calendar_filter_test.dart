import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

void main() {
  /// Wednesday 19 August 2026, 09:00-10:00 UTC.
  DateTime at(int hour, [int minute = 0]) =>
      DateTime.utc(2026, 8, 19, hour, minute);

  CalendarEntry timed({
    bool isBusy = true,
    Attendance attendance = Attendance.none,
    String calendarId = 'work',
  }) => CalendarEntry(
    calendarId: calendarId,
    start: at(9),
    end: at(10),
    isBusy: isBusy,
    attendance: attendance,
  );

  /// An all-day entry for 19 August, stored the way providers store one:
  /// UTC midnights naming local dates.
  CalendarEntry allDay({
    bool isBusy = false,
    Attendance attendance = Attendance.none,
  }) => CalendarEntry(
    calendarId: 'personal',
    start: DateTime.utc(2026, 8, 19),
    end: DateTime.utc(2026, 8, 20),
    isAllDay: true,
    isBusy: isBusy,
    attendance: attendance,
  );

  group('transparency decides, not duration', () {
    const filter = CalendarFilter();

    test('an entry marked busy blocks', () {
      expect(filter.blocks(timed()), isTrue);
    });

    test('the same entry marked free does not', () {
      expect(filter.blocks(timed(isBusy: false)), isFalse);
    });

    test('an all-day transparent entry does not block', () {
      // The rule that keeps Van usable: birthdays, quarters starting and
      // other people's leave are all-day and free, and blocking a day for
      // each would empty the calendar of working time.
      expect(filter.blocks(allDay()), isFalse);
      expect(filter.commitments([allDay()]), isEmpty);
    });

    test('an all-day busy entry blocks the whole day', () {
      final blocked = filter.commitments([allDay(isBusy: true)]);
      expect(blocked, hasLength(1));
      expect(blocked.single.start, DateTime.utc(2026, 8, 19));
      expect(blocked.single.end, DateTime.utc(2026, 8, 20));
    });
  });

  group('the user answer decides for invitations', () {
    const filter = CalendarFilter();

    test('a declined entry does not block', () {
      expect(filter.blocks(timed(attendance: Attendance.declined)), isFalse);
    });

    test('an unanswered entry blocks', () {
      // Over-blocking loses planning room. Under-blocking nudges the user to
      // start work during a meeting they are already in.
      expect(filter.blocks(timed(attendance: Attendance.invited)), isTrue);
    });

    test('a tentative entry blocks', () {
      expect(filter.blocks(timed(attendance: Attendance.tentative)), isTrue);
    });

    test('an accepted entry blocks', () {
      expect(filter.blocks(timed(attendance: Attendance.accepted)), isTrue);
    });

    test('declining a free entry changes nothing', () {
      expect(
        filter.blocks(timed(isBusy: false, attendance: Attendance.declined)),
        isFalse,
      );
    });
  });

  group('all-day entries resolve against the offset', () {
    test('an all-day busy entry lands on the local day, not the UTC one', () {
      // UTC-7. The local day runs 07:00 on the 19th to 07:00 on the 20th UTC,
      // and reading the stored midnights as real instants would put the block
      // seven hours early - the shape of issue 18, in a new place.
      const filter = CalendarFilter(utcOffset: Duration(hours: -7));
      final blocked = filter.commitments([allDay(isBusy: true)]);

      expect(blocked.single.start, DateTime.utc(2026, 8, 19, 7));
      expect(blocked.single.end, DateTime.utc(2026, 8, 20, 7));
    });

    test('a timed entry is already a real instant and does not move', () {
      const filter = CalendarFilter(utcOffset: Duration(hours: 5, minutes: 30));
      final blocked = filter.commitments([timed()]);

      expect(blocked.single.start, at(9));
      expect(blocked.single.end, at(10));
    });

    test('withUtcOffset moves the filter and nothing else', () {
      const filter = CalendarFilter();
      expect(
        filter.withUtcOffset(const Duration(hours: 2)).utcOffset,
        const Duration(hours: 2),
      );
    });
  });

  group('commitments', () {
    const filter = CalendarFilter();

    test('keeps only the blocking entries', () {
      final blocked = filter.commitments([
        timed(),
        timed(isBusy: false),
        timed(attendance: Attendance.declined),
        allDay(),
      ]);
      expect(blocked, hasLength(1));
    });

    test('drops an entry with no duration rather than throwing', () {
      // Providers emit these: a zero-length marker, or an instance clipped
      // to the very edge of the query window.
      final blocked = filter.commitments([
        CalendarEntry(calendarId: 'work', start: at(9), end: at(9)),
      ]);
      expect(blocked, isEmpty);
    });

    test('carries no title, because there is none to carry', () {
      expect(filter.commitments([timed()]).single.label, 'calendar');
    });

    test('several calendars are simply more commitments', () {
      final blocked = filter.commitments([
        timed(calendarId: 'work'),
        timed(calendarId: 'university'),
        timed(calendarId: 'family'),
      ]);
      expect(blocked, hasLength(3));
    });
  });

  group('the planner cannot tell the sources apart', () {
    test('calendar commitments remove time from the free slots', () {
      const waking = WakingHours(startHour: 8, endHour: 23);
      const filter = CalendarFilter();

      final slots = const FreeSlotFinder(waking: waking).find(
        commitments: filter.commitments([timed()]),
        from: at(8),
        to: at(12),
      );

      expect(slots, [
        FreeSlot(start: at(8), end: at(9)),
        FreeSlot(start: at(10), end: at(12)),
      ]);
    });
  });
}
