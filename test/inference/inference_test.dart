import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/backends/mock_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/parsing.dart';
import 'package:van/inference/router.dart';
import 'package:van_core/van_core.dart';

final now = DateTime.utc(2026, 8, 19, 9);

NudgeTemplates loadTemplates({int seed = 7}) => NudgeTemplates.fromJson(
  File('assets/nudge_templates/templates.json').readAsStringSync(),
  random: Random(seed),
);

class _RecordingObserver implements InferenceObserver {
  final calls = <String>[];

  @override
  void onInference({
    required String capabilityId,
    required String backendId,
    required InferenceOutcome outcome,
    String? failureReason,
    int? latencyMs,
  }) {
    calls.add(
      '$capabilityId/$backendId/${outcome.name}/${failureReason ?? "-"}',
    );
  }
}

void main() {
  group('JsonSalvage', () {
    test('reads a bare object', () {
      expect(JsonSalvage.extractObject('{"a": 1}'), {'a': 1});
    });

    test('strips markdown fences', () {
      expect(
        JsonSalvage.extractObject('```json\n{"a": 1}\n```'),
        {'a': 1},
      );
    });

    test('ignores leading and trailing prose', () {
      expect(
        JsonSalvage.extractObject(
          'Sure! Here you go:\n{"a": 1}\nHope that helps.',
        ),
        {'a': 1},
      );
    });

    test('keeps nested objects intact', () {
      final json = JsonSalvage.extractObject('{"a": {"b": 2}, "c": 3}');
      expect(json!['a'], {'b': 2});
      expect(json['c'], 3);
    });

    test('is not fooled by braces inside strings', () {
      final json = JsonSalvage.extractObject('{"a": "not } the end", "b": 1}');
      expect(json!['b'], 1);
    });

    test('handles escaped quotes inside strings', () {
      final json = JsonSalvage.extractObject(r'{"a": "say \"hi\"", "b": 2}');
      expect(json!['b'], 2);
    });

    test('returns null on truncated output', () {
      expect(JsonSalvage.extractObject('{"a": 1, "b":'), isNull);
    });

    test('returns null when there is no object at all', () {
      expect(JsonSalvage.extractObject('I could not do that.'), isNull);
    });

    test('coerces a stringified int', () {
      expect(JsonSalvage.readInt({'m': '45'}, 'm'), 45);
      expect(JsonSalvage.readInt({'m': 45.0}, 'm'), 45);
      expect(JsonSalvage.readInt({'m': 'lots'}, 'm'), isNull);
    });

    test('treats blank strings as absent', () {
      expect(JsonSalvage.readString({'t': '   '}, 't'), isNull);
    });

    test('reads an enum case-insensitively', () {
      expect(
        JsonSalvage.readEnum({'p': 'HIGH'}, 'p', const ['low', 'high']),
        'high',
      );
      expect(
        JsonSalvage.readEnum({'p': 'urgent'}, 'p', const ['low', 'high']),
        isNull,
      );
    });
  });

  group('NudgeTemplates', () {
    test('every level has at least eight variants', () {
      final templates = loadTemplates();
      const keys = [
        'sessionStart_l0Gentle',
        'sessionMissed_l0Gentle',
        'sessionMissed_l1Check',
        'sessionMissed_l2Diagnose',
        'sessionMissed_l3Shrink',
        'sessionMissed_l4Renegotiate',
        'sessionMissed_l5Concede',
      ];
      for (final key in keys) {
        expect(
          templates.variantCount(key),
          greaterThanOrEqualTo(8),
          reason: '$key has too few variants',
        );
      }
    });

    test('fills every placeholder', () {
      final copy = loadTemplates().pick(
        const NudgeCopyRequest(
          type: NudgeType.sessionMissed,
          level: InterventionLevel.l4Renegotiate,
          taskTitle: 'Database assignment',
          minutes: 45,
          minutesLate: 20,
          moves: 3,
        ),
      );
      expect(copy.text, isNot(contains('{')));
      expect(copy.templateId, isNotNull);
    });

    test('never repeats within a window of two', () {
      final templates = loadTemplates();
      const request = NudgeCopyRequest(
        type: NudgeType.sessionMissed,
        level: InterventionLevel.l1Check,
        taskTitle: 'Assignment',
      );

      final seen = <String>[];
      for (var i = 0; i < 20; i++) {
        final text = templates.pick(request).text;
        expect(
          seen.length < 2 ? <String>[] : seen.sublist(seen.length - 2),
          isNot(contains(text)),
          reason: 'repeated too soon at call $i',
        );
        seen.add(text);
      }
      // And it genuinely varies rather than alternating between two.
      expect(seen.toSet().length, greaterThanOrEqualTo(4));
    });

    test('an unknown key still produces something usable', () {
      final templates = NudgeTemplates({}, random: Random(1));
      final copy = templates.pick(
        const NudgeCopyRequest(
          type: NudgeType.hydration,
          level: InterventionLevel.l0Gentle,
          taskTitle: 'Water',
        ),
      );
      expect(copy.text, isNotEmpty);
    });
  });

  group('ExtractTask', () {
    const capability = ExtractTask();

    test('parses well-formed model output', () {
      final draft = capability.parse(
        '{"title": "Finish report", "deadline": "2026-08-21T23:59:00Z", '
        '"estimatedMinutes": 120, "priority": "high"}',
      );
      expect(draft!.title, 'Finish report');
      expect(draft.deadline, DateTime.utc(2026, 8, 21, 23, 59));
      expect(draft.estimatedMinutes, 120);
      expect(draft.priority, Priority.high);
    });

    test('rejects output with no title', () {
      expect(capability.parse('{"estimatedMinutes": 60}'), isNull);
    });

    test('treats a nonsense duration as unstated', () {
      final draft = capability.parse('{"title": "X", "estimatedMinutes": 0}');
      expect(draft!.estimatedMinutes, isNull);
    });

    test('falls back to the heuristic parser', () {
      final draft = capability.fallback(
        ExtractTaskInput('finish the assignment by friday 2 hours', now: now),
      );
      expect(draft.title, 'Finish the assignment');
      expect(draft.estimatedMinutes, 120);
      expect(draft.deadline, DateTime.utc(2026, 8, 21, 23, 59));
    });

    test('asks for native structured output only when supported', () {
      const withNative = BackendCapabilities(
        supportsNativeStructuredOutput: true,
      );
      const without = BackendCapabilities();
      final input = ExtractTaskInput('x', now: now);

      expect(capability.buildRequest(input, withNative).jsonSchema, isNotNull);
      final plain = capability.buildRequest(input, without);
      expect(plain.jsonSchema, isNull);
      // Without native support the schema has to travel in the prompt.
      expect(plain.prompt, contains('"title"'));
    });
  });

  group('InferenceRouter', () {
    late MockBackend backend;
    late _RecordingObserver observer;
    late InferenceRouter router;

    setUp(() {
      backend = MockBackend();
      observer = _RecordingObserver();
      router = InferenceRouter(defaultBackend: backend, observer: observer);
    });

    test('uses the model when it answers correctly', () async {
      backend.replyToAll('{"title": "From the model"}');
      final draft = await router.run(
        const ExtractTask(),
        ExtractTaskInput('anything', now: now),
      );
      expect(draft.title, 'From the model');
      expect(observer.calls.single, contains('/model/'));
    });

    test('falls back when the backend is unavailable', () async {
      backend.goOffline();
      final draft = await router.run(
        const ExtractTask(),
        ExtractTaskInput('buy milk', now: now),
      );
      expect(draft.title, 'Buy milk');
      expect(observer.calls.single, contains('/fallback/unavailable'));
    });

    test('falls back on every declared failure kind', () async {
      for (final kind in LlmFailureKind.values) {
        final mock = MockBackend()..failEverything(kind);
        final only = InferenceRouter(defaultBackend: mock);
        final draft = await only.run(
          const ExtractTask(),
          ExtractTaskInput('buy milk', now: now),
        );
        expect(draft.title, 'Buy milk', reason: 'failed for ${kind.name}');
      }
    });

    test('falls back when the model returns unparseable text', () async {
      backend.replyToAll('I am terribly sorry, I cannot help with that.');
      final draft = await router.run(
        const ExtractTask(),
        ExtractTaskInput('buy milk', now: now),
      );
      expect(draft.title, 'Buy milk');
      expect(observer.calls.single, contains('/fallback/malformed'));
    });

    test('a backend that throws does not take the app down', () async {
      final router = InferenceRouter(defaultBackend: _ExplodingBackend());
      final draft = await router.run(
        const ExtractTask(),
        ExtractTaskInput('buy milk', now: now),
      );
      expect(draft.title, 'Buy milk');
    });

    test('routes per capability, not globally', () {
      final other = MockBackend(id: 'other');
      final routed = InferenceRouter(
        defaultBackend: backend,
        byCapabilityId: {'compose_nudge': other},
      );
      expect(routed.backendFor('compose_nudge').id, 'other');
      expect(routed.backendFor('extract_task').id, 'mock');
    });
  });

  group('the decisive offline test', () {
    test('everything still works with every model call failing', () async {
      // This is the property the whole design rests on: pull the model out
      // entirely and Van still captures work, plans it, and writes varied
      // nudge copy. If this ever fails, "offline-first" has become a slogan.
      final dead = MockBackend()..failEverything();
      final router = InferenceRouter(defaultBackend: dead);
      final templates = loadTemplates();

      // 1. Capture from a real sentence.
      final draft = await router.run(
        const ExtractTask(),
        ExtractTaskInput(
          'I need to finish my database assignment by friday, 4 hours',
          now: now,
        ),
      );
      expect(draft.title, 'Finish my database assignment');
      expect(draft.estimatedMinutes, 240);
      expect(draft.deadline, DateTime.utc(2026, 8, 21, 23, 59));

      // 2. Plan it into sessions.
      final task = Task(
        id: 't1',
        title: draft.title,
        createdAt: now,
        deadline: draft.deadline,
        estimatedMinutes: draft.estimatedMinutes,
      );
      final slots =
          const FreeSlotFinder(
            waking: WakingHours(utcOffset: Duration.zero),
          ).find(
            commitments: const [],
            from: now,
            to: now.add(const Duration(days: 3)),
          );
      final planned = SessionPlanner(
        ids: SequentialIds('s'),
        waking: const WakingHours(utcOffset: Duration.zero),
      ).plan(task: task, slots: slots, clock: FakeClock(now));
      expect(planned.isOk, isTrue, reason: 'planning failed offline');
      expect(planned.okOrNull!.length, greaterThan(1));

      // 3. Decide a nudge.
      const engine = NudgeEngine(
        suppression: SuppressionPolicy(
          waking: WakingHours(utcOffset: Duration.zero),
        ),
      );
      final session = planned.okOrNull!.first;
      final decisions = engine.tick(
        session.plannedStart.add(const Duration(minutes: 12)),
        engineStateFor(session, task),
      );
      final live = decisions.where((d) => d.willDeliver).toList();
      expect(live, hasLength(1));
      expect(live.single.level, InterventionLevel.l1Check);

      // 4. Write the words for it, twice, and get different lines.
      final capability = ComposeNudge(templates);
      final texts = <String>{};
      for (var i = 0; i < 4; i++) {
        final copy = await InferenceRouter(defaultBackend: dead).run(
          capability,
          NudgeCopyRequest(
            type: live.single.type,
            level: live.single.level,
            taskTitle: task.title,
            minutesLate: 12,
          ),
        );
        expect(copy.text, isNotEmpty);
        expect(
          copy.templateId,
          isNotNull,
          reason: 'should be template-sourced',
        );
        texts.add(copy.text);
      }
      expect(texts.length, greaterThan(1), reason: 'copy repeated itself');
    });
  });
}

/// Builds the engine state for a single session under test.
NudgeEngineState engineStateFor(WorkSession session, Task task) =>
    NudgeEngineState(
      sessions: [SessionContext(session: session, task: task)],
    );

class _ExplodingBackend implements LlmBackend {
  @override
  String get id => 'exploding';

  @override
  BackendCapabilities get capabilities => const BackendCapabilities();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<LlmResult> generate(LlmRequest request) async =>
      throw StateError('backend is broken');

  @override
  Stream<String> generateStream(LlmRequest request) =>
      throw StateError('backend is broken');

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> dispose() async {}
}
