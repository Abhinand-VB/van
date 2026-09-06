import 'package:van/inference/backend.dart';
import 'package:van/inference/capability.dart';
import 'package:van/inference/parsing.dart';
import 'package:van/inference/prompts.dart';
import 'package:van_core/van_core.dart';

/// The raw text a user typed, plus the instant it was typed.
class ExtractTaskInput {
  /// Creates an input.
  const ExtractTaskInput(this.text, {required this.now});

  /// What the user wrote.
  final String text;

  /// The current instant, UTC. Needed to resolve "tomorrow".
  final DateTime now;
}

/// Turns a sentence into a structured task.
///
/// The fallback is a real parser, not an apology: with no model at all, Van
/// still understands "finish the assignment by friday, 2 hours". That matters
/// because task capture is the most commoditised part of this product and the
/// least worth spending model quality on.
class ExtractTask extends Capability<ExtractTaskInput, TaskDraft> {
  /// Creates the capability over a prompt asset.
  const ExtractTask({
    required PromptTemplate prompt,
    TemporalParser parser = const TemporalParser(),
  }) : _prompt = prompt,
       _parser = parser;

  final PromptTemplate _prompt;
  final TemporalParser _parser;

  /// The parser this capability falls back to, at the device's own offset.
  ///
  /// Exposed because answering "roughly how long?" has to read a duration the
  /// same way capturing the sentence would have, and because there is exactly
  /// one correctly-configured parser in the app - the one built with the
  /// current UTC offset and rebuilt whenever it moves. A second one made at
  /// the call site is issue 19 waiting to happen again.
  TemporalParser get parser => _parser;

  @override
  String get id => 'extract_task';

  @override
  Map<String, Object?> get outputSchema => const {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'deadline': {
        'type': ['string', 'null'],
        'description': 'ISO-8601 UTC instant, or null if none was stated',
      },
      'estimatedMinutes': {
        'type': ['integer', 'null'],
      },
      'priority': {
        'type': 'string',
        'enum': ['low', 'normal', 'high'],
      },
    },
    'required': ['title'],
  };

  @override
  LlmRequest buildRequest(ExtractTaskInput input, BackendCapabilities caps) {
    final schemaHint = caps.supportsNativeStructuredOutput
        ? ''
        : '\n\nReply with only JSON of this shape:\n'
              '{"title": "...", "deadline": "2026-08-21T23:59:00Z" or null, '
              '"estimatedMinutes": 120 or null, "priority": "normal"}';

    return LlmRequest(
      system: _prompt.system,
      prompt: _prompt.fill({
        'now': input.now.toIso8601String(),
        'text': input.text,
        'schemaHint': schemaHint,
      }),
      jsonSchema: caps.supportsNativeStructuredOutput ? outputSchema : null,
      maxOutputTokens: 200,
      temperature: 0.2,
    );
  }

  @override
  TaskDraft? parse(String raw) {
    final json = JsonSalvage.extractObject(raw);
    if (json == null) return null;

    final title = JsonSalvage.readString(json, 'title');
    if (title == null) return null;

    final minutes = JsonSalvage.readInt(json, 'estimatedMinutes');
    final priority = JsonSalvage.readEnum(json, 'priority', const [
      'low',
      'normal',
      'high',
    ]);

    return TaskDraft(
      title: title,
      deadline: JsonSalvage.readUtcDateTime(json, 'deadline'),
      // A model that says zero or a negative duration has misunderstood;
      // treat it as "did not say" rather than persisting nonsense.
      estimatedMinutes: (minutes != null && minutes > 0) ? minutes : null,
      priority: switch (priority) {
        'low' => Priority.low,
        'high' => Priority.high,
        _ => Priority.normal,
      },
    );
  }

  @override
  TaskDraft fallback(ExtractTaskInput input) =>
      _parser.parse(input.text, now: input.now);
}
