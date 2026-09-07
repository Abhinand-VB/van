import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/backends/gemma_backend.dart';
import 'package:van/platform/local_llm.dart';

import '../support/fake_local_llm.dart';

void main() {
  late FakeLocalLlm llm;
  late GemmaBackend backend;

  setUp(() {
    llm = FakeLocalLlm();
    backend = GemmaBackend(llm);
  });

  const request = LlmRequest(
    system: 'be brief',
    prompt: 'a sentence',
    maxOutputTokens: 80,
    temperature: 0.2,
  );

  group('what it declares', () {
    test('does not claim structured output it cannot do yet', () {
      // ExtractTask asks for schema-constrained decoding when this is true.
      // Claiming it before the engine supports it means asking for JSON and
      // getting prose, which reads as a model failure rather than a wiring
      // one. Flip it in the change that wires the engine, not before.
      expect(backend.capabilities.supportsNativeStructuredOutput, isFalse);
    });

    test('is local, so nothing leaves the phone', () {
      expect(backend.capabilities.isLocal, isTrue);
    });

    test('has a stable id for config and the event log', () {
      expect(backend.id, 'gemma_e2b');
    });
  });

  group('generating', () {
    test('passes the request through unchanged', () async {
      llm.reply = 'an answer';

      final result = await backend.generate(request);

      expect(result, isA<LlmOk>());
      expect((result as LlmOk).text, 'an answer');
      expect(llm.lastSystem, 'be brief');
      expect(llm.lastPrompt, 'a sentence');
      expect(llm.lastMaxTokens, 80);
      expect(llm.lastTemperature, 0.2);
    });

    test('an empty completion is a failure, not an empty success', () async {
      // LlmOk('') would send the parser something it must reject, and the
      // router would log `malformed` when the truth is the model said nothing.
      llm.reply = '   ';

      final result = await backend.generate(request);

      expect(result, isA<LlmFailure>());
      expect((result as LlmFailure).kind, LlmFailureKind.malformed);
    });

    test('a missing model reports unavailable, not a crash', () async {
      llm.failure = const LocalLlmException(
        LocalLlmError.unavailable,
        'no model file',
      );

      final result = await backend.generate(request);

      expect((result as LlmFailure).kind, LlmFailureKind.unavailable);
    });

    test('running out of memory is told apart from bad output', () async {
      // They mean different things: oom says this device cannot run the model
      // at all, malformed says try again.
      llm.failure = const LocalLlmException(
        LocalLlmError.failed,
        'Failed to allocate memory for the session',
      );

      final result = await backend.generate(request);

      expect((result as LlmFailure).kind, LlmFailureKind.oom);
    });

    test('any other engine failure is malformed', () async {
      llm.failure = const LocalLlmException(
        LocalLlmError.failed,
        'tokeniser exploded',
      );

      final result = await backend.generate(request);

      expect((result as LlmFailure).kind, LlmFailureKind.malformed);
    });
  });

  group('timing out', () {
    test('gives up and says so', () async {
      llm.hang = const Duration(seconds: 2);

      final result = await backend.generate(
        const LlmRequest(prompt: 'x', timeout: Duration(milliseconds: 20)),
      );

      expect((result as LlmFailure).kind, LlmFailureKind.timeout);
    });

    test('tells the engine to stop', () async {
      // The generation is still running on the device thread and holds the
      // model until it finishes. Walking away without cancelling would block
      // the next call behind an answer nobody wants.
      llm.hang = const Duration(seconds: 2);

      await backend.generate(
        const LlmRequest(prompt: 'x', timeout: Duration(milliseconds: 20)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(llm.cancelled, isTrue);
    });
  });

  group('lifecycle', () {
    test('availability comes from the platform, not a cached guess', () async {
      llm.available = false;
      expect(await backend.isAvailable(), isFalse);
      llm.available = true;
      expect(await backend.isAvailable(), isTrue);
    });

    test('warming up is advisory and never throws', () async {
      llm.available = false;
      await backend.warmUp();
      expect(llm.warmedUp, isTrue);
    });

    test('disposing releases the model', () async {
      await backend.dispose();
      expect(llm.disposed, isTrue);
    });
  });

  group('streaming', () {
    test('yields once at the end rather than pretending to stream', () async {
      llm.reply = 'an answer';

      final chunks = await backend.generateStream(request).toList();

      expect(chunks, ['an answer']);
    });

    test('yields nothing when the call failed', () async {
      llm.failure = const LocalLlmException(
        LocalLlmError.unavailable,
        'no model',
      );

      expect(await backend.generateStream(request).toList(), isEmpty);
    });
  });
}
