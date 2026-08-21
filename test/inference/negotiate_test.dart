import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/backends/mock_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capabilities/negotiate.dart';
import 'package:van/inference/router.dart';
import 'package:van_core/van_core.dart';

void main() {
  late Negotiate negotiate;
  late MockBackend backend;
  late InferenceRouter router;

  setUp(() {
    negotiate = Negotiate(
      prompt: PromptTemplate.parse(
        File('assets/prompts/negotiate.v1.txt').readAsStringSync(),
      ),
      templates: NudgeTemplates.fromJson(
        File('assets/nudge_templates/templates.json').readAsStringSync(),
      ),
    );
    backend = MockBackend();
    router = InferenceRouter(defaultBackend: backend);
  });

  NegotiationRequest request({
    int minutes = 60,
    int minutesLate = 0,
    int moves = 0,
    double? hoursToDeadline,
    bool userRefused = false,
    bool userGaveReason = false,
    String? reasonText,
  }) => NegotiationRequest(
    taskTitle: 'Database assignment',
    minutes: minutes,
    minutesLate: minutesLate,
    moves: moves,
    hoursToDeadline: hoursToDeadline,
    userRefused: userRefused,
    userGaveReason: userGaveReason,
    reasonText: reasonText,
  );

  group('the prompt asset', () {
    test('loads from assets rather than a string literal in Dart', () {
      final file = File('assets/prompts/negotiate.v1.txt');
      expect(file.existsSync(), isTrue);
    });

    test('splits into a system half and a prompt half', () {
      final parsed = PromptTemplate.parse(
        'SYSTEM\nbe brief\n\nPROMPT\nTask: {task}',
      );
      expect(parsed.system, 'be brief');
      expect(parsed.prompt, 'Task: {task}');
    });

    test('a malformed asset degrades instead of throwing', () {
      final parsed = PromptTemplate.parse('just some text');
      expect(parsed.system, isEmpty);
      expect(parsed.prompt, 'just some text');
    });

    test('every placeholder is filled before the model sees it', () {
      final built = negotiate.buildRequest(
        request(minutesLate: 12, moves: 2, hoursToDeadline: 5),
        const BackendCapabilities(),
      );
      // Not "contains no brace" - the prompt ends with a JSON example that
      // legitimately has them. What must not survive is an unfilled slot.
      for (final slot in [
        'task',
        'minutes',
        'late',
        'moves',
        'deadline',
        'level',
        'allowed',
        'reason',
      ]) {
        expect(
          built.prompt,
          isNot(contains('{$slot}')),
          reason: '{$slot} reached the model unfilled',
        );
      }
      expect(built.system, isNotEmpty);
      expect(built.prompt, contains('Database assignment'));
    });
  });

  group("the level is never the model's to choose", () {
    test('the ladder picks it and the prompt only reports it', () {
      final built = negotiate.buildRequest(
        request(minutesLate: 30),
        const BackendCapabilities(),
      );
      expect(built.prompt, contains('Level: l2Diagnose'));
    });

    test('the prompt states only the actions that level permits', () {
      final gentle = negotiate.buildRequest(
        request(),
        const BackendCapabilities(),
      );
      expect(gentle.prompt, contains('Permitted actions: hold'));
      expect(gentle.prompt, isNot(contains('release')));
    });

    test('a refusal at the renegotiation stage unlocks conceding', () {
      final conceding = negotiate.buildRequest(
        request(moves: 3, hoursToDeadline: 4, userRefused: true),
        const BackendCapabilities(),
      );
      expect(conceding.prompt, contains('Level: l5Concede'));
      expect(conceding.prompt, contains('release'));
    });
  });

  group('parsing a model reply', () {
    test('reads a well-formed proposal', () {
      final parsed = negotiate.parse(
        '{"action": "shrink", "shrinkToMinutes": 20, "message": "Try 20?"}',
      );
      expect(parsed!.action, NegotiationAction.shrink);
      expect(parsed.shrinkToMinutes, 20);
      expect(parsed.message, 'Try 20?');
      expect(parsed.fromModel, isTrue);
    });

    test('salvages a proposal wrapped in chatter', () {
      final parsed = negotiate.parse(
        'Sure! Here you go:\n```json\n'
        '{"action": "hold", "message": "Still on for this?"}\n```',
      );
      expect(parsed!.action, NegotiationAction.hold);
    });

    test('refuses an action it does not recognise', () {
      expect(
        negotiate.parse('{"action": "delete_everything", "message": "hi"}'),
        isNull,
      );
    });

    test('refuses a proposal with no message', () {
      expect(negotiate.parse('{"action": "hold", "message": "  "}'), isNull);
      expect(negotiate.parse('{"action": "hold"}'), isNull);
    });

    test('refuses text that is not JSON at all', () {
      expect(negotiate.parse('I think you should take a break.'), isNull);
    });
  });

  group('the deterministic fallback', () {
    test('holds while Van is still just asking', () {
      final proposal = negotiate.fallback(request(minutesLate: 5));
      expect(proposal.action, NegotiationAction.hold);
      expect(proposal.message, isNotEmpty);
      expect(proposal.templateId, isNotNull);
      expect(proposal.fromModel, isFalse);
    });

    test('offers half the block once the level allows it', () {
      final proposal = negotiate.fallback(
        request(minutes: 60, userGaveReason: true, reasonText: 'too tired'),
      );
      expect(proposal.action, NegotiationAction.shrink);
      expect(proposal.shrinkToMinutes, 30);
    });

    test('never proposes a block too small to be work', () {
      // Half of 20 is under the floor, so shrinking is not on offer.
      final proposal = negotiate.fallback(
        request(minutes: 20, userGaveReason: true),
      );
      expect(proposal.action, NegotiationAction.hold);
      expect(proposal.shrinkToMinutes, isNull);
    });

    test('concedes by shrinking rather than releasing when it still can', () {
      // Releasing loses the work; a wrong hold costs one notification. With
      // no model, Van takes the cheaper mistake.
      final proposal = negotiate.fallback(
        request(minutes: 60, moves: 3, hoursToDeadline: 4, userRefused: true),
      );
      expect(proposal.action, NegotiationAction.shrink);
    });

    test('releases only when nothing smaller is left to offer', () {
      final proposal = negotiate.fallback(
        request(minutes: 20, moves: 3, hoursToDeadline: 4, userRefused: true),
      );
      expect(proposal.action, NegotiationAction.release);
    });

    test('always produces something the rules will accept', () {
      const rules = NegotiationRules();
      for (final minutes in [15, 20, 45, 60, 90]) {
        for (final late in [0, 12, 30, 90]) {
          for (final refused in [false, true]) {
            final input = request(
              minutes: minutes,
              minutesLate: late,
              moves: 3,
              hoursToDeadline: 4,
              userRefused: refused,
            );
            final proposal = negotiate.fallback(input);
            expect(
              rules.reject(proposal, negotiate.contextFor(input)),
              isNull,
              reason:
                  'fallback produced $proposal for ${minutes}m, ${late}m late, '
                  'refused=$refused - the fallback must never be refused',
            );
          }
        }
      }
    });
  });

  group('through the router', () {
    test('a usable model reply is used', () async {
      backend.replyToAll(
        '{"action": "shrink", "shrinkToMinutes": 25, "message": "25 minutes?"}',
      );
      final proposal = await router.run(
        negotiate,
        request(minutes: 60, userGaveReason: true),
      );
      expect(proposal.message, '25 minutes?');
      expect(proposal.fromModel, isTrue);
    });

    test('garbage falls back to the ladder', () async {
      backend.replyToAll('no thanks');
      final proposal = await router.run(negotiate, request(minutesLate: 5));
      expect(proposal.action, NegotiationAction.hold);
      expect(proposal.fromModel, isFalse);
    });

    test('a dead model still produces a proposal', () async {
      backend.failEverything();
      final proposal = await router.run(negotiate, request(minutesLate: 5));
      expect(proposal.message, isNotEmpty);
      expect(proposal.fromModel, isFalse);
    });

    test(
      'a model overreaching is caught by the domain, not the parser',
      () async {
        // The parser accepts this - it is well-formed JSON with a real action.
        // Refusing it is the domain's job, and that separation is the point.
        backend.replyToAll(
          '{"action": "release", "message": "Forget it, take the day off."}',
        );
        final input = request(minutesLate: 2);
        final proposal = await router.run(negotiate, input);

        expect(proposal.action, NegotiationAction.release);
        expect(
          const NegotiationRules().reject(
            proposal,
            negotiate.contextFor(input),
          ),
          NegotiationRejection.actionExceedsLevel,
          reason: 'an l0 prompt must never be able to cancel the day',
        );
      },
    );
  });
}
