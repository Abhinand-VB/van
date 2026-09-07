import 'dart:async';

import 'package:van/inference/backend.dart';
import 'package:van/platform/local_llm.dart';

/// Gemma 4 E2B, running on the phone through the `LocalLlm` channel.
///
/// The whole point of the backend layer is that this file is the only one that
/// knows the model's name. Capabilities ask `InferenceRouter` for a backend by
/// capability id; swapping this for a cloud provider is a line in
/// `assets/inference_config.json`, which `tool/check_layers.dart` enforces by
/// failing the build if a provider name appears in `core/` or `ui/`.
///
/// **Latency is measured; accuracy is not.** One capture takes about two and
/// three quarter minutes on the owner's phone, which [capabilities] now says
/// rather than guesses. That is more than eight times the 20 s an `LlmRequest`
/// waits by default, so every interactive capability routed here would time
/// out and fall back - see `STATUS.md` 3ad and D86. How *good* the answers are
/// is what `GoldenRunScreen` exists to find out; the WP-6 gate in STATUS
/// section 6 still stands, and nothing may be routed here below 80%.
class GemmaBackend implements LlmBackend {
  /// Creates a backend over [_llm].
  ///
  /// [timeout] overrides how long each request may take. Null - the
  /// production value - respects whatever the capability asked for, which is
  /// right: how long to wait is a fact about the person waiting, not about the
  /// model. Only the measurement harness sets it, and `DECISIONS_PENDING.md`
  /// D86 says why that is not the same as being impatient in production.
  GemmaBackend(this._llm, {BackendCapabilities? capabilities, this.timeout})
    : _declared = capabilities ?? _defaults;

  static const _defaults = BackendCapabilities(
    // Gemma 4 supports constrained decoding through LiteRT-LM, but the
    // integration is not written, so capabilities must not claim it yet -
    // ExtractTask would ask for schema-constrained output and get prose.
    // Flip this in the same change that wires the engine, not before.
    supportsNativeStructuredOutput: false,
    // Streaming exists in LiteRT-LM. The channel deliberately does not expose
    // it: an EventChannel is a sixth method and a second failure mode, and
    // nothing in Van renders a partial answer.
    supportsStreaming: false,
    contextWindowTokens: 4096,
    isLocal: true,
    // **Measured, 6-7 Sep 2026, on a Snapdragon 8 Elite.** One `extract_task`
    // capture took 164,990 ms cold and 183,643 ms warm; cutting the output
    // budget by a third moved it by nine seconds, so roughly 155 s of it is
    // fixed cost before a token is decoded. The GPU and NPU builds of these
    // weights cannot be loaded by this runtime at all - `STATUS.md` 3ad.
    //
    // It is recorded here because the number has to live where a decision
    // would read it: this is more than eight times the 20 s a request asks
    // for by default, which means routing an interactive capability here
    // times out every single time. D84 and D86.
    typicalLatencyMs: 165000,
  );

  final LocalLlm _llm;
  final BackendCapabilities _declared;

  /// How long a request may take, when the caller's own limit is not wanted.
  ///
  /// Null means the request decides.
  final Duration? timeout;

  /// The limit actually applied to [request].
  Duration _patienceFor(LlmRequest request) => timeout ?? request.timeout;

  @override
  String get id => 'gemma_e2b';

  @override
  BackendCapabilities get capabilities => _declared;

  @override
  Future<bool> isAvailable() => _llm.isAvailable();

  @override
  Future<LlmResult> generate(LlmRequest request) async {
    try {
      final text = await _llm
          .generate(
            system: request.system,
            prompt: request.prompt,
            maxOutputTokens: request.maxOutputTokens,
            temperature: request.temperature,
          )
          .timeout(_patienceFor(request));

      // An empty answer is a failure, not an empty success. Returning LlmOk('')
      // here would send the capability's parser something it must reject, and
      // the router would log it as `malformed` when the truth is the model
      // said nothing.
      if (text.trim().isEmpty) {
        return const LlmFailure(LlmFailureKind.malformed, 'empty completion');
      }
      return LlmOk(text);
    } on TimeoutException {
      // The generation is still running on the device thread and will hold the
      // engine until it finishes, so tell it to stop before giving up.
      // Cancelling is exactly the call most likely to throw - the engine is
      // being abandoned mid-generation, which is why we are here - and
      // `unawaited` does not catch, so without this the failure would surface
      // as an unhandled async error long after the timeout was handled.
      unawaited(_llm.cancel().catchError((Object _, StackTrace _) {}));
      return LlmFailure(
        LlmFailureKind.timeout,
        'no answer within ${_patienceFor(request).inMilliseconds}ms',
      );
    } on LocalLlmException catch (e) {
      return LlmFailure(_kindFrom(e), e.message);
    }
  }

  @override
  Stream<String> generateStream(LlmRequest request) async* {
    // Honest rather than fake: one chunk at the end. The channel does not
    // stream, and pretending to would make a caller believe partial output is
    // arriving early.
    final result = await generate(request);
    if (result is LlmOk) yield result.text;
  }

  @override
  Future<void> warmUp() async {
    // Loading takes seconds and the result is only advisory - a failed warm-up
    // means the first real call is slow, not that it will fail.
    await _llm.warmUp();
  }

  @override
  Future<void> dispose() => _llm.dispose();

  /// Maps a channel failure onto the router's vocabulary.
  ///
  /// Out-of-memory arrives as a generic engine failure carrying the word, and
  /// telling it apart matters: `oom` means the device cannot run this model at
  /// all, while `malformed` means try again with a different prompt.
  static LlmFailureKind _kindFrom(LocalLlmException e) {
    if (e.error == LocalLlmError.unavailable) return LlmFailureKind.unavailable;
    if (e.error == LocalLlmError.detached) return LlmFailureKind.unavailable;
    final message = e.message.toLowerCase();
    if (message.contains('memory') || message.contains('oom')) {
      return LlmFailureKind.oom;
    }
    return LlmFailureKind.malformed;
  }
}
