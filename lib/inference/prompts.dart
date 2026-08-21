import 'package:meta/meta.dart';

/// A prompt loaded from `assets/prompts/`, split into its two halves.
///
/// Prompts are assets rather than string literals so they can be versioned,
/// diffed and swapped without a rebuild — a prompt change is a content change,
/// and reviewing one inside a Dart file is miserable. AGENTS.md has required
/// this from the start; `assets/prompts/` simply sat empty for months.
@immutable
class PromptTemplate {
  /// Creates a template.
  const PromptTemplate({required this.system, required this.prompt});

  /// Parses the `SYSTEM` / `PROMPT` format used under `assets/prompts/`.
  factory PromptTemplate.parse(String source) {
    const systemMarker = 'SYSTEM\n';
    const promptMarker = '\nPROMPT\n';

    final split = source.indexOf(promptMarker);
    if (split < 0 || !source.startsWith(systemMarker)) {
      // A malformed asset must not be a crash during startup. The whole file
      // becomes the prompt, which is degraded but works.
      return PromptTemplate(system: '', prompt: source.trim());
    }
    return PromptTemplate(
      system: source.substring(systemMarker.length, split).trim(),
      prompt: source.substring(split + promptMarker.length).trim(),
    );
  }

  /// Instructions that frame the task.
  final String system;

  /// The body, with `{placeholders}` still in it.
  final String prompt;

  /// Substitutes `{key}` for each entry in [values].
  String fill(Map<String, String> values) {
    var filled = prompt;
    for (final entry in values.entries) {
      filled = filled.replaceAll('{${entry.key}}', entry.value);
    }
    return filled;
  }
}

/// Every prompt Van ships, loaded once at startup.
///
/// A bundle rather than three constructor arguments threaded through the
/// service: the set grows with each capability, and the alternative is a
/// signature that has to change every time one is added.
@immutable
class Prompts {
  /// Creates a bundle from already-parsed templates.
  const Prompts({
    required this.extractTask,
    required this.composeNudge,
    required this.negotiate,
  });

  /// Loads every prompt through [read], which is `rootBundle.loadString` in
  /// the app and a file read in tests.
  static Future<Prompts> load(Future<String> Function(String path) read) async {
    Future<PromptTemplate> at(String name) async =>
        PromptTemplate.parse(await read('assets/prompts/$name'));

    return Prompts(
      extractTask: await at(extractTaskAsset),
      composeNudge: await at(composeNudgeAsset),
      negotiate: await at(negotiateAsset),
    );
  }

  /// Asset names, in one place so a rename cannot miss a call site.
  static const extractTaskAsset = 'extract_task.v1.txt';

  /// See [extractTaskAsset].
  static const composeNudgeAsset = 'compose_nudge.v1.txt';

  /// See [extractTaskAsset].
  static const negotiateAsset = 'negotiate.v1.txt';

  /// Every asset Van expects to find, for tests that check they all exist.
  static const List<String> all = [
    extractTaskAsset,
    composeNudgeAsset,
    negotiateAsset,
  ];

  /// Turns a sentence into a structured task.
  final PromptTemplate extractTask;

  /// Writes the words for a nudge whose level is already chosen.
  final PromptTemplate composeNudge;

  /// Proposes a way out of a stalled block.
  final PromptTemplate negotiate;
}
