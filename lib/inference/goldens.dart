import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/inference/router.dart';
import 'package:van_core/van_core.dart';

/// One golden case: a sentence, and the smallest assertion that would catch
/// the capability getting it wrong.
@immutable
class GoldenCase {
  /// Creates a case.
  const GoldenCase({
    required this.name,
    required this.input,
    required this.expect,
  });

  /// What this case is checking, used in failure output.
  final String name;

  /// The sentence a user would have typed.
  final String input;

  /// Fields to check. Anything absent is deliberately not checked.
  final Map<String, Object?> expect;
}

/// A parsed golden file.
@immutable
class GoldenSet {
  /// Creates a set.
  const GoldenSet({
    required this.capability,
    required this.now,
    required this.cases,
  });

  /// Reads the format used under `test/golden/`.
  factory GoldenSet.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return GoldenSet(
      capability: json['capability'] as String,
      now: DateTime.parse(json['now'] as String).toUtc(),
      cases: [
        for (final raw in json['cases'] as List<dynamic>)
          GoldenCase(
            name: (raw as Map<String, dynamic>)['name'] as String,
            input: raw['input'] as String,
            expect: Map<String, Object?>.from(
              raw['expect'] as Map<String, dynamic>,
            ),
          ),
      ],
    );
  }

  /// Which capability these cases exercise.
  final String capability;

  /// The instant the sentences were typed, so relative dates resolve.
  final DateTime now;

  /// The cases, in file order.
  final List<GoldenCase> cases;
}

/// What happened to one case.
@immutable
class GoldenOutcome {
  /// Creates an outcome.
  const GoldenOutcome({required this.name, required this.failures});

  /// The case's name.
  final String name;

  /// One line per expectation that did not hold. Empty means it passed.
  final List<String> failures;

  /// Whether every expectation held.
  bool get passed => failures.isEmpty;
}

/// The result of running a whole set.
@immutable
class GoldenReport {
  /// Creates a report.
  const GoldenReport({required this.capability, required this.outcomes});

  /// Which capability was measured.
  final String capability;

  /// One outcome per case, in file order.
  final List<GoldenOutcome> outcomes;

  /// How many cases passed.
  int get passed => outcomes.where((o) => o.passed).length;

  /// How many cases there were.
  int get total => outcomes.length;

  /// Share of cases that passed, 0..1.
  double get passRate => total == 0 ? 0 : passed / total;

  /// Whether this clears the WP-6 routing gate.
  ///
  /// 80% is from STATUS section 6 and it is not arbitrary: below it the model
  /// is worse than the deterministic parser it would be replacing, and
  /// switching would be a downgrade dressed as progress.
  bool get clearsGate => passRate >= 0.8;

  /// A readable summary, for CI output and for `tool/run_goldens.dart`.
  String describe({bool verbose = false}) {
    final buffer = StringBuffer()
      ..writeln(
        '$capability: $passed/$total '
        '(${(passRate * 100).toStringAsFixed(1)}%) '
        '${clearsGate ? 'clears' : 'BELOW'} the 80% gate',
      );
    for (final outcome in outcomes) {
      if (outcome.passed && !verbose) continue;
      buffer.writeln('  ${outcome.passed ? 'ok  ' : 'FAIL'} ${outcome.name}');
      for (final failure in outcome.failures) {
        buffer.writeln('        $failure');
      }
    }
    return buffer.toString();
  }
}

/// Runs a golden set against whatever backend [router] is configured with.
///
/// The same code path CI uses against the deterministic parser and
/// `tool/run_goldens.dart` uses against a real model. That sameness is the
/// point: a measurement taken by a different harness than the one that gates
/// the change is not a measurement of the change.
class GoldenRunner {
  /// Creates a runner over [router].
  const GoldenRunner(this.router, {required this.prompts});

  /// The prompts a real backend would be sent. Irrelevant to the fallback,
  /// which is why CI passes them and never notices - but a measurement of a
  /// model that used different prompts than production would be worthless.
  final Prompts prompts;

  /// Routes each case to the configured backend, falling back as normal.
  final InferenceRouter router;

  /// Runs every case in [set].
  Future<GoldenReport> run(GoldenSet set) async {
    if (set.capability != 'extract_task') {
      throw UnsupportedError(
        'no runner for "${set.capability}". Add one here rather than in the '
        'tool, so CI and the manual harness stay the same code.',
      );
    }

    final outcomes = <GoldenOutcome>[];
    for (final testCase in set.cases) {
      final draft = await router.run(
        ExtractTask(prompt: prompts.extractTask),
        ExtractTaskInput(testCase.input, now: set.now),
      );
      outcomes.add(
        GoldenOutcome(
          name: testCase.name,
          failures: _checkDraft(draft, testCase.expect),
        ),
      );
    }
    return GoldenReport(capability: set.capability, outcomes: outcomes);
  }

  /// Checks only the fields the case actually names.
  static List<String> _checkDraft(
    TaskDraft draft,
    Map<String, Object?> expected,
  ) {
    final failures = <String>[];

    void compare(String field, Object? want, Object? got) {
      if (want != got) failures.add('$field: wanted $want, got $got');
    }

    for (final entry in expected.entries) {
      switch (entry.key) {
        case 'title':
          compare('title', entry.value, draft.title);
        case 'titleContains':
          final needle = (entry.value! as String).toLowerCase();
          if (!draft.title.toLowerCase().contains(needle)) {
            failures.add(
              'title: wanted something containing "$needle", '
              'got "${draft.title}"',
            );
          }
        case 'titleIsNotEmpty':
          if (draft.title.trim().isEmpty) {
            failures.add('title: wanted something, got an empty string');
          }
        case 'deadline':
          final want = entry.value == null
              ? null
              : DateTime.parse(entry.value! as String).toUtc();
          compare('deadline', want, draft.deadline);
        case 'estimatedMinutes':
          compare('estimatedMinutes', entry.value, draft.estimatedMinutes);
        case 'priority':
          compare('priority', entry.value, draft.priority.name);
        default:
          failures.add('unknown expectation "${entry.key}"');
      }
    }
    return failures;
  }
}
