import 'package:van/inference/backend.dart';
import 'package:van/inference/capability.dart';

/// How a result was produced.
enum InferenceOutcome {
  /// A backend answered and the output parsed.
  model,

  /// The deterministic fallback ran.
  fallback,
}

/// Notified about every inference attempt.
///
/// Kept as a narrow interface rather than a direct `EventRepo` dependency so
/// the inference layer does not reach into the data layer. The app supplies an
/// adapter that appends to the event log.
abstract interface class InferenceObserver {
  /// Records one completed attempt.
  void onInference({
    required String capabilityId,
    required String backendId,
    required InferenceOutcome outcome,
    String? failureReason,
    int? latencyMs,
  });
}

/// An observer that does nothing, for tests that do not care.
class NullInferenceObserver implements InferenceObserver {
  /// Creates a no-op observer.
  const NullInferenceObserver();

  @override
  void onInference({
    required String capabilityId,
    required String backendId,
    required InferenceOutcome outcome,
    String? failureReason,
    int? latencyMs,
  }) {}
}

/// Sends each capability to whichever backend the config names.
///
/// This is where "start offline, expand to a cloud model later" becomes a
/// config change. The router is the only place that knows a capability and a
/// backend are separate things, and it guarantees the caller always gets an
/// answer: if the backend is missing, slow, or produces nonsense, the
/// capability's deterministic fallback runs instead.
class InferenceRouter {
  /// Creates a router.
  InferenceRouter({
    required LlmBackend defaultBackend,
    Map<String, LlmBackend> byCapabilityId = const {},
    InferenceObserver observer = const NullInferenceObserver(),
  }) : _default = defaultBackend,
       _byCapabilityId = byCapabilityId,
       _observer = observer;

  final LlmBackend _default;
  final Map<String, LlmBackend> _byCapabilityId;
  final InferenceObserver _observer;

  /// The backend that would serve [capabilityId].
  LlmBackend backendFor(String capabilityId) =>
      _byCapabilityId[capabilityId] ?? _default;

  /// Runs [capability] over [input], never throwing and never returning null.
  Future<TOut> run<TIn, TOut>(
    Capability<TIn, TOut> capability,
    TIn input,
  ) async {
    final backend = backendFor(capability.id);
    final stopwatch = Stopwatch()..start();

    Future<TOut> fallback(String reason) async {
      stopwatch.stop();
      _observer.onInference(
        capabilityId: capability.id,
        backendId: backend.id,
        outcome: InferenceOutcome.fallback,
        failureReason: reason,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      return capability.fallback(input);
    }

    try {
      if (!await backend.isAvailable()) {
        return fallback(LlmFailureKind.unavailable.name);
      }

      final result = await backend.generate(
        capability.buildRequest(input, backend.capabilities),
      );

      if (result is LlmFailure) return fallback(result.kind.name);

      final parsed = capability.parse((result as LlmOk).text);
      if (parsed == null) return fallback(LlmFailureKind.malformed.name);

      stopwatch.stop();
      _observer.onInference(
        capabilityId: capability.id,
        backendId: backend.id,
        outcome: InferenceOutcome.model,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      return parsed;
    } on Object catch (error) {
      // A backend that throws is a backend that is broken, not a reason for
      // the whole app to be. Treat it exactly like a declared failure.
      return fallback('threw: $error');
    }
  }
}
