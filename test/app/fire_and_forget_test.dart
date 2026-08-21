import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:van/ui/background.dart';
import 'package:van/ui/task_list_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/prompts.dart';

/// An [EventRepo] whose writes always fail, standing in for a full disk or a
/// database torn down while something was still logging to it.
/// A service whose task list cannot be read, standing in for a database that
/// has gone away underneath a screen.
class _FailingReads extends VanService {
  _FailingReads({
    required super.tasks,
    required super.sessions,
    required super.events,
    required super.nudges,
    required super.router,
    required super.notifications,
    required super.templates,
    required super.prompts,
    required super.clock,
    required super.ids,
  });

  @override
  Future<List<Task>> openTasks() async => throw Exception('the read failed');
}

class _FailingEvents extends EventRepo {
  _FailingEvents(super._db, super._clock);

  @override
  Future<VanEvent> append(
    EventType type, [
    Map<String, Object?> payload = const {},
    DateTime? at,
  ]) async => throw Exception('the write failed');
}

void main() {
  late VanDatabase db;
  late FakeClock clock;

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 8, 19, 9));
  });

  tearDown(() async => db.close());

  group('inBackground', () {
    test('swallows a failure that nothing could have awaited', () async {
      Object? escaped;

      await runZonedGuarded(() async {
        inBackground(Future<void>.error(Exception('no')));
        await Future<void>.delayed(Duration.zero);
      }, (error, stack) => escaped = error);

      expect(escaped, isNull);
    });

    test('still runs the work', () async {
      var ran = false;

      await runZonedGuarded(() async {
        inBackground(Future<void>(() async => ran = true));
        await Future<void>.delayed(Duration.zero);
      }, (_, _) {});

      expect(ran, isTrue);
    });

    test('does not wait for it', () {
      // The whole reason it exists: the callers are void, so this must return
      // before the work finishes or those callbacks would have to block.
      var finished = false;
      inBackground(
        Future<void>.delayed(
          const Duration(milliseconds: 50),
          () => finished = true,
        ),
      );

      expect(finished, isFalse);
    });
  });

  group('a screen whose refresh fails', () {
    testWidgets('does not take the app down with it', (tester) async {
      // initState and didChangeAppLifecycleState both return void, so nothing
      // is able to await the refresh they start. Before `inBackground` a
      // failed read escaped to the zone; the honest behaviour is to leave the
      // last good view on screen and say nothing, because the user did not
      // ask for this refresh.
      final events = EventRepo(db, clock);
      final service = _FailingReads(
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
        ids: SequentialIds('z'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TaskListScreen(service: service, clock: clock),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('logging an inference', () {
    test('a failed write does not escape into the zone', () async {
      // `unawaited` silences the analyzer and catches nothing, so before this
      // a failed append surfaced as an unhandled asynchronous error in
      // whichever zone the inference happened to run in - reaching Flutter's
      // error handler in the app, and failing unrelated tests in the suite.
      // The comment on onInference promised the opposite.
      Object? escaped;

      await runZonedGuarded(
        () async {
          EventLogInferenceObserver(_FailingEvents(db, clock)).onInference(
            capabilityId: 'extract_task',
            backendId: 'none',
            outcome: InferenceOutcome.fallback,
            failureReason: 'unavailable',
          );
          // Let the failed write settle. Without the handler the error lands
          // here, on this turn of the microtask queue.
          await Future<void>.delayed(Duration.zero);
        },
        (error, stack) => escaped = error,
      );

      expect(
        escaped,
        isNull,
        reason: "a logging failure must not become everyone else's problem",
      );
    });

    test('and the caller is never made to wait on it', () async {
      // The observer interface is synchronous on purpose: an inference must
      // not be delayed by the record of it. This would hang if onInference
      // ever started awaiting its own write.
      final events = _FailingEvents(db, clock);

      expect(
        () => EventLogInferenceObserver(events).onInference(
          capabilityId: 'compose_nudge',
          backendId: 'none',
          outcome: InferenceOutcome.model,
        ),
        returnsNormally,
      );
    });

    test('a successful write still lands', () async {
      final events = EventRepo(db, clock);

      EventLogInferenceObserver(events).onInference(
        capabilityId: 'extract_task',
        backendId: 'none',
        outcome: InferenceOutcome.model,
        latencyMs: 7,
      );
      await Future<void>.delayed(Duration.zero);

      final logged = await events.ofType(EventType.inferenceOk);
      expect(logged, hasLength(1));
      expect(logged.single.field<String>('capability'), 'extract_task');
      expect(logged.single.field<int>('latencyMs'), 7);
    });
  });
}
