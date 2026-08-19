import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

/// Wednesday 19 August 2026, 09:00 UTC.
final now = DateTime.utc(2026, 8, 19, 9);

const parser = TemporalParser();

TaskDraft parse(String text) => parser.parse(text, now: now);

void main() {
  group('durations', () {
    test('hours', () {
      expect(parse('read the paper 2 hours').estimatedMinutes, 120);
      expect(parse('read 3 hrs').estimatedMinutes, 180);
      expect(parse('read 1 hour').estimatedMinutes, 60);
    });

    test('fractional hours', () {
      expect(parse('gym 1.5 hours').estimatedMinutes, 90);
    });

    test('minutes', () {
      expect(parse('email prof 20 minutes').estimatedMinutes, 20);
      expect(parse('email prof 45 mins').estimatedMinutes, 45);
      expect(parse('email prof 30 min').estimatedMinutes, 30);
    });

    test('written-out durations', () {
      expect(parse('walk half an hour').estimatedMinutes, 30);
      expect(parse('walk an hour').estimatedMinutes, 60);
    });

    test('hours win over a stray minute abbreviation', () {
      expect(parse('study 2 hours').estimatedMinutes, 120);
    });

    test('no duration mentioned', () {
      expect(parse('finish the assignment').estimatedMinutes, isNull);
    });
  });

  group('relative days', () {
    test('today means end of today', () {
      final due = parse('submit today').deadline!;
      expect(due, DateTime.utc(2026, 8, 19, 23, 59));
    });

    test('tomorrow means end of tomorrow', () {
      expect(
        parse('submit tomorrow').deadline,
        DateTime.utc(2026, 8, 20, 23, 59),
      );
    });

    test('tomorrow evening', () {
      expect(
        parse('gym tomorrow evening').deadline,
        DateTime.utc(2026, 8, 20, 20),
      );
    });

    test('tomorrow morning', () {
      expect(
        parse('call tomorrow morning').deadline,
        DateTime.utc(2026, 8, 20, 9),
      );
    });

    test('tonight and this evening agree', () {
      expect(parse('read tonight').deadline, DateTime.utc(2026, 8, 19, 20));
      expect(
        parse('read this evening').deadline,
        DateTime.utc(2026, 8, 19, 20),
      );
    });

    test('this morning and this afternoon', () {
      expect(parse('call this morning').deadline, DateTime.utc(2026, 8, 19, 9));
      expect(
        parse('call this afternoon').deadline,
        DateTime.utc(2026, 8, 19, 15),
      );
    });

    test('in N days', () {
      expect(
        parse('report in 3 days').deadline,
        DateTime.utc(2026, 8, 22, 23, 59),
      );
    });

    test('in N hours is relative to the instant, not the day', () {
      expect(parse('reply in 5 hours').deadline, DateTime.utc(2026, 8, 19, 14));
    });
  });

  group('weekdays', () {
    test('a later weekday lands this week', () {
      // Wednesday the 19th, so Friday is the 21st.
      expect(
        parse('assignment by friday').deadline,
        DateTime.utc(2026, 8, 21, 23, 59),
      );
    });

    test('an earlier weekday rolls to next week', () {
      // Monday already passed, so it means the 24th.
      expect(
        parse('assignment by monday').deadline,
        DateTime.utc(2026, 8, 24, 23, 59),
      );
    });

    test('the same weekday means next week, not five minutes ago', () {
      expect(
        parse('assignment by wednesday').deadline,
        DateTime.utc(2026, 8, 26, 23, 59),
      );
    });

    test('abbreviations work', () {
      expect(
        parse('assignment by fri').deadline,
        DateTime.utc(2026, 8, 21, 23, 59),
      );
      expect(
        parse('assignment by thurs').deadline,
        DateTime.utc(2026, 8, 20, 23, 59),
      );
    });

    test('weekday with a part of day', () {
      expect(
        parse('gym friday morning').deadline,
        DateTime.utc(2026, 8, 21, 9),
      );
    });

    test('on and next are both understood', () {
      expect(
        parse('meet on friday').deadline,
        DateTime.utc(2026, 8, 21, 23, 59),
      );
      expect(
        parse('meet next friday').deadline,
        DateTime.utc(2026, 8, 21, 23, 59),
      );
    });
  });

  group('priority', () {
    test('urgency words raise it', () {
      expect(parse('urgent: submit form').priority, Priority.high);
      expect(parse('reply asap').priority, Priority.high);
      expect(parse('important meeting prep').priority, Priority.high);
    });

    test('nothing special stays normal', () {
      expect(parse('read a book').priority, Priority.normal);
    });
  });

  group('titles', () {
    test('strips the matched temporal phrasing', () {
      expect(
        parse('finish the assignment by friday').title,
        'Finish the assignment',
      );
    });

    test('strips duration as well as deadline', () {
      final draft = parse('finish the assignment by friday 2 hours');
      expect(draft.title, 'Finish the assignment');
      expect(draft.estimatedMinutes, 120);
      expect(draft.deadline, DateTime.utc(2026, 8, 21, 23, 59));
    });

    test('strips conversational lead-ins', () {
      expect(
        parse('i need to finish the assignment').title,
        'Finish the assignment',
      );
      expect(
        parse('remind me to email my professor').title,
        'Email my professor',
      );
      expect(parse('I should call mum').title, 'Call mum');
    });

    test('capitalises the first letter', () {
      expect(parse('walk the dog').title, 'Walk the dog');
    });

    test('keeps the original casing of the body', () {
      expect(
        parse('finish the DBMS lab by friday').title,
        'Finish the DBMS lab',
      );
    });

    test('falls back rather than producing an empty title', () {
      expect(parse('tomorrow').title, 'Untitled task');
    });

    test('collapses the whitespace left by removals', () {
      expect(
        parse('finish   the    assignment').title,
        'Finish the assignment',
      );
    });
  });

  group('real sentences', () {
    test('the example from the brief', () {
      final draft = parse(
        'I need to finish my database assignment by Wednesday',
      );
      expect(draft.title, 'Finish my database assignment');
      expect(draft.deadline, DateTime.utc(2026, 8, 26, 23, 59));
      expect(draft.priority, Priority.normal);
    });

    test('casual phrasing with a duration', () {
      final draft = parse(
        'bro I need to finish this assignment by tomorrow 3 hours',
      );
      expect(draft.deadline, DateTime.utc(2026, 8, 20, 23, 59));
      expect(draft.estimatedMinutes, 180);
      expect(draft.title, contains('assignment'));
    });

    test('urgent with a same-day deadline', () {
      final draft = parse('urgent: submit the form tonight');
      expect(draft.priority, Priority.high);
      expect(draft.deadline, DateTime.utc(2026, 8, 19, 20));
      expect(draft.title, 'Submit the form');
    });

    test('a bare task keeps everything null', () {
      final draft = parse('buy milk');
      expect(draft.title, 'Buy milk');
      expect(draft.deadline, isNull);
      expect(draft.estimatedMinutes, isNull);
    });
  });

  group('timezone offsets', () {
    test('a local end-of-day converts back to the right UTC instant', () {
      const ist = TemporalParser(utcOffset: Duration(hours: 5, minutes: 30));
      // 19 Aug 09:00 UTC is 14:30 IST, so "today" is still the 19th locally
      // and end of day is 23:59 IST = 18:29 UTC.
      final due = ist.parse('submit today', now: now).deadline!;
      expect(due, DateTime.utc(2026, 8, 19, 18, 29));
    });

    test('an offset can push the local day ahead of the UTC day', () {
      const ist = TemporalParser(utcOffset: Duration(hours: 5, minutes: 30));
      final lateUtc = DateTime.utc(2026, 8, 19, 20); // 01:30 IST on the 20th
      final due = ist.parse('submit today', now: lateUtc).deadline!;
      expect(due, DateTime.utc(2026, 8, 20, 18, 29));
    });
  });

  group('equality', () {
    test('drafts compare by value', () {
      expect(parse('buy milk'), parse('buy milk'));
      expect(parse('buy milk'), isNot(parse('buy bread')));
    });
  });
}
