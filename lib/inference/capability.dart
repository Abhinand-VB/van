import 'package:van/inference/backend.dart';

/// One thing Van wants from a language model.
///
/// A capability owns its prompt, its output schema, its parser and - the part
/// that matters most - a deterministic fallback that always produces a usable
/// result. Van must work with no model at all, so the fallback is not an error
/// path; it is the v1 implementation, and the model is an upgrade on top.
abstract class Capability<TIn, TOut> {
  /// Creates a capability.
  const Capability();

  /// Stable id used for routing config, the event log and golden tests.
  String get id;

  /// The shape the output should take.
  ///
  /// Declared once here. Each backend translates it to whatever mechanism it
  /// has natively, and every backend then runs the same post-hoc validation,
  /// because even native structured output can fail.
  Map<String, Object?> get outputSchema;

  /// Builds the request, adapting to what [caps] can do.
  LlmRequest buildRequest(TIn input, BackendCapabilities caps);

  /// Parses and validates raw model text. Returns null when unusable.
  TOut? parse(String raw);

  /// Produces a result without any model.
  ///
  /// Must always succeed. If this can throw or return null, the app cannot
  /// claim to work offline.
  TOut fallback(TIn input);
}
