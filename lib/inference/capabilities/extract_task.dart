import 'package:van/inference/backend.dart';
import 'package:van/inference/capability.dart';
import 'package:van/inference/parsing.dart';
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
  /// Creates the capability.
  const ExtractTask({TemporalParser parser = const TemporalParser()})
    : _parser = parser;

  final TemporalParser _parser;

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
      system:
          'You extract a single task from a sentence. Do not invent a '
          'deadline or a duration that was not stated - null is correct and '
          'a wrong deadline is worse than none. The title must not repeat '
          'the date or duration wording.',
      prompt:
          'Current time (UTC): ${input.now.toIso8601String()}\n'
          'Sentence: ${input.text}$schemaHint',
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
