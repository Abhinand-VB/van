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

/// Remembers how the last routed call was actually served.
///
/// **Without this a phone run measures the wrong thing.** `InferenceRouter`
/// guarantees an answer: when the model is missing, slow or malformed, the
/// capability's deterministic fallback runs and the caller cannot tell. Point
/// the golden set at a real model with no observer and every case the model
/// failed is scored as a pass, because the parser answered it - a report
/// saying 29/29 about a model that produced nothing. See
/// `DECISIONS_PENDING.md` D85.
class LastInference implements InferenceObserver {
  /// Whether a backend, rather than the fallback, produced the last answer.
  bool viaModel = false;

  /// How long the last attempt took, including a failed one.
  int? latencyMs;

  /// Why the last attempt fell back, when it did.
  String? failureReason;

  @override
  void onInference({
    required String capabilityId,
    required String backendId,
    required InferenceOutcome outcome,
    String? failureReason,
    int? latencyMs,
  }) {
    viaModel = outcome == InferenceOutcome.model;
    this.latencyMs = latencyMs;
    this.failureReason = failureReason;
  }
}

/// What happened to one case.
@immutable
class GoldenOutcome {
  /// Creates an outcome.
  const GoldenOutcome({
    required this.name,
    required this.failures,
    this.viaModel = false,
    this.latencyMs,
    this.failureReason,
  });

  /// Reads one back from [toJson].
  factory GoldenOutcome.fromJson(Map<String, dynamic> json) => GoldenOutcome(
    name: json['name'] as String,
    failures: [for (final f in json['failures'] as List<dynamic>) f as String],
    viaModel: json['viaModel'] as bool? ?? false,
    latencyMs: json['latencyMs'] as int?,
    failureReason: json['failureReason'] as String?,
  );

  /// The case's name.
  final String name;

  /// One line per expectation that did not hold. Empty means it passed.
  final List<String> failures;

  /// Whether a backend answered this case, or the fallback did.
  ///
  /// False for every case in CI, which runs with no backend at all, and that
  /// is correct: nothing there is measuring a model.
  final bool viaModel;

  /// How long the attempt took, when a runner was watching.
  final int? latencyMs;

  /// Why it fell back, when it did.
  final String? failureReason;

  /// Whether every expectation held.
  bool get passed => failures.isEmpty;

  /// A form that survives the app being killed part-way through a run.
  Map<String, Object?> toJson() => {
    'name': name,
    'failures': failures,
    'viaModel': viaModel,
    'latencyMs': latencyMs,
    'failureReason': failureReason,
  };
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

  /// How many cases a backend actually answered.
  int get answeredByModel => outcomes.where((o) => o.viaModel).length;

  /// How many cases a backend answered **and** got right.
  int get passedViaModel =>
      outcomes.where((o) => o.viaModel && o.passed).length;

  /// The model's share of the whole set, 0..1.
  ///
  /// **Over the whole set, not over the cases it managed to answer.** A model
  /// that answers four sentences perfectly and falls back on the other
  /// twenty-five has not scored 100%: it contributed to four cases out of
  /// twenty-nine and the parser did the rest.
  double get modelPassRate => total == 0 ? 0 : passedViaModel / total;

  /// Whether a *model* clears the gate, which is the question 3e asks.
  ///
  /// [clearsGate] answers a different one, and is the number CI watches: it
  /// counts every case the fallback rescued, which is the right measure of
  /// "does Van answer correctly" and the wrong measure of "is this model
  /// worth routing to".
  bool get modelClearsGate => modelPassRate >= 0.8;

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
  ///
  /// Pass [watching] the same [LastInference] the router was given and every
  /// outcome records whether a model or the fallback produced it.
  const GoldenRunner(this.router, {required this.prompts, this.watching});

  /// The observer the router reports to, when the caller installed one.
  final LastInference? watching;

  /// The prompts a real backend would be sent. Irrelevant to the fallback,
  /// which is why CI passes them and never notices - but a measurement of a
  /// model that used different prompts than production would be worthless.
  final Prompts prompts;

  /// Routes each case to the configured backend, falling back as normal.
  final InferenceRouter router;

  /// Runs every case in [set] that is not already in [done].
  ///
  /// [done], [onOutcome] and [stop] exist for the phone, where one case costs
  /// minutes rather than microseconds and the app can be killed part-way
  /// through. CI passes none of them and behaves exactly as it did.
  Future<GoldenReport> run(
    GoldenSet set, {
    List<GoldenOutcome> done = const [],
    Future<void> Function(GoldenOutcome outcome)? onOutcome,
    bool Function()? stop,
  }) async {
    if (set.capability != 'extract_task') {
      throw UnsupportedError(
        'no runner for "${set.capability}". Add one here rather than in the '
        'tool, so CI and the manual harness stay the same code.',
      );
    }

    final outcomes = [...done];
    final finished = {for (final outcome in done) outcome.name};
    for (final testCase in set.cases) {
      if (finished.contains(testCase.name)) continue;
      if (stop?.call() ?? false) break;

      watching
        ?..viaModel = false
        ..latencyMs = null
        ..failureReason = null;
      final draft = await router.run(
        ExtractTask(prompt: prompts.extractTask),
        ExtractTaskInput(testCase.input, now: set.now),
      );
      final outcome = GoldenOutcome(
        name: testCase.name,
        failures: _checkDraft(draft, testCase.expect),
        viaModel: watching?.viaModel ?? false,
        latencyMs: watching?.latencyMs,
        failureReason: watching?.failureReason,
      );
      outcomes.add(outcome);
      await onOutcome?.call(outcome);
    }

    // File order, not finish order: a run that was resumed must read exactly
    // like one that was never interrupted.
    final byName = {for (final outcome in outcomes) outcome.name: outcome};
    return GoldenReport(
      capability: set.capability,
      outcomes: [
        for (final testCase in set.cases) ?byName[testCase.name],
      ],
    );
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
