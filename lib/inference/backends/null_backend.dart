import 'package:van/inference/backend.dart';

/// The backend for a build with no model at all.
///
/// Van v1 ships with this wired in. It is not a stub or a placeholder: every
/// capability has a deterministic fallback, so with this backend the app is
/// fully functional, just without a language model. Swapping it for a real one
/// is a change to assets/inference_config.json.
class NullBackend implements LlmBackend {
  /// Creates the null backend.
  const NullBackend();

  @override
  String get id => 'none';

  @override
  BackendCapabilities get capabilities => const BackendCapabilities(
    supportsStreaming: false,
    typicalLatencyMs: 0,
  );

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<LlmResult> generate(LlmRequest request) async =>
      const LlmFailure(LlmFailureKind.unavailable, 'no model configured');

  @override
  Stream<String> generateStream(LlmRequest request) => const Stream.empty();

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> dispose() async {}
}
