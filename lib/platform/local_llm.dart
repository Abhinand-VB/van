import 'package:flutter/services.dart';

/// Why a call to the local model could not be made.
enum LocalLlmError {
  /// No engine compiled in, or no model file on disk. The expected state
  /// until WP-6 finishes, and a normal state afterwards while the model is
  /// still downloading.
  unavailable,

  /// The channel is not attached. Only happens during teardown.
  detached,

  /// The engine was reached and something went wrong inside it.
  failed,
}

/// Raised by [LocalLlm] rather than returning a sentinel.
///
/// A missing model must not be mistakable for a model that answered with an
/// empty string - the first is a fallback, the second is a bug.
class LocalLlmException implements Exception {
  /// Creates an exception.
  const LocalLlmException(this.error, this.message);

  /// What kind of failure this was.
  final LocalLlmError error;

  /// Detail for the log. Never shown to the user.
  final String message;

  @override
  String toString() => 'LocalLlmException(${error.name}: $message)';
}

/// The Dart half of the `LocalLlm` platform channel.
///
/// An interface so the backend above it can be tested without a phone. The
/// real implementation is [MethodChannelLocalLlm]; tests use a fake.
abstract interface class LocalLlm {
  /// Whether a model could answer right now.
  Future<bool> isAvailable();

  /// Loads the model so the first real call is not the slow one.
  Future<bool> warmUp();

  /// Runs one prompt to completion.
  Future<String> generate({
    required String prompt,
    String system,
    int maxOutputTokens,
    double temperature,
  });

  /// Abandons any generation in flight.
  Future<void> cancel();

  /// Releases the engine.
  Future<void> dispose();
}

/// Talks to `LocalLlmPlugin.kt` over a method channel.
///
/// Deliberately thin. It moves strings across the boundary and translates
/// platform errors into [LocalLlmException]; every decision about *what to
/// ask* belongs to the capabilities, and every decision about what to do when
/// the answer is unusable belongs to `InferenceRouter`.
class MethodChannelLocalLlm implements LocalLlm {
  /// Creates a client over [channel].
  const MethodChannelLocalLlm([
    this.channel = const MethodChannel('dev.van.app/local_llm'),
  ]);

  /// The channel, matching `LocalLlmPlugin.CHANNEL`.
  final MethodChannel channel;

  @override
  Future<bool> isAvailable() async {
    // Availability is asked before every routed call, so it must never throw:
    // a channel that is not there at all is simply an unavailable model.
    try {
      return await channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> warmUp() async {
    try {
      return await channel.invokeMethod<bool>('warmUp') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String> generate({
    required String prompt,
    String system = '',
    int maxOutputTokens = 256,
    double temperature = 0.7,
  }) async {
    try {
      final text = await channel.invokeMethod<String>('generate', {
        'system': system,
        'prompt': prompt,
        'maxOutputTokens': maxOutputTokens,
        'temperature': temperature,
      });
      if (text == null) {
        throw const LocalLlmException(
          LocalLlmError.failed,
          'the engine returned nothing',
        );
      }
      return text;
    } on PlatformException catch (e) {
      throw LocalLlmException(_errorFrom(e.code), e.message ?? e.code);
    } on MissingPluginException {
      throw const LocalLlmException(
        LocalLlmError.unavailable,
        'the local model channel is not registered on this platform',
      );
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // Cancelling something that is not running is not a failure worth
      // propagating; the caller has already moved on.
    } on MissingPluginException {
      // Likewise.
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // Nothing useful to do during teardown.
    } on MissingPluginException {
      // Likewise.
    }
  }

  static LocalLlmError _errorFrom(String code) => switch (code) {
    'unavailable' => LocalLlmError.unavailable,
    'detached' => LocalLlmError.detached,
    _ => LocalLlmError.failed,
  };
}
