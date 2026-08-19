import 'package:meta/meta.dart';

/// Why a model call did not produce usable text.
enum LlmFailureKind {
  /// No backend is present - no model file, no key, not installed.
  unavailable,

  /// Took longer than the caller was willing to wait.
  timeout,

  /// The device ran out of memory loading or running the model.
  oom,

  /// Produced something, but not something that could be parsed.
  malformed,

  /// A remote backend refused for rate reasons.
  rateLimited,

  /// A remote backend refused for credential reasons.
  authFailed,
}

/// What a backend can actually do.
///
/// Capabilities read this to decide their strategy - whether to ask for
/// schema-constrained decoding or to embed the schema in the prompt and
/// validate afterwards.
@immutable
class BackendCapabilities {
  /// Creates a capability declaration.
  const BackendCapabilities({
    this.supportsNativeStructuredOutput = false,
    this.supportsStreaming = false,
    this.supportsSystemPrompt = true,
    this.contextWindowTokens = 4096,
    this.isLocal = true,
    this.typicalLatencyMs = 500,
  });

  /// Whether the backend can constrain decoding to a JSON schema itself.
  final bool supportsNativeStructuredOutput;

  /// Whether tokens can be streamed as they are produced.
  final bool supportsStreaming;

  /// Whether a separate system prompt is honoured.
  final bool supportsSystemPrompt;

  /// Usable context, in tokens.
  final int contextWindowTokens;

  /// Whether this runs on the device, with no network and no cost.
  final bool isLocal;

  /// Rough round-trip time, used when deciding whether a call is worth making
  /// inside a time-critical path.
  final int typicalLatencyMs;
}

/// One request to a backend.
@immutable
class LlmRequest {
  /// Creates a request.
  const LlmRequest({
    required this.prompt,
    this.system = '',
    this.jsonSchema,
    this.maxOutputTokens = 512,
    this.temperature = 0.7,
    this.timeout = const Duration(seconds: 20),
  });

  /// Instructions that frame the task.
  final String system;

  /// The actual input.
  final String prompt;

  /// The shape the output should take, if any. Backends that support native
  /// structured output translate this; the rest embed it in the prompt.
  final Map<String, Object?>? jsonSchema;

  /// Ceiling on the reply length.
  final int maxOutputTokens;

  /// Sampling temperature.
  final double temperature;

  /// How long the caller will wait.
  final Duration timeout;
}

/// The outcome of a backend call.
sealed class LlmResult {
  const LlmResult();
}

/// A successful call.
@immutable
class LlmOk extends LlmResult {
  /// Creates a success.
  const LlmOk(this.text, {this.inputTokens, this.outputTokens});

  /// What the model said.
  final String text;

  /// Prompt tokens, when the backend reports them.
  final int? inputTokens;

  /// Completion tokens, when the backend reports them.
  final int? outputTokens;
}

/// A failed call.
@immutable
class LlmFailure extends LlmResult {
  /// Creates a failure.
  const LlmFailure(this.kind, [this.message = '']);

  /// What went wrong.
  final LlmFailureKind kind;

  /// Detail for the log. Never shown to the user.
  final String message;

  @override
  String toString() => 'LlmFailure(${kind.name}: $message)';
}

/// Something that can turn a prompt into text.
///
/// This is the entire surface a new provider has to implement. Adding a cloud
/// model in phase 3 means writing one of these and adding a line to
/// `assets/inference_config.json` - no domain code changes, which
/// `tool/check_layers.dart` enforces.
abstract interface class LlmBackend {
  /// Stable identifier used in config and in the event log.
  String get id;

  /// What this backend can do.
  BackendCapabilities get capabilities;

  /// Whether it can be called right now.
  Future<bool> isAvailable();

  /// Runs one request.
  Future<LlmResult> generate(LlmRequest request);

  /// Runs one request, yielding text as it arrives.
  Stream<String> generateStream(LlmRequest request);

  /// Prepares the backend so the first real call is not the slow one.
  Future<void> warmUp();

  /// Releases whatever the backend is holding.
  Future<void> dispose();
}
