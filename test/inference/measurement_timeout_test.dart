import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/backends/gemma_backend.dart';
import 'package:van/inference/on_device_runner.dart';

import '../support/fake_local_llm.dart';

void main() {
  /// What every capability asks for, because none of them sets a timeout.
  const request = LlmRequest(prompt: 'a sentence');

  /// Runs [backend] against a model that takes [takes], without waiting.
  ///
  /// Real delays here cost twenty seconds a case and the suite runs in
  /// twenty-five for everything. `fakeAsync` moves the clock instead, which
  /// is also the only honest way to test a five-minute limit.
  LlmResult resultAfter(Duration takes, {Duration? timeout}) {
    late LlmResult outcome;
    fakeAsync((async) {
      final llm = FakeLocalLlm()..hang = takes;
      unawaited(
        GemmaBackend(
          llm,
          timeout: timeout,
        ).generate(request).then((r) => outcome = r),
      );
      async
        ..elapse(takes + const Duration(seconds: 1))
        ..flushMicrotasks();
    });
    return outcome;
  }

  group('what a request asks for', () {
    test('is respected in production, where nothing overrides it', () {
      // 20 seconds is the default and it is right for a capture: it is how
      // long a person will wait, which is not a fact about the model.
      expect(request.timeout, const Duration(seconds: 20));

      final result = resultAfter(const Duration(seconds: 25));

      expect(result, isA<LlmFailure>());
      expect((result as LlmFailure).kind, LlmFailureKind.timeout);
      expect(result.message, contains('20000ms'));
    });

    test('the model as measured never finishes inside it', () {
      // The defect this whole change exists for. 164,990 ms was measured on
      // the phone; at the production limit the golden run would have timed
      // out all 29 cases and reported a confident zero.
      final result = resultAfter(const Duration(milliseconds: 164990));

      expect((result as LlmFailure).kind, LlmFailureKind.timeout);
    });
  });

  group('what the measurement harness asks for', () {
    test('overrides it, and reports the number it actually used', () {
      final result = resultAfter(
        const Duration(minutes: 6),
        timeout: measurementTimeout,
      );

      expect((result as LlmFailure).kind, LlmFailureKind.timeout);
      expect(result.message, contains('300000ms'));
    });

    test('lets the same measured latency through', () {
      final llm = FakeLocalLlm()
        ..hang = const Duration(milliseconds: 164990)
        ..reply = '{"title": "Write the report"}';
      late LlmResult outcome;

      fakeAsync((async) {
        unawaited(
          GemmaBackend(
            llm,
            timeout: measurementTimeout,
          ).generate(request).then((r) => outcome = r),
        );
        async
          ..elapse(const Duration(minutes: 3))
          ..flushMicrotasks();
      });

      expect(outcome, isA<LlmOk>());
    });

    test('is long enough for the latency actually measured', () {
      // 164,990 ms cold and 183,643 ms warm. A limit under those turns every
      // case into a timeout and the run into a number about nothing.
      expect(
        measurementTimeout,
        greaterThan(const Duration(milliseconds: 183643)),
      );
      expect(measurementTimeout, greaterThan(request.timeout));
    });
  });

  group('the declared latency', () {
    test('is the measured number, not the old guess', () {
      // A decision that reads this must not be told the model answers in a
      // second. It answers in about two and three quarter minutes.
      final declared = GemmaBackend(
        FakeLocalLlm(),
      ).capabilities.typicalLatencyMs;

      expect(declared, 165000);
      expect(
        declared,
        greaterThan(request.timeout.inMilliseconds),
        reason: 'anything routed here at the default timeout always falls back',
      );
    });
  });
}
