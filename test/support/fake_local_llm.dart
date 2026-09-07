import 'package:van/platform/local_llm.dart';

/// A local model that does whatever the test needs.
///
/// Lives here rather than in one test file because two suites now need it:
/// the backend's own tests, and the golden-run screen that measures the
/// backend. A second copy would drift from this one.
class FakeLocalLlm implements LocalLlm {
  bool available = true;
  bool warmedUp = false;
  bool cancelled = false;
  bool disposed = false;
  int calls = 0;

  /// What `generate` should do. Set one of these.
  String? reply;
  LocalLlmException? failure;
  Duration? hang;

  /// Replies in order, one per call, falling back to [reply] when exhausted.
  ///
  /// A model that answers some sentences and not others is the interesting
  /// case for anything measuring one, and a single [reply] cannot express it.
  List<String?>? replies;

  String? lastSystem;
  String? lastPrompt;
  int? lastMaxTokens;
  double? lastTemperature;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> warmUp() async {
    warmedUp = true;
    return available;
  }

  @override
  Future<String> generate({
    required String prompt,
    String system = '',
    int maxOutputTokens = 256,
    double temperature = 0.7,
  }) async {
    final index = calls;
    calls++;
    lastSystem = system;
    lastPrompt = prompt;
    lastMaxTokens = maxOutputTokens;
    lastTemperature = temperature;

    if (hang != null) await Future<void>.delayed(hang!);
    if (failure != null) throw failure!;
    if (replies case final scripted? when index < scripted.length) {
      final one = scripted[index];
      if (one == null) {
        throw const LocalLlmException(LocalLlmError.failed, 'scripted failure');
      }
      return one;
    }
    return reply ?? '';
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async => disposed = true;
}
