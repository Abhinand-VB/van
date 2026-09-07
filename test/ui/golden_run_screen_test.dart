import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/golden_run_store.dart';
import 'package:van/inference/goldens.dart';
import 'package:van/ui/golden_run_screen.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_local_llm.dart';
import '../support/prompts.dart';

/// A store that keeps the run in memory.
///
/// Real file I/O inside `pumpAndSettle` deadlocks the test binding, and the
/// screen's job is not to write files - it is to save after every case, which
/// this asserts just as well.
class _MemoryStore implements GoldenRunStore {
  GoldenRun? saved;

  @override
  Future<GoldenRun?> read(String capability) async => saved;

  @override
  Future<void> write(GoldenRun run) async => saved = run;

  @override
  Future<void> clear(String capability) async => saved = null;
}

void main() {
  late FakeLocalLlm llm;
  late _MemoryStore store;

  /// Two cases, so a run is short enough to drive in a widget test.
  const set = '''
{
  "capability": "extract_task",
  "now": "2026-08-19T09:00:00Z",
  "cases": [
    {"name": "plain", "input": "write the report 45 minutes",
     "expect": {"estimatedMinutes": 45}},
    {"name": "second", "input": "call the bank 20 minutes",
     "expect": {"estimatedMinutes": 20}}
  ]
}
''';

  setUp(() {
    llm = FakeLocalLlm();
    store = _MemoryStore();
  });

  Widget screen() => MaterialApp(
    home: GoldenRunScreen(
      llm: llm,
      prompts: testPrompts(),
      store: store,
      clock: FakeClock(DateTime.utc(2026, 9, 7, 4)),
      loadAsset: (_) async => set,
    ),
  );

  group('what it says before anything has run', () {
    testWidgets('nothing measured, and nothing claimed', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text('0 of 2 measured'), findsOneWidget);
      expect(find.textContaining('below the 80% gate'), findsOneWidget);
      expect(find.text('Run the set'), findsOneWidget);
    });
  });

  group('a model that answers nothing', () {
    testWidgets('scores zero however well the parser does', (tester) async {
      // The failure this screen exists to make impossible to miss. The
      // engine is absent, so the parser answers both cases correctly - and
      // the model must still read as having contributed nothing.
      llm.available = false;

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run the set'));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2 measured'), findsOneWidget);
      expect(
        find.textContaining('The model answered 0 and got 0 of those right'),
        findsOneWidget,
      );
      expect(find.textContaining('0% of the whole set'), findsOneWidget);
      expect(find.textContaining('below the 80% gate'), findsOneWidget);
      // And it says so plainly rather than hiding it: Van itself got both.
      expect(
        find.textContaining('Van itself would have got 2 of 2 right'),
        findsOneWidget,
      );
    });
  });

  group('a model that answers', () {
    testWidgets('is credited only for what it got right', (tester) async {
      // First case answered correctly by the model, second one refused.
      llm.replies = [
        jsonEncode({'title': 'Write the report', 'estimatedMinutes': 45}),
        null,
      ];

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run the set'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The model answered 1 and got 1 of those right'),
        findsOneWidget,
      );
      // One of two is 50%, not 100%: the denominator is the set, not the
      // cases it managed to answer.
      expect(find.textContaining('50% of the whole set'), findsOneWidget);
    });
  });

  group('surviving the phone', () {
    testWidgets('every case is saved before the next one starts', (
      tester,
    ) async {
      llm.available = false;

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run the set'));
      await tester.pumpAndSettle();

      final saved = await store.read('extract_task');
      expect(saved, isNotNull);
      expect(saved!.outcomes, hasLength(2));
      expect(saved.startedAt, DateTime.utc(2026, 9, 7, 4));
    });

    testWidgets('a part-finished run is offered, not restarted', (
      tester,
    ) async {
      final prompts = testPrompts().extractTask;
      await store.write(
        GoldenRun(
          capability: 'extract_task',
          promptFingerprint: GoldenRun.fingerprint(
            '${prompts.system}\n${prompts.prompt}',
          ),
          startedAt: DateTime.utc(2026, 9, 7, 3),
          outcomes: const [GoldenOutcome(name: 'plain', failures: [])],
        ),
      );

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 measured'), findsOneWidget);
      expect(find.text('Continue — 1 left'), findsOneWidget);
      expect(find.text('Start over'), findsOneWidget);
    });

    testWidgets('a run against a different prompt is dropped', (tester) async {
      await store.write(
        GoldenRun(
          capability: 'extract_task',
          promptFingerprint: GoldenRun.fingerprint('some older prompt'),
          startedAt: DateTime.utc(2026, 9, 7, 3),
          outcomes: const [GoldenOutcome(name: 'plain', failures: [])],
        ),
      );

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      // An hour of measurement thrown away, deliberately: half a run against
      // one prompt and half against another describes neither.
      expect(find.text('0 of 2 measured'), findsOneWidget);
      expect(find.text('Run the set'), findsOneWidget);
    });
  });
}
