import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/router.dart';

/// A routing problem found while building the router.
///
/// Collected rather than thrown. A typo in a config asset must not stop Van
/// starting - it falls back to the default backend, which falls back to the
/// deterministic path, and the app still works. But it must not be silent
/// either, or a capability could quietly stop using the model it was meant to.
@immutable
class ConfigWarning {
  /// Creates a warning.
  const ConfigWarning(this.message);

  /// What was wrong, in words a human can act on.
  final String message;

  @override
  String toString() => 'ConfigWarning($message)';
}

/// Capability-to-backend routing, read from `assets/inference_config.json`.
///
/// This class is why the rest of the codebase can claim that adding a cloud
/// provider is "a config change and one class". It was not true until now:
/// the asset existed and nothing read it, so routing lived in `main.dart`.
/// Named backends are resolved against instances the composition root
/// supplies, because construction needs channels and keys and that is wiring,
/// which belongs in exactly one place.
@immutable
class InferenceConfig {
  /// Creates a config.
  const InferenceConfig({
    required this.defaultBackend,
    required this.backendTypes,
    required this.routes,
  });

  /// Parses the asset. Never throws on a missing field; see [ConfigWarning].
  factory InferenceConfig.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;

    final backends = <String, String>{};
    final declared = json['backends'];
    if (declared is Map<String, dynamic>) {
      for (final entry in declared.entries) {
        final spec = entry.value;
        backends[entry.key] = spec is Map<String, dynamic>
            ? (spec['type'] as String? ?? 'unknown')
            : 'unknown';
      }
    }

    final routes = <String, String>{};
    final declaredRoutes = json['routes'];
    if (declaredRoutes is Map<String, dynamic>) {
      for (final entry in declaredRoutes.entries) {
        if (entry.value is String) routes[entry.key] = entry.value as String;
      }
    }

    return InferenceConfig(
      defaultBackend: json['default_backend'] as String? ?? 'none',
      backendTypes: backends,
      routes: routes,
    );
  }

  /// Backend used for any capability without its own route.
  final String defaultBackend;

  /// Declared backend names, and the type each one is.
  final Map<String, String> backendTypes;

  /// Capability id to backend name.
  final Map<String, String> routes;

  /// Builds a router, resolving names against [available].
  ///
  /// [warnings] collects anything wrong with the config. A name that resolves
  /// to nothing routes to the default instead, so the worst a bad config does
  /// is use the deterministic fallback - which is a working configuration, not
  /// a broken one.
  InferenceRouter router({
    required Map<String, LlmBackend> available,
    required LlmBackend fallbackBackend,
    InferenceObserver observer = const NullInferenceObserver(),
    List<ConfigWarning>? warnings,
  }) {
    void warn(String message) => warnings?.add(ConfigWarning(message));

    final defaultInstance = available[defaultBackend];
    if (defaultInstance == null) {
      warn(
        'default_backend "$defaultBackend" has no instance; '
        'using ${fallbackBackend.id}',
      );
    }

    final byCapability = <String, LlmBackend>{};
    for (final entry in routes.entries) {
      final name = entry.value;
      if (!backendTypes.containsKey(name)) {
        warn(
          'route "${entry.key}" names backend "$name", '
          'which is not declared under "backends"',
        );
      }
      final instance = available[name];
      if (instance == null) {
        warn(
          'route "${entry.key}" names backend "$name", '
          'which has no instance; using the default',
        );
        continue;
      }
      byCapability[entry.key] = instance;
    }

    return InferenceRouter(
      defaultBackend: defaultInstance ?? fallbackBackend,
      byCapabilityId: byCapability,
      observer: observer,
    );
  }
}
