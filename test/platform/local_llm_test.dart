import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/platform/local_llm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.van.app/local_llm');
  const llm = MethodChannelLocalLlm(channel);
  final calls = <MethodCall>[];

  /// Answers the channel the way `LocalLlmPlugin.kt` would.
  void respond(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  /// Removes the handler entirely, which is what a platform without the
  /// plugin registered actually looks like.
  void unregister() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  setUp(calls.clear);
  tearDown(unregister);

  group('availability', () {
    test('reports what the platform says', () async {
      respond((_) => true);
      expect(await llm.isAvailable(), isTrue);

      respond((_) => false);
      expect(await llm.isAvailable(), isFalse);
    });

    test('a platform error is just unavailable, never a throw', () async {
      // Asked before every routed call, so throwing here would turn a missing
      // model into a crash on a path that is supposed to fall back quietly.
      respond((_) => throw PlatformException(code: 'boom'));
      expect(await llm.isAvailable(), isFalse);
    });

    test('no plugin at all is unavailable too', () async {
      unregister();
      expect(await llm.isAvailable(), isFalse);
    });
  });

  group('generating', () {
    test('sends everything the engine needs', () async {
      respond((_) => 'an answer');

      final text = await llm.generate(
        prompt: 'a sentence',
        system: 'be brief',
        maxOutputTokens: 80,
        temperature: 0.2,
      );

      expect(text, 'an answer');
      expect(calls.single.method, 'generate');
      expect(calls.single.arguments, {
        'system': 'be brief',
        'prompt': 'a sentence',
        'maxOutputTokens': 80,
        'temperature': 0.2,
      });
    });

    test(
      'an unavailable engine raises rather than returning nothing',
      () async {
        // The distinction the whole class exists for: a missing model must not
        // be mistakable for a model that answered with an empty string.
        respond(
          (_) =>
              throw PlatformException(code: 'unavailable', message: 'no file'),
        );

        await expectLater(
          () => llm.generate(prompt: 'x'),
          throwsA(
            isA<LocalLlmException>().having(
              (e) => e.error,
              'error',
              LocalLlmError.unavailable,
            ),
          ),
        );
      },
    );

    test('a detached channel is reported as such', () async {
      respond((_) => throw PlatformException(code: 'detached'));

      await expectLater(
        () => llm.generate(prompt: 'x'),
        throwsA(
          isA<LocalLlmException>().having(
            (e) => e.error,
            'error',
            LocalLlmError.detached,
          ),
        ),
      );
    });

    test('an unrecognised code is a failure, not a silent success', () async {
      respond((_) => throw PlatformException(code: 'something new'));

      await expectLater(
        () => llm.generate(prompt: 'x'),
        throwsA(
          isA<LocalLlmException>().having(
            (e) => e.error,
            'error',
            LocalLlmError.failed,
          ),
        ),
      );
    });

    test('a null answer is a failure', () async {
      respond((_) => null);

      await expectLater(
        () => llm.generate(prompt: 'x'),
        throwsA(isA<LocalLlmException>()),
      );
    });

    test('no plugin registered raises unavailable', () async {
      unregister();

      await expectLater(
        () => llm.generate(prompt: 'x'),
        throwsA(
          isA<LocalLlmException>().having(
            (e) => e.error,
            'error',
            LocalLlmError.unavailable,
          ),
        ),
      );
    });
  });

  group('teardown', () {
    test('cancel and dispose swallow failures', () async {
      // Both are called when the caller has already moved on - after a
      // timeout, or while the activity is being destroyed. Throwing there
      // achieves nothing and can take the teardown with it.
      respond((_) => throw PlatformException(code: 'boom'));

      await expectLater(llm.cancel(), completes);
      await expectLater(llm.dispose(), completes);
    });

    test('and work with no plugin registered', () async {
      unregister();
      await expectLater(llm.cancel(), completes);
      await expectLater(llm.dispose(), completes);
    });

    test('warm-up failure is not fatal', () async {
      respond((_) => throw PlatformException(code: 'boom'));
      expect(await llm.warmUp(), isFalse);
    });
  });

  group('the channel name', () {
    test('matches the Kotlin side', () async {
      // These are two string literals in two languages with nothing linking
      // them. If they drift, every call silently becomes unavailable.
      final kotlin = await _kotlinChannelName();
      expect(kotlin, channel.name);
    });
  });
}

/// Reads `LocalLlmPlugin.CHANNEL` out of the Kotlin source.
Future<String> _kotlinChannelName() async {
  const path = 'android/app/src/main/kotlin/dev/van/app/LocalLlmPlugin.kt';
  final source = await File(path).readAsString();
  final match = RegExp(r'CHANNEL:\s*String\s*=\s*"([^"]+)"').firstMatch(source);
  if (match == null) {
    throw StateError('could not find CHANNEL in $path');
  }
  return match.group(1)!;
}
