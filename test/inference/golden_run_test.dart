import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/golden_run_store.dart';
import 'package:van/inference/goldens.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/inference/router.dart';

import '../support/prompts.dart';

/// A backend that answers the first [answers] calls and then stops existing.
///
/// Stands in for the phone: a model that works, and then does not.
class _FlakyBackend implements LlmBackend {
  _FlakyBackend({required this.answers, required this.reply});

  int answers;
  final String reply;
  int calls = 0;

  @override
  String get id => 'flaky';

  @override
  BackendCapabilities get capabilities =>
      const BackendCapabilities(isLocal: true);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<LlmResult> generate(LlmRequest request) async {
    calls++;
    if (calls > answers) {
      return const LlmFailure(LlmFailureKind.timeout, 'gone');
    }
    return LlmOk(reply);
  }

  @override
  Stream<String> generateStream(LlmRequest request) =>
      throw UnsupportedError('not streamed');

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  late GoldenSet set;
  late Prompts prompts;

  setUpAll(() async {
    set = GoldenSet.fromJson(
      File('test/golden/extract_task.json').readAsStringSync(),
    );
    prompts = testPrompts();
  });

  group('a run that a model did not actually do', () {
    test('scores zero for the model even when every case passes', () async {
      // The trap this whole design exists for. No backend at all, so the
      // parser answers all 29 - and the parser is very good, so the naive
      // reading is "29/29, ship it".
      final report = await GoldenRunner(
        InferenceRouter(defaultBackend: _FlakyBackend(answers: 0, reply: '')),
        prompts: prompts,
        watching: LastInference(),
      ).run(set);

      expect(report.passed, greaterThan(20), reason: 'the parser is good');
      expect(report.answeredByModel, 0);
      expect(report.passedViaModel, 0);
      expect(report.modelPassRate, 0);
      expect(report.modelClearsGate, isFalse);
      // And the number CI watches is unchanged by any of this.
      expect(report.clearsGate, isTrue);
    });

    test('without an observer nothing claims the model did anything', () async {
      // CI passes no observer. Every outcome must read as "not the model"
      // rather than defaulting the other way.
      final report = await GoldenRunner(
        InferenceRouter(defaultBackend: _FlakyBackend(answers: 99, reply: '')),
        prompts: prompts,
      ).run(set);

      expect(report.outcomes.every((o) => !o.viaModel), isTrue);
    });
  });

  group('resuming', () {
    test('skips what is done and keeps file order', () async {
      final first = set.cases.first.name;
      final done = [
        GoldenOutcome(name: first, failures: const ['stale'], viaModel: true),
      ];
      final backend = _FlakyBackend(answers: 99, reply: '');

      final report = await GoldenRunner(
        InferenceRouter(defaultBackend: backend),
        prompts: prompts,
      ).run(set, done: done);

      expect(report.total, set.cases.length);
      // The saved outcome was kept, not re-run: 28 calls, not 29.
      expect(backend.calls, set.cases.length - 1);
      expect(report.outcomes.first.name, first);
      expect(report.outcomes.first.failures, ['stale']);
      // Order is the file's, so a resumed report reads like an uninterrupted
      // one.
      expect(
        report.outcomes.map((o) => o.name),
        set.cases.map((c) => c.name),
      );
    });

    test('stopping leaves a short report rather than a wrong one', () async {
      var seen = 0;
      final report = await GoldenRunner(
        InferenceRouter(defaultBackend: _FlakyBackend(answers: 0, reply: '')),
        prompts: prompts,
      ).run(set, stop: () => seen >= 3, onOutcome: (_) async => seen++);

      expect(report.total, 3);
      // 3 of 29 measured is not a pass rate over 29, and must not read as one.
      expect(report.passRate, 1.0);
      expect(report.modelPassRate, 0);
    });
  });

  group('the store', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('van-golden'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('a run survives a round trip', () async {
      final store = FileGoldenRunStore(directory.path);
      final run = GoldenRun(
        capability: 'extract_task',
        promptFingerprint: GoldenRun.fingerprint('a prompt'),
        startedAt: DateTime.utc(2026, 9, 7, 4),
        outcomes: const [
          GoldenOutcome(
            name: 'one',
            failures: [],
            viaModel: true,
            latencyMs: 164990,
          ),
          GoldenOutcome(
            name: 'two',
            failures: ['title: wanted x, got y'],
            failureReason: 'malformed',
          ),
        ],
      );

      await store.write(run);
      final read = await store.read('extract_task');

      expect(read, isNotNull);
      expect(read!.outcomes, hasLength(2));
      expect(read.outcomes.first.viaModel, isTrue);
      expect(read.outcomes.first.latencyMs, 164990);
      expect(read.outcomes.last.viaModel, isFalse);
      expect(read.outcomes.last.failureReason, 'malformed');
      expect(read.startedAt, run.startedAt);
    });

    test('a run measured against another prompt is not resumed', () async {
      final store = FileGoldenRunStore(directory.path);
      await store.write(
        GoldenRun(
          capability: 'extract_task',
          promptFingerprint: GoldenRun.fingerprint('the old prompt'),
          startedAt: DateTime.utc(2026, 9, 7),
          outcomes: const [],
        ),
      );

      final read = await store.read('extract_task');

      expect(read!.matches('the old prompt'), isTrue);
      // Half a run against one prompt and half against another measures
      // neither, so the screen throws it away rather than continuing it.
      expect(read.matches('a rewritten prompt'), isFalse);
    });

    test('a corrupt file costs the run, not the screen', () async {
      File(
        '${directory.path}/golden-run-extract_task.json',
      ).writeAsStringSync('{not json');

      expect(
        await FileGoldenRunStore(directory.path).read('extract_task'),
        isNull,
      );
    });

    test('nothing saved reads as nothing saved', () async {
      expect(
        await FileGoldenRunStore(directory.path).read('extract_task'),
        isNull,
      );
    });
  });
}
