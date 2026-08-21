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
import 'package:van_core/van_core.dart';

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

  VanService serviceAt(Duration offset) {
    final events = EventRepo(db, clock);
    return VanService(
      tasks: TaskRepo(db),
      sessions: SessionRepo(db),
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
      notifications: FakeNotifications(),
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
}
