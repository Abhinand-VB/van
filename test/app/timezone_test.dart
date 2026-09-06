import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van/platform/calendars.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_calendars.dart';
import '../support/fake_notifications.dart';
import '../support/prompts.dart';

/// The test device's real offset: America/Los_Angeles in August.
///
/// Every other suite runs at UTC, which is convenient arithmetic and the exact
/// reason a whole timezone was able to go unwired without anything failing.
const pacific = Duration(hours: -7);

void main() {
  late VanDatabase db;
  late FakeClock clock;

  /// Wednesday 19 August 2026, 09:00 UTC — 02:00 in Pacific.
  final start = DateTime.utc(2026, 8, 19, 9);

  VanService serviceAt(Duration offset, {Calendars? calendars}) {
    final events = EventRepo(db, clock);
    return VanService(
      tasks: TaskRepo(db),
      sessions: SessionRepo(db),
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
      notifications: FakeNotifications(),
      calendars: calendars ?? const UnsupportedCalendars(),
      templates: NudgeTemplates.fromJson(
        File('assets/nudge_templates/templates.json').readAsStringSync(),
      ),
      prompts: testPrompts(),
      clock: clock,
      ids: SequentialIds('x'),
      waking: WakingHours(utcOffset: offset),
    );
  }

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
  });

  tearDown(() async => db.close());

  /// The wall-clock time [utc] reads as on a device at [pacific].
  DateTime asLocalWall(DateTime utc) => utc.add(pacific);

  group('a deadline means the same thing the user meant', () {
    test('"by friday" is the end of Friday where the user is', () async {
      // The bug this closes. VanService built ExtractTask with the default
      // parser, which runs at UTC — so on this device "by friday" resolved to
      // Friday 23:59 UTC, which is Friday 16:59 in the afternoon locally.
      final captured = await serviceAt(
        pacific,
      ).capture('finish the report by friday');

      final wall = asLocalWall(captured.task.deadline!);
      expect(wall.weekday, DateTime.friday);
      expect(wall.hour, 23);
      expect(captured.task.deadline, DateTime.utc(2026, 8, 22, 6, 59));
    });

    test('"today" is not already over by teatime', () async {
      // Captured at 17:00 local. With the parser at UTC that produced 23:59
      // UTC — 16:59 local — so the task was born an hour overdue.
      clock.advanceTo(DateTime.utc(2026, 8, 20).add(const Duration(hours: 24)));
      final now = clock.now();
      expect(asLocalWall(now).hour, 17, reason: 'set the scene at teatime');

      final captured = await serviceAt(
        pacific,
      ).capture('email the landlord today');

      expect(
        captured.task.deadline!.isAfter(now),
        isTrue,
        reason: 'a task due today must not be overdue the moment it is typed',
      );
      expect(asLocalWall(captured.task.deadline!).hour, 23);
    });

    test('"tonight" is the evening, not the middle of the afternoon', () async {
      final captured = await serviceAt(pacific).capture('pack the bag tonight');

      expect(asLocalWall(captured.task.deadline!).hour, 20);
    });
  });

  group('the parser and the planner agree', () {
    test('blocks land inside waking hours, in the same zone', () async {
      // These two used to read different clocks: WakingHours got the device
      // offset in main.dart and the parser did not. A plan can only make
      // sense if both agree on what day it is.
      final captured = await serviceAt(
        pacific,
      ).capture('write the report 2 hours');

      expect(captured.sessions, isNotEmpty);
      for (final session in captured.sessions) {
        final wall = asLocalWall(session.plannedStart);
        expect(wall.hour, greaterThanOrEqualTo(8));
        expect(wall.hour, lessThan(23));
      }
    });

    test('work fits before a deadline the user would recognise', () async {
      final captured = await serviceAt(
        pacific,
      ).capture('finish the report by friday, 3 hours');

      final deadline = captured.task.deadline!;
      for (final session in captured.sessions) {
        expect(
          session.plannedEnd.isBefore(deadline),
          isTrue,
          reason: 'a block scheduled after its own deadline helps nobody',
        );
      }
    });
  });

  group('at UTC nothing changes', () {
    test('the offset-zero behaviour every other suite relies on', () async {
      final captured = await serviceAt(
        Duration.zero,
      ).capture('finish the report by friday');

      expect(captured.task.deadline, DateTime.utc(2026, 8, 21, 23, 59));
    });
  });

  group('the offset can move under a running process', () {
    // Issue 19. The offset was read once in main.dart and frozen into three
    // places at construction, so a process alive across a DST change or a
    // flight kept planning in the zone it launched in until restart.

    test('nothing moves when the offset has not', () {
      final service = serviceAt(pacific);
      expect(service.refreshTimezone(pacific), isFalse);
      expect(service.utcOffset, pacific);
    });

    test('the parser follows the device to a new zone', () async {
      // Launched at UTC, then the phone moves to Pacific. "by friday" has to
      // mean the end of Friday where the user now is, not where they were.
      final service = serviceAt(Duration.zero);
      expect(service.refreshTimezone(pacific), isTrue);
      expect(service.utcOffset, pacific);

      final captured = await service.capture('finish the report by friday');

      expect(asLocalWall(captured.task.deadline!).hour, 23);
      expect(captured.task.deadline, DateTime.utc(2026, 8, 22, 6, 59));
    });

    test('the planner follows too, so the two still agree', () async {
      // The failure mode worth guarding is not "the offset is wrong" but
      // "half of it moved" - a parser in one zone and a waking window in
      // another is issue 18 wearing a different hat.
      final service = serviceAt(Duration.zero);
      service.refreshTimezone(pacific);

      final captured = await service.capture('write the report 2 hours');

      expect(captured.sessions, isNotEmpty);
      for (final session in captured.sessions) {
        final wall = asLocalWall(session.plannedStart);
        expect(wall.hour, greaterThanOrEqualTo(8));
        expect(wall.hour, lessThan(23));
      }
    });

    test('an hour of DST is enough to matter', () async {
      // Not a flight - the ordinary case, and the one that will actually
      // happen. Next US transition is 1 Nov 2026.
      final service = serviceAt(const Duration(hours: -8));
      expect(service.refreshTimezone(const Duration(hours: -7)), isTrue);

      final captured = await service.capture('email the landlord today');
      expect(asLocalWall(captured.task.deadline!).hour, 23);
    });
  });

  group('the calendar lands where the user is', () {
    /// A calendar holding one entry, with the grant already given.
    FakeCalendars calendarWith(CalendarEntry entry) => FakeCalendars()
      ..granted = true
      ..entries.add(entry);

    test(
      'an all-day busy entry blocks the local day, not the UTC one',
      () async {
        // Providers store all-day entries as UTC midnights *naming local
        // dates*. Read as instants they would block 00:00-00:00 UTC, which at
        // this offset is 17:00 on the 18th to 17:00 on the 19th locally - most
        // of the wrong day, and it would leave the evening of the 19th looking
        // free. This is issue 18 in a new place, and it is why CalendarFilter
        // carries an offset at all.
        final service = serviceAt(
          pacific,
          calendars: calendarWith(
            CalendarEntry(
              calendarId: 'work',
              start: DateTime.utc(2026, 8, 19),
              end: DateTime.utc(2026, 8, 20),
              isAllDay: true,
            ),
          ),
        );

        final captured = await service.capture('write the report 60 minutes');

        // The whole of Wednesday local is spoken for, so the work goes to
        // Thursday morning - 08:00 local, which is 15:00 UTC.
        expect(
          captured.sessions.single.plannedStart,
          DateTime.utc(2026, 8, 20, 15),
        );
        expect(asLocalWall(captured.sessions.single.plannedStart).day, 20);
      },
    );

    test('an all-day transparent entry still costs nothing', () async {
      final service = serviceAt(
        pacific,
        calendars: calendarWith(
          CalendarEntry(
            calendarId: 'birthdays',
            start: DateTime.utc(2026, 8, 19),
            end: DateTime.utc(2026, 8, 20),
            isAllDay: true,
            isBusy: false,
          ),
        ),
      );

      final captured = await service.capture('write the report 60 minutes');

      // First thing on Wednesday local, unaffected.
      expect(
        captured.sessions.single.plannedStart,
        DateTime.utc(2026, 8, 19, 15),
      );
    });

    test(
      'a timed entry from another timezone lands at the right instant',
      () async {
        // 08:00-09:00 Pacific, which is how the provider reports a meeting
        // someone in another country put on the calendar: as a UTC instant.
        final service = serviceAt(
          pacific,
          calendars: calendarWith(
            CalendarEntry(
              calendarId: 'work',
              start: DateTime.utc(2026, 8, 19, 15),
              end: DateTime.utc(2026, 8, 19, 16),
            ),
          ),
        );

        final captured = await service.capture('write the report 60 minutes');

        expect(
          captured.sessions.single.plannedStart,
          DateTime.utc(2026, 8, 19, 16),
        );
        expect(asLocalWall(captured.sessions.single.plannedStart).hour, 9);
      },
    );

    test('the filter follows the device to a new zone', () async {
      // The half-moved failure again: a waking window in one zone and a
      // calendar filter in another would place an all-day commitment on a
      // day the planner is not looking at.
      final service = serviceAt(
        Duration.zero,
        calendars: calendarWith(
          CalendarEntry(
            calendarId: 'work',
            start: DateTime.utc(2026, 8, 19),
            end: DateTime.utc(2026, 8, 20),
            isAllDay: true,
          ),
        ),
      );
      expect(service.refreshTimezone(pacific), isTrue);

      final captured = await service.capture('write the report 60 minutes');

      expect(
        captured.sessions.single.plannedStart,
        DateTime.utc(2026, 8, 20, 15),
      );
    });
  });

  group('SuppressionPolicy.withWaking', () {
    test('keeps every knob except the one being changed', () {
      const tuned = SuppressionPolicy(
        minimumGapMinutes: 45,
        escalationGapMinutes: 9,
        dismissalLimit: 5,
        fatigueProbeMinutes: 60,
        overrideGapAtImportance: 7,
        overrideAllAtImportance: 9,
      );

      final moved = tuned.withWaking(const WakingHours(utcOffset: pacific));

      expect(moved.waking.utcOffset, pacific);
      expect(moved.minimumGapMinutes, 45);
      expect(moved.escalationGapMinutes, 9);
      expect(moved.dismissalLimit, 5);
      expect(moved.fatigueProbeMinutes, 60);
      expect(moved.overrideGapAtImportance, 7);
      expect(moved.overrideAllAtImportance, 9);
    });

    test('the waking hours themselves do not move with the user', () {
      const policy = SuppressionPolicy(
        waking: WakingHours(startHour: 6, endHour: 22),
      );

      final moved = policy.withWaking(
        policy.waking.withUtcOffset(const Duration(hours: 5, minutes: 30)),
      );

      expect(moved.waking.startHour, 6);
      expect(moved.waking.endHour, 22);
      expect(moved.waking.utcOffset, const Duration(hours: 5, minutes: 30));
    });
  });
}
