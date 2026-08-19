import 'dart:async';

import 'package:van/inference/backend.dart';

/// A backend whose behaviour is scripted per capability.
///
/// This is the backend CI uses. Its most important job is not returning canned
/// answers - it is being able to fail on demand, so the suite can prove Van
/// still works end to end when every model call goes wrong.
class MockBackend implements LlmBackend {
  /// Creates a mock.
  ///
  /// With no arguments every call fails as [LlmFailureKind.unavailable], which
  /// is the correct default: a build with no model configured.
  MockBackend({
    this.id = 'mock',
    BackendCapabilities? capabilities,
    bool available = true,
  }) : capabilities =
           capabilities ??
           const BackendCapabilities(
             supportsNativeStructuredOutput: true,
             supportsStreaming: true,
           ),
       _available = available;

  @override
  final String id;

  @override
  final BackendCapabilities capabilities;

  bool _available;

  /// Canned replies, keyed by a substring of the prompt.
  final _replies = <String, String>{};

  /// Scripted failures, keyed by a substring of the prompt.
  final _failures = <String, LlmFailureKind>{};

  String? _replyToEverything;
  LlmFailureKind? _failEverything;

  /// Every request the mock has seen, for assertions.
  final requests = <LlmRequest>[];

  /// Replies with [text] whenever the prompt contains [promptContains].
  void reply(String promptContains, String text) =>
      _replies[promptContains] = text;

  /// Replies with [text] to anything not otherwise matched.
  // ignore: use_setters_to_change_properties
  void replyToAll(String text) => _replyToEverything = text;

  /// Fails with [kind] whenever the prompt contains [promptContains].
  void failOn(String promptContains, LlmFailureKind kind) =>
      _failures[promptContains] = kind;

  /// Fails every call with [kind].
  ///
  /// The decisive offline test uses this: with the model failing on every
  /// call, the app must still capture tasks, plan sessions and write nudges.
  // ignore: use_setters_to_change_properties
  void failEverything([LlmFailureKind kind = LlmFailureKind.unavailable]) =>
      _failEverything = kind;

  /// Makes [isAvailable] report false.
  void goOffline() => _available = false;

  /// Makes [isAvailable] report true again.
  void goOnline() => _available = true;

  @override
  Future<bool> isAvailable() async => _available;

  @override
  Future<LlmResult> generate(LlmRequest request) async {
    requests.add(request);

    if (_failEverything != null) {
      return LlmFailure(_failEverything!, 'scripted');
    }
    for (final entry in _failures.entries) {
      if (request.prompt.contains(entry.key)) {
        return LlmFailure(entry.value, 'scripted for "${entry.key}"');
      }
    }
    for (final entry in _replies.entries) {
      if (request.prompt.contains(entry.key)) {
        return LlmOk(entry.value);
      }
    }
    if (_replyToEverything != null) return LlmOk(_replyToEverything!);

    return const LlmFailure(
      LlmFailureKind.unavailable,
      'no scripted reply matched',
    );
  }

  @override
  Stream<String> generateStream(LlmRequest request) async* {
    final result = await generate(request);
    if (result is LlmOk) yield result.text;
  }

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> dispose() async {}
}
