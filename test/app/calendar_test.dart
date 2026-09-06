import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/settings_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_calendars.dart';
import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeCalendars calendars;
  late FakeNotifications notifications;
  late EventRepo events;
  late SessionRepo sessions;
  late CalendarPreferences preferences;
  late VanService service;
  late FakeClock clock;

  /// Wednesday 19 August 2026, 09:00 UTC. Inside the default waking window.
  final start = DateTime.utc(2026, 8, 19, 9);

  DateTime at(int hour, [int minute = 0]) =>
      DateTime.utc(2026, 8, 19, hour, minute);

  VanService build({Duration offset = Duration.zero}) => VanService(
    tasks: TaskRepo(db),
    sessions: sessions,
    events: events,
    nudges: NudgeRepo(db),
    router: InferenceRouter(
      defaultBackend: const NullBackend(),
      observer: EventLogInferenceObserver(events),
    ),
    notifications: notifications,
    calendars: calendars,
    calendarPreferences: preferences,
    templates: NudgeTemplates.fromJson(
      File('assets/nudge_templates/templates.json').readAsStringSync(),
    ),
    prompts: testPrompts(),
    clock: clock,
    ids: SequentialIds('x'),
    waking: WakingHours(utcOffset: offset),
  );

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    calendars = FakeCalendars()..granted = true;
    notifications = FakeNotifications();
    events = EventRepo(db, clock);
    sessions = SessionRepo(db);
    preferences = CalendarPreferences(SettingsRepo(db));
    service = build();
  });

  tearDown(() async => db.close());

  CalendarEntry meeting({
    DateTime? from,
    DateTime? to,
    bool isBusy = true,
    Attendance attendance = Attendance.none,
    String calendarId = 'work',
  }) => CalendarEntry(
    calendarId: calendarId,
    start: from ?? at(9),
    end: to ?? at(11),
    isBusy: isBusy,
    attendance: attendance,
  );

  Future<List<WorkSession>> planOneHour() async {
    final result = await service.capture('write the report, 60 minutes');
    return result.sessions;
  }

  group('a meeting is time Van cannot plan into', () {
    test('a busy entry pushes the block past it', () async {
      calendars.entries.add(meeting());

      final planned = await planOneHour();

      expect(planned, hasLength(1));
      expect(planned.single.plannedStart, at(11));
    });

    test('the same entry marked free does not', () async {
      calendars.entries.add(meeting(isBusy: false));

      final planned = await planOneHour();

      expect(planned.single.plannedStart, at(9));
    });

    test('a declined entry does not', () async {
      calendars.entries.add(meeting(attendance: Attendance.declined));

      final planned = await planOneHour();

      expect(planned.single.plannedStart, at(9));
    });

    test('an unanswered entry does', () async {
      calendars.entries.add(meeting(attendance: Attendance.invited));

      final planned = await planOneHour();

      expect(planned.single.plannedStart, at(11));
    });

    test('the sweep moves missed work around the calendar too', () async {
      // Nothing on the calendar when the block is planned.
      final planned = await planOneHour();
      expect(planned.single.plannedStart, at(9));

      // A meeting appears, and the block is never started. The sweep has to
      // read the calendar as it is now, not as it was at capture.
      calendars.entries.add(meeting(from: at(10), to: at(12)));
      clock.advance(const Duration(hours: 1, minutes: 15));

      final swept = await service.sweepStaleSessions();

      expect(swept.moved, hasLength(1));
      expect(swept.moved.single.plannedStart, at(12));
    });
  });

  group('excluding a calendar', () {
    test('removes its entries from planning', () async {
      calendars.entries.add(meeting(calendarId: 'holidays'));
      await preferences.setIncluded('holidays', included: false);

      final planned = await planOneHour();

      expect(planned.single.plannedStart, at(9));
    });

    test('leaves the other calendars alone', () async {
      calendars.entries
        ..add(meeting(calendarId: 'holidays'))
        ..add(meeting(calendarId: 'work'));
      await preferences.setIncluded('holidays', included: false);

      final planned = await planOneHour();

      expect(planned.single.plannedStart, at(11));
    });

    test(
      'a calendar added to the phone later is included by default',
      () async {
        // The reason exclusions are stored rather than inclusions. A calendar
        // Van has never seen must count, or granting access and then adding a
        // university timetable would silently do nothing.
        await preferences.setIncluded('holidays', included: false);
        calendars.entries.add(meeting(calendarId: 'university'));

        final planned = await planOneHour();

        expect(planned.single.plannedStart, at(11));
      },
    );

    test('an excluded calendar can be put back', () async {
      calendars.entries.add(meeting(calendarId: 'work'));
      await preferences.setIncluded('work', included: false);
      await preferences.setIncluded('work', included: true);

      final planned = await planOneHour();

      expect(planned.single.plannedStart, at(11));
    });
  });

  group('the calendar is read, never copied', () {
    test('every plan reads it again', () async {
      await planOneHour();
      await planOneHour();

      // Two reads for two planning passes. The OS owns the calendar and is
      // the source of truth for it; a copy inside Van would have to be
      // invalidated and there is no good moment to do that.
      expect(calendars.reads, hasLength(2));
      expect(calendars.reads.first.from, start);
    });

    test('a resume with nothing stale reads nothing', () async {
      // The Now screen sweeps on every resume. That path returns before it
      // needs a plan when there is nothing to move, and it must not pay for
      // a provider query to find that out.
      await service.sweepStaleSessions();

      expect(calendars.reads, isEmpty);
    });

    test('nothing is read at all without the grant', () async {
      calendars
        ..granted = false
        ..entries.add(meeting());

      final planned = await planOneHour();

      expect(calendars.reads, isEmpty);
      expect(planned.single.plannedStart, at(9));
      expect(service.calendarIsUnreadable, isFalse);
    });

    test('the log records how much was considered, and nothing else', () async {
      calendars.entries
        ..add(meeting())
        ..add(meeting(isBusy: false));

      await planOneHour();

      final read = (await events.ofType(EventType.calendarRead)).single;
      expect(read.field<int>('entries'), 2);
      expect(read.field<int>('commitments'), 1);
      expect(read.payload.keys, isNot(contains('title')));
    });
  });

  group('a broken calendar never costs the user their capture', () {
    setUp(() {
      calendars.failure = Exception('the provider is not responding');
      calendars.entries.add(meeting());
    });

    test('the task is still captured and still planned', () async {
      final result = await service.capture('write the report, 60 minutes');

      expect(result.task.title, 'Write the report');
      // Planned as if the calendar were empty, which is the honest fallback:
      // the user's typed sentence is worth more than a perfect plan.
      expect(result.sessions.single.plannedStart, at(9));
    });

    test('the degradation is surfaced rather than swallowed', () async {
      expect(service.calendarIsUnreadable, isFalse);

      await planOneHour();

      expect(service.calendarIsUnreadable, isTrue);
      expect(await events.ofType(EventType.calendarUnavailable), hasLength(1));
    });

    test('a later successful read clears it', () async {
      await planOneHour();
      expect(service.calendarIsUnreadable, isTrue);

      calendars.failure = null;
      await planOneHour();

      expect(service.calendarIsUnreadable, isFalse);
    });

    test('losing the grant mid-session is not reported as a fault', () async {
      calendars
        ..failure = null
        ..granted = false;

      await planOneHour();

      expect(service.calendarIsUnreadable, isFalse);
    });

    test('the sweep survives it too', () async {
      calendars.failure = null;
      await planOneHour();
      calendars.failure = Exception('permission revoked');
      // Past 12:00, which is an hour after the block the meeting pushed to
      // 11:00 - the point at which the sweep considers it abandoned.
      clock.advance(const Duration(hours: 3, minutes: 15));

      final swept = await service.sweepStaleSessions();

      expect(swept.total, 1);
      expect(service.calendarIsUnreadable, isTrue);
    });
  });

  group('no calendar content reaches the log', () {
    test('the whole serialised log is free of anything identifying', () async {
      // Asserted against the serialised log rather than trusted to review,
      // because `events` is append-only: a meeting title that lands in it is
      // on the phone permanently, and no later change can take it out.
      //
      // Van cannot leak what it never reads - CalendarEntry carries no title
      // and the platform channel never puts one on the wire - and this test
      // is what stops someone helpfully adding one.
      calendars.entries.add(
        meeting(attendance: Attendance.accepted, calendarId: 'cal-7291-work'),
      );

      await planOneHour();
      clock.advance(const Duration(hours: 3));
      await service.sweepStaleSessions();

      final serialised = jsonEncode([
        for (final event in await events.all())
          {'type': event.type.name, 'payload': event.payload},
      ]);

      // The calendar's own id, and the field names that could only be there
      // because something started carrying calendar content. Van's own task
      // titles are its business and are supposed to be in the log.
      for (final forbidden in [
        'cal-7291-work',
        'attendance',
        'allday',
        'label',
      ]) {
        expect(
          serialised.toLowerCase(),
          isNot(contains(forbidden.toLowerCase())),
          reason: 'the event log must say how much, never what',
        );
      }
    });

    test('no notification body mentions the calendar', () async {
      calendars.entries.add(meeting(from: at(12), to: at(13)));

      await planOneHour();

      expect(notifications.scheduled, isNotEmpty);
      for (final nudge in notifications.scheduled) {
        expect(nudge.body.toLowerCase(), isNot(contains('calendar')));
        expect(nudge.title.toLowerCase(), isNot(contains('calendar')));
      }
    });
  });
}
