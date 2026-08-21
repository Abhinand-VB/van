import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backends/mock_backend.dart';
import 'package:van/inference/goldens.dart';
import 'package:van/inference/router.dart';

import '../support/prompts.dart';

void main() {
  GoldenSet loadExtractTask() => GoldenSet.fromJson(
    File('test/golden/extract_task.json').readAsStringSync(),
  );

  group('the golden set itself', () {
    test('has enough cases to mean something', () {
      // ARCHITECTURE section 5 asks for 25-30 per capability. Fewer and a
      // single lucky heuristic can carry the whole score.
      expect(loadExtractTask().cases.length, greaterThanOrEqualTo(25));
    });

    test('every case checks something', () {
      for (final testCase in loadExtractTask().cases) {
        expect(
          testCase.expect,
          isNotEmpty,
          reason: '"${testCase.name}" asserts nothing',
        );
      }
    });

    test('case names are unique, so failures can be found', () {
      final names = loadExtractTask().cases.map((c) => c.name).toList();
      expect(names.toSet(), hasLength(names.length));
    });
  });

  group('the deterministic parser, which is what ships', () {
    test('clears the gate it would have to clear to be replaced', () async {
      // No model configured, so every call falls back to the parser. This is
      // the number a candidate model has to beat, and it is measured by the
      // same runner rather than asserted from memory.
      final report = await GoldenRunner(
        prompts: testPrompts(),
        InferenceRouter(defaultBackend: MockBackend(available: false)),
      ).run(loadExtractTask());

      expect(report.clearsGate, isTrue, reason: '\n${report.describe()}');
    });

    test('scores the same on every run', () async {
      Future<double> score() async => (await GoldenRunner(
        prompts: testPrompts(),
        InferenceRouter(defaultBackend: MockBackend(available: false)),
      ).run(loadExtractTask())).passRate;

      expect(await score(), await score());
    });
  });

  group('the runner', () {
    test('reports a failing model rather than hiding it', () async {
      // A backend answering confidently and wrongly is the case the gate
      // exists for. It must show up as a low score, not as an exception.
      final backend = MockBackend()
        ..replyToAll('{"title": "Wrong", "estimatedMinutes": 1}');

      final report = await GoldenRunner(
        prompts: testPrompts(),
        InferenceRouter(defaultBackend: backend),
      ).run(loadExtractTask());

      expect(report.clearsGate, isFalse);
      expect(report.passed, lessThan(report.total));
      expect(report.describe(), contains('BELOW the 80% gate'));
    });

    test('names the field that disagreed', () async {
      final backend = MockBackend()
        ..replyToAll('{"title": "Wrong", "estimatedMinutes": 1}');

      final report = await GoldenRunner(
        prompts: testPrompts(),
        InferenceRouter(defaultBackend: backend),
      ).run(loadExtractTask());

      expect(report.describe(), contains('wanted'));
      expect(report.describe(), contains('got'));
    });

    test('a garbled model falls back and still scores', () async {
      // Falling back is not failing. The router substitutes the parser, so
      // this measures what the user would actually get.
      final backend = MockBackend()..replyToAll('sorry, I cannot help');

      final report = await GoldenRunner(
        prompts: testPrompts(),
        InferenceRouter(defaultBackend: backend),
      ).run(loadExtractTask());

      expect(report.clearsGate, isTrue, reason: '\n${report.describe()}');
    });

    test('refuses a set it has no runner for', () async {
      final unknown = GoldenSet(
        capability: 'compose_nudge',
        now: DateTime.utc(2026, 8, 19, 9),
        cases: const [],
      );
      expect(
        () => GoldenRunner(
          InferenceRouter(defaultBackend: MockBackend()),
          prompts: testPrompts(),
        ).run(unknown),
        throwsUnsupportedError,
      );
    });
  });
}
