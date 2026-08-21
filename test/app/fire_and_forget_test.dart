import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/inference/router.dart';
import 'package:van_core/van_core.dart';

/// An [EventRepo] whose writes always fail, standing in for a full disk or a
/// database torn down while something was still logging to it.
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
