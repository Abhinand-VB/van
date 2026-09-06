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
  late FakeNotifications notifications;
  late FakeCalendars calendars;
  late EventRepo events;
  late SessionRepo sessions;
  late VanService service;
  late FakeClock clock;

  /// Wednesday 19 August 2026, 09:00 UTC.
  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    notifications = FakeNotifications();
    calendars = FakeCalendars();
    events = EventRepo(db, clock);
    sessions = SessionRepo(db);

    service = VanService(
      tasks: TaskRepo(db),
      sessions: sessions,
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
      notifications: notifications,
      calendars: calendars,
      calendarPreferences: CalendarPreferences(SettingsRepo(db)),
      templates: NudgeTemplates.fromJson(
        File('assets/nudge_templates/templates.json').readAsStringSync(),
      ),
      prompts: testPrompts(),
      clock: clock,
      ids: SequentialIds('e'),
      waking: const WakingHours(utcOffset: Duration.zero),
    );
  });

  tearDown(() async => db.close());

  /// The evidence row written alongside the proposal, which is the only place
  /// the gathered numbers are observable from outside.
  Future<Map<String, Object?>> evidenceOf(String sessionId) async {
    final row = (await events.all()).lastWhere(
      (e) => e.type == EventType.interventionSelected,
    );
    expect(row.field<String>('sessionId'), sessionId);
    return row.payload;
  }

  /// Captures a block and walks the clock past its start without touching it.
  Future<WorkSession> stalled() async {
    final captured = await service.capture('write the report 40 minutes');
    final session = captured.sessions.single;
    clock.advanceTo(session.plannedStart.add(const Duration(minutes: 30)));
    return session;
  }

  group('the evidence the log already held', () {
    test('a block nobody has started says so', () async {
      final session = await stalled();

      await service.negotiate(session.id, reason: 'too tired');

      final evidence = await evidenceOf(session.id);
      expect(evidence['everStarted'], isFalse);
    });

    test('a chain that was started once carries that forward', () async {
      // Start it, stop early so it is snoozeable, then move it. The
      // replacement inherits a history in which the work was begun - which is
      // the distinction the whole rule turns on.
      final session = await stalled();
      await service.startSession(session.id);
      final replacement = (await service.stuck(session.id, minutes: 5))!;
      clock.advanceTo(
        replacement.plannedStart.add(const Duration(minutes: 30)),
      );

      await service.negotiate(replacement.id, reason: 'still tired');

      expect((await evidenceOf(replacement.id))['everStarted'], isTrue);
    });

    test('starting one block of a task does not vouch for another', () async {
      // Two separate blocks of the same task are not one chain. Starting the
      // first hour says nothing about whether the third will begin, and
      // treating them as one history would make "ever started" mean almost
      // nothing.
      final captured = await service.capture('write the report 3 hours');
      expect(captured.sessions.length, greaterThan(1));
      await service.startSession(captured.sessions.first.id);

      final other = captured.sessions.last;
      clock.advanceTo(other.plannedStart.add(const Duration(minutes: 30)));
      await service.negotiate(other.id, reason: 'no');

      expect((await evidenceOf(other.id))['everStarted'], isFalse);
    });

    test('the hour of day is counted, started against scheduled', () async {
      final session = await stalled();

      await service.negotiate(session.id, reason: 'too tired');

      final evidence = await evidenceOf(session.id);
      expect(evidence['blocksAtHour'], greaterThan(0));
      expect(
        evidence['startsAtHour'],
        lessThanOrEqualTo(evidence['blocksAtHour']! as int),
      );
    });

    test('the calendar around the block is measured', () async {
      final session = await stalled();
      // A meeting covering the whole hour the block sits in.
      calendars
        ..granted = true
        ..entries.add(
          CalendarEntry(
            calendarId: 'work',
            start: session.plannedStart,
            end: session.plannedStart.add(const Duration(hours: 1)),
            title: 'Standup',
          ),
        );

      await service.negotiate(session.id, reason: 'in a meeting');

      // Four-hour window, one hour claimed.
      expect((await evidenceOf(session.id))['calendarBusyPercent'], 25);
    });

    test('no calendar means nought, not a failure', () async {
      final session = await stalled();

      await service.negotiate(session.id, reason: 'too tired');

      expect((await evidenceOf(session.id))['calendarBusyPercent'], 0);
    });

    test('a broken calendar costs the evidence and nothing else', () async {
      final session = await stalled();
      calendars
        ..granted = true
        ..failure = Exception('provider is down');

      final outcome = await service.negotiate(session.id, reason: 'too tired');

      // The negotiation still happened. A provider that will not answer must
      // not cost the user the conversation.
      expect(outcome, isNotNull);
      expect((await evidenceOf(session.id))['calendarBusyPercent'], 0);
    });

    test('nothing about a meeting reaches the log but a percentage', () async {
      final session = await stalled();
      calendars
        ..granted = true
        ..entries.add(
          CalendarEntry(
            calendarId: 'private-cal-77',
            start: session.plannedStart,
            end: session.plannedStart.add(const Duration(hours: 1)),
            title: 'Oncology follow-up',
          ),
        );

      await service.negotiate(session.id, reason: 'busy');

      // The same boundary D71 draws for the calendar screen: counts cross,
      // content does not. Asserted against the serialised log because that is
      // the file that never deletes.
      final log = (await events.all()).map((e) => e.payload.toString()).join();
      expect(log, isNot(contains('Oncology')));
      expect(log, isNot(contains('private-cal-77')));
    });
  });
}
