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
import 'package:van/main.dart';
import 'package:van/platform/notifications.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late SessionRepo sessions;
  late VanService service;
  late FakeClock clock;

  /// Wednesday 19 August 2026, 09:00 UTC.
  final start = DateTime.utc(2026, 8, 19, 9);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(start);
    notifications = FakeNotifications();
    sessions = SessionRepo(db);
    final events = EventRepo(db, clock);

    service = VanService(
      tasks: TaskRepo(db),
      sessions: sessions,
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
      notifications: notifications,
      templates: NudgeTemplates.fromJson(
        File('assets/nudge_templates/templates.json').readAsStringSync(),
      ),
      prompts: testPrompts(),
      clock: clock,
      ids: SequentialIds('x'),
      waking: const WakingHours(utcOffset: Duration.zero),
    );
  });

  tearDown(() async => db.close());

  /// Captures a task and puts the clock a few minutes past its block, which
  /// is when a nudge would have fired.
  Future<WorkSession> due(String sentence) async {
    final result = await service.capture(sentence);
    final session = result.sessions.first;
    clock.advanceTo(session.plannedStart.add(const Duration(minutes: 5)));
    return session;
  }

  group('what each notification button does', () {
    // This is the single most important interaction Van has, and until now it
    // lived as a closure inside main() where no test could reach it. The
    // switch being wrong would mean pressing START moves the block instead of
    // starting it, and nothing would have caught that.

    test('START begins the session', () async {
      final session = await due('write the report 45 minutes');

      await handleNudgeAction(service, session.id, NudgeAction.start);

      final reloaded = await sessions.byId(session.id);
      expect(reloaded!.status, SessionStatus.started);
      expect(reloaded.hasStarted, isTrue);
    });

    test('START stands the rest of the ladder down', () async {
      final session = await due('write the report 45 minutes');

      await handleNudgeAction(service, session.id, NudgeAction.start);

      expect(
        notifications.scheduled.where((n) => n.sessionId == session.id),
        isEmpty,
        reason: 'answering must not leave Van chasing',
      );
    });

    test('Snooze moves the block and does not start it', () async {
      final session = await due('write the report 45 minutes');

      await handleNudgeAction(service, session.id, NudgeAction.snooze);

      expect(
        (await sessions.byId(session.id))!.status,
        SessionStatus.rescheduled,
      );
      final live = (await service.upcoming()).single;
      expect(live.parentSessionId, session.id);
      expect(live.hasStarted, isFalse);
    });

    test('Not today closes the block without a replacement', () async {
      final session = await due('write the report 45 minutes');

      await handleNudgeAction(service, session.id, NudgeAction.notToday);

      expect((await sessions.byId(session.id))!.status, SessionStatus.skipped);
      expect(await service.upcoming(), isEmpty);
    });

    test('opening the body changes nothing', () async {
      // Tapping the notification itself is not an answer. Van shows the Now
      // screen and waits for the user to choose.
      final session = await due('write the report 45 minutes');

      await handleNudgeAction(service, session.id, NudgeAction.opened);

      expect((await sessions.byId(session.id))!.status, SessionStatus.planned);
    });

    test('an action for a session that no longer exists is harmless', () async {
      await expectLater(
        handleNudgeAction(service, 'gone', NudgeAction.start),
        completes,
      );
    });
  });

  group('an action pressed while Van was not running', () {
    // The gap this closes. With the app killed, the callback passed to init()
    // does not exist - there is no Flutter engine to receive it. Android
    // launches Van and leaves the response in the launch details, which
    // nothing read. Pressing START at 09:00 would have opened Van and done
    // nothing at all.

    test('is collected at startup and acted on', () async {
      final session = await due('write the report 45 minutes');
      notifications.launchAction = (
        sessionId: session.id,
        action: NudgeAction.start,
      );

      final launched = await notifications.consumeLaunchAction();
      expect(launched, isNotNull);
      await handleNudgeAction(service, launched!.sessionId, launched.action);

      expect((await sessions.byId(session.id))!.status, SessionStatus.started);
    });

    test('is consumed once, not replayed on every launch', () async {
      final session = await due('write the report 45 minutes');
      notifications.launchAction = (
        sessionId: session.id,
        action: NudgeAction.snooze,
      );

      expect(await notifications.consumeLaunchAction(), isNotNull);
      expect(
        await notifications.consumeLaunchAction(),
        isNull,
        reason: 'replaying it would snooze the block again on every open',
      );
    });

    test('an ordinary launch has nothing to collect', () async {
      expect(await notifications.consumeLaunchAction(), isNull);
    });
  });
}
