import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/capability.dart';
import 'package:van/inference/parsing.dart';
import 'package:van/inference/prompts.dart';
import 'package:van_core/van_core.dart';

/// Everything needed to write one line of nudge copy.
@immutable
class NudgeCopyRequest {
  /// Creates a request.
  const NudgeCopyRequest({
    required this.type,
    required this.level,
    required this.taskTitle,
    this.minutes = 25,
    this.minutesLate = 0,
    this.moves = 0,
  });

  /// The kind of interruption.
  final NudgeType type;

  /// How hard it should push. Chosen by the policy, never by a model.
  final InterventionLevel level;

  /// What the work is called.
  final String taskTitle;

  /// Length of the block.
  final int minutes;

  /// Minutes past the planned start.
  final int minutesLate;

  /// How many times this work has been moved.
  final int moves;

  /// Key into the template bank.
  String get templateKey => '${type.name}_${level.name}';
}

/// A line of copy, and where it came from.
@immutable
class NudgeCopy {
  /// Creates a line.
  const NudgeCopy(this.text, {this.templateId});

  /// What to show the user.
  final String text;

  /// Which template produced it, or null when a model wrote it.
  final String? templateId;
}

/// A bank of hand-written nudge lines with a no-repeat rotation.
///
/// The rotation is the point. A 2B model has a narrow stylistic range and will
/// converge on the same handful of phrasings within a week; hand-written
/// variants that never repeat within a window beat it comfortably, and cost
/// nothing to run. This is why Van is usable with no model at all.
class NudgeTemplates {
  /// Creates a bank from decoded JSON.
  NudgeTemplates(this._byKey, {Random? random}) : _random = random ?? Random();

  /// Parses the asset at `assets/nudge_templates/templates.json`.
  factory NudgeTemplates.fromJson(String source, {Random? random}) {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final byKey = <String, List<String>>{};
    for (final entry in decoded.entries) {
      if (entry.key.startsWith('_')) continue;
      final values = entry.value;
      if (values is! List) continue;
      byKey[entry.key] = values.whereType<String>().toList();
    }
    return NudgeTemplates(byKey, random: random);
  }

  final Map<String, List<String>> _byKey;
  final Random _random;

  /// The last two indices used per key, so neither is picked again.
  final _recent = <String, List<int>>{};

  /// How many variants exist for [key].
  int variantCount(String key) => _byKey[key]?.length ?? 0;

  /// Picks a line for [request], avoiding the two most recent for that key.
  NudgeCopy pick(NudgeCopyRequest request) {
    // The bank has a line for every level of sessionMissed and only l0Gentle
    // for sessionStart, so five of the twelve combinations have no entry -
    // and Negotiate asks for one of them whenever it proposes at l3 or above
    // for a block that is not yet a whole minute late.
    //
    // Falling straight back to `sessionMissed_l0Gentle` answered those with a
    // gentle "not started yet?" while Van was shrinking or conceding the
    // block: the words and the action disagreeing, which is the one thing the
    // copy must never do. Dropping the *type* keeps the level, and the level
    // is what carries the tone.
    final key = request.templateKey;
    final sameLevel = '${NudgeType.sessionMissed.name}_${request.level.name}';
    final usedKey = _byKey.containsKey(key)
        ? key
        : _byKey.containsKey(sameLevel)
        ? sameLevel
        : 'sessionMissed_l0Gentle';

    final options = _byKey[usedKey] ?? const <String>[];
    if (options.isEmpty) {
      return NudgeCopy('${request.taskTitle}.', templateId: 'builtin_bare');
    }

    // Both the id and the recent-list are keyed on what was *used*, not what
    // was asked for. Reporting the requested key made `templateId` lie in the
    // event log every time a fallback ran, and tracking recency under it meant
    // the indices were counted against a list they did not come from.
    final recent = _recent[usedKey] ?? <int>[];
    final eligible = <int>[
      for (var i = 0; i < options.length; i++)
        if (!recent.contains(i)) i,
    ];
    final pool = eligible.isEmpty
        ? [for (var i = 0; i < options.length; i++) i]
        : eligible;

    final index = pool[_random.nextInt(pool.length)];
    _recent[usedKey] = [
      ...recent,
      index,
    ].reversed.take(2).toList().reversed.toList();

    return NudgeCopy(
      _fill(options[index], request),
      templateId: '$usedKey#$index',
    );
  }

  String _fill(String template, NudgeCopyRequest request) => template
      .replaceAll('{task}', request.taskTitle)
      .replaceAll('{minutes}', '${request.minutes}')
      .replaceAll('{late}', '${request.minutesLate}')
      .replaceAll('{moves}', '${request.moves}');
}

/// Writes the words for a nudge whose level has already been decided.
class ComposeNudge extends Capability<NudgeCopyRequest, NudgeCopy> {
  /// Creates the capability over a prompt asset and a template bank.
  const ComposeNudge(this._templates, {required PromptTemplate prompt})
    : _prompt = prompt;

  final NudgeTemplates _templates;
  final PromptTemplate _prompt;

  @override
  String get id => 'compose_nudge';

  @override
  Map<String, Object?> get outputSchema => const {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'maxLength': 140},
    },
    'required': ['text'],
  };

  @override
  LlmRequest buildRequest(NudgeCopyRequest input, BackendCapabilities caps) {
    return LlmRequest(
      system: _prompt.system,
      prompt: _prompt.fill({
        'level': input.level.name,
        'task': input.taskTitle,
        'minutes': '${input.minutes}',
        'late': '${input.minutesLate}',
        'moves': '${input.moves}',
      }),
      jsonSchema: caps.supportsNativeStructuredOutput ? outputSchema : null,
      maxOutputTokens: 80,
      temperature: 0.9,
    );
  }

  @override
  NudgeCopy? parse(String raw) {
    final json = JsonSalvage.extractObject(raw);
    if (json == null) return null;
    final text = JsonSalvage.readString(json, 'text');
    if (text == null || text.length > 200) return null;
    return NudgeCopy(text);
  }

  @override
  NudgeCopy fallback(NudgeCopyRequest input) => _templates.pick(input);
}
