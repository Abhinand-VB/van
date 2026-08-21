import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/prompts.dart';
import 'package:van_core/van_core.dart';

import '../support/prompts.dart';

void main() {
  /// Every `{placeholder}` a prompt asks to have filled.
  Set<String> slotsIn(String text) => RegExp(
    r'\{([a-zA-Z]+)\}',
  ).allMatches(text).map((m) => m.group(1)!).toSet();

  group('the prompt assets', () {
    test('all exist', () {
      for (final name in Prompts.all) {
        expect(
          File('assets/prompts/$name').existsSync(),
          isTrue,
          reason: 'assets/prompts/$name is missing',
        );
      }
    });

    test('are declared in pubspec so a release build ships them', () {
      // A prompt that loads in tests off disk and is absent from the bundle
      // would fail only on a real device, at the first model call.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/prompts/'));
    });

    test('each splits into a system half and a prompt half', () {
      final prompts = testPrompts();
      for (final template in [
        prompts.extractTask,
        prompts.composeNudge,
        prompts.negotiate,
      ]) {
        expect(template.system, isNotEmpty);
        expect(template.prompt, isNotEmpty);
      }
    });

    test('load through the same path main.dart uses', () async {
      final loaded = await Prompts.load(
        (path) async => File(path).readAsString(),
      );
      expect(loaded.extractTask.system, isNotEmpty);
      expect(loaded.negotiate.prompt, contains('{task}'));
    });

    test('a malformed asset degrades instead of throwing', () {
      final parsed = PromptTemplate.parse('just some text');
      expect(parsed.system, isEmpty);
      expect(parsed.prompt, 'just some text');
    });
  });

  group('placeholders match the code that fills them', () {
    // The failure this catches: renaming a slot in the asset, or adding one,
    // and shipping a prompt that reaches the model with a literal "{task}" in
    // it. Nothing else would notice - the deterministic fallback does not read
    // the prompt at all, so every test would stay green.

    test('extract_task', () {
      final prompt = testPrompts().extractTask;
      final built = ExtractTask(prompt: prompt).buildRequest(
        ExtractTaskInput('call the bank', now: DateTime.utc(2026, 8, 19, 9)),
        const BackendCapabilities(),
      );

      expect(slotsIn(prompt.prompt), {'now', 'text', 'schemaHint'});
      expect(slotsIn(built.prompt), isEmpty);
      expect(built.prompt, contains('call the bank'));
    });

    test('compose_nudge', () {
      final prompt = testPrompts().composeNudge;
      final built =
          ComposeNudge(
            NudgeTemplates.fromJson(
              File('assets/nudge_templates/templates.json').readAsStringSync(),
            ),
            prompt: prompt,
          ).buildRequest(
            const NudgeCopyRequest(
              type: NudgeType.sessionMissed,
              level: InterventionLevel.l1Check,
              taskTitle: 'Write the report',
              minutes: 45,
              minutesLate: 10,
              moves: 1,
            ),
            const BackendCapabilities(),
          );

      // The trailing {"text": "..."} is a JSON example, not a slot: the
      // pattern only matches a bare {word}, so quotes exclude it. That is
      // load-bearing - a prompt cannot show a model the shape of the reply it
      // wants without writing braces.
      expect(slotsIn(prompt.prompt), {
        'level',
        'task',
        'minutes',
        'late',
        'moves',
      });
      expect(slotsIn(built.prompt), isEmpty);
      expect(built.prompt, contains('Write the report'));
      expect(built.prompt, contains('l1Check'));
    });
  });

  group('what the prompts must not say', () {
    test('no provider names, so a prompt is not tied to one model', () {
      // ARCHITECTURE 5: prompts are written model-agnostically. "You are
      // Claude" in an asset is how the abstraction rots quietly.
      const banned = ['gemma', 'claude', 'anthropic', 'openai', 'gemini'];
      for (final name in Prompts.all) {
        final text = File(
          'assets/prompts/$name',
        ).readAsStringSync().toLowerCase();
        for (final provider in banned) {
          expect(
            text,
            isNot(contains(provider)),
            reason: '$name names "$provider"',
          );
        }
      }
    });

    test('the ladder is never handed to the model to choose', () {
      // compose_nudge and negotiate are both told which level they are
      // writing for. A prompt inviting the model to pick would make
      // escalation unpredictable, which is the one thing it must not be.
      final prompts = testPrompts();
      expect(prompts.composeNudge.system.toLowerCase(), contains('level'));
      expect(prompts.negotiate.system.toLowerCase(), contains('level'));
    });
  });
}
