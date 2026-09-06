import 'package:meta/meta.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capability.dart';
import 'package:van/inference/parsing.dart';
import 'package:van/inference/prompts.dart';
import 'package:van_core/van_core.dart';

/// Everything Van knows about a block that is not starting.
@immutable
class NegotiationRequest {
  /// Creates a request.
  const NegotiationRequest({
    required this.taskTitle,
    required this.minutes,
    this.minutesLate = 0,
    this.moves = 0,
    this.hoursToDeadline,
    this.priorResponses = const [],
    this.userGaveReason = false,
    this.reasonText,
    this.userRefused = false,
    this.evidence = NegotiationEvidence.none,
  });

  /// What the work is called.
  final String taskTitle;

  /// How long the block is now.
  final int minutes;

  /// Minutes past the planned start with no start recorded.
  final int minutesLate;

  /// How many times this work has already been moved.
  final int moves;

  /// Hours until the task is due, if it has a deadline.
  final double? hoursToDeadline;

  /// How the user answered earlier nudges about this block, oldest first.
  final List<ResponseType> priorResponses;

  /// Whether they explained themselves rather than just ignoring it.
  final bool userGaveReason;

  /// What they said, when they said anything.
  final String? reasonText;

  /// Whether they have said no outright.
  final bool userRefused;

  /// What the log knows about this block: whether it was ever started, how
  /// this hour of day usually goes, how full the calendar is around it.
  ///
  /// Every one of these was already in the database and none of it reached
  /// the prompt. See `WP_JUDGEMENT.md` 13c.
  final NegotiationEvidence evidence;

  /// The facts the ladder needs to pick a level.
  InterventionContext get interventionContext => InterventionContext(
    minutesLate: minutesLate,
    rescheduleCount: moves,
    hoursToDeadline: hoursToDeadline,
    priorResponses: priorResponses,
    userGaveReason: userGaveReason,
    userRefused: userRefused,
  );
}

/// Proposes a way out of a stalled block, and writes the line for it.
///
/// The one capability whose output is an *action* rather than text, which is
/// why it is the one that most needs the rule in AGENTS.md: the model never
/// mutates state. It returns a [NegotiationProposal], and `NegotiationRules`
/// in the domain decides whether Van is allowed to act on it.
///
/// The level is never the model's to choose. `InterventionPolicy` picks it
/// before the prompt is built, and the prompt is told which actions that level
/// permits. A model that proposes outside them is refused and the deterministic
/// fallback runs instead - so the worst a bad model can do here is be useless,
/// never destructive.
class Negotiate extends Capability<NegotiationRequest, NegotiationProposal> {
  /// Creates the capability over a prompt asset and a template bank.
  const Negotiate({
    required PromptTemplate prompt,
    required NudgeTemplates templates,
    InterventionPolicy policy = const InterventionPolicy(),
    NegotiationRules rules = const NegotiationRules(),
  }) : _prompt = prompt,
       _templates = templates,
       _policy = policy,
       _rules = rules;

  final PromptTemplate _prompt;
  final NudgeTemplates _templates;
  final InterventionPolicy _policy;
  final NegotiationRules _rules;

  @override
  String get id => 'negotiate';

  @override
  Map<String, Object?> get outputSchema => const {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['hold', 'shrink', 'defer', 'release'],
      },
      'shrinkToMinutes': {
        'type': ['integer', 'null'],
      },
      'deferByMinutes': {
        'type': ['integer', 'null'],
      },
      'message': {'type': 'string', 'maxLength': 140},
    },
    'required': ['action', 'message'],
  };

  /// The level the ladder picks for [input]. Deterministic, always.
  InterventionLevel levelFor(NegotiationRequest input) =>
      _policy.select(input.interventionContext);

  /// The facts a proposal for [input] must be judged against.
  NegotiationContext contextFor(NegotiationRequest input) => NegotiationContext(
    level: levelFor(input),
    currentMinutes: input.minutes,
    hoursToDeadline: input.hoursToDeadline,
    evidence: input.evidence,
  );

  @override
  LlmRequest buildRequest(NegotiationRequest input, BackendCapabilities caps) {
    final level = levelFor(input);
    // What the level permits, minus anything the evidence has taken off the
    // table. Telling the model an action is available and then refusing it is
    // how a model learns nothing and the user gets a template.
    final allowed =
        _rules
            .allowedAt(level)
            .where(
              (action) => _rules.permits(
                _probe(action, input),
                contextFor(input),
              ),
            )
            .map((a) => a.name)
            .toList()
          ..sort();

    return LlmRequest(
      system: _prompt.system,
      prompt: _prompt.fill({
        'task': input.taskTitle,
        'minutes': '${input.minutes}',
        'late': '${input.minutesLate}',
        'moves': '${input.moves}',
        'deadline': input.hoursToDeadline == null
            ? 'none'
            : input.hoursToDeadline!.toStringAsFixed(1),
        'level': level.name,
        'allowed': allowed.join(', '),
        'reason': input.reasonText ?? 'nothing',
        'started': input.evidence.everStarted
            ? 'yes, at least once'
            : 'never, not once',
        'hourRate': _hourRate(input.evidence),
        'calendar': _calendar(input.evidence),
      }),
      jsonSchema: caps.supportsNativeStructuredOutput ? outputSchema : null,
      maxOutputTokens: 160,
      temperature: 0.6,
    );
  }

  @override
  NegotiationProposal? parse(String raw) {
    final json = JsonSalvage.extractObject(raw);
    if (json == null) return null;

    final message = JsonSalvage.readString(json, 'message');
    if (message == null || message.trim().isEmpty) return null;

    final action = _actionFrom(JsonSalvage.readString(json, 'action'));
    if (action == null) return null;

    return NegotiationProposal(
      action: action,
      message: message.trim(),
      shrinkToMinutes: JsonSalvage.readInt(json, 'shrinkToMinutes'),
      deferByMinutes: JsonSalvage.readInt(json, 'deferByMinutes'),
    );
  }

  /// A minimal well-formed proposal for [action], used only to ask the rules
  /// whether that action is available at all.
  ///
  /// The amounts are the smallest legal ones rather than anything Van would
  /// actually offer: this is a question about the *action*, and a probe that
  /// failed on its own size would answer the wrong one.
  NegotiationProposal _probe(
    NegotiationAction action,
    NegotiationRequest input,
  ) => NegotiationProposal(
    action: action,
    message: '.',
    shrinkToMinutes: input.minutes > _rules.minimumBlockMinutes
        ? _rules.minimumBlockMinutes
        : null,
    deferByMinutes: _rules.minimumDeferMinutes,
  );

  static String _hourRate(NegotiationEvidence evidence) {
    final rate = evidence.startRateAtHour;
    if (rate == null) return 'not enough history to say';
    return '${evidence.startsAtThisHour} of ${evidence.blocksAtThisHour} '
        'blocks at this hour were started';
  }

  static String _calendar(NegotiationEvidence evidence) {
    if (evidence.calendarWindowMinutes == 0) return 'not read';
    final percent = (evidence.calendarDensity * 100).round();
    return '$percent% of the hours around this block are already committed';
  }

  static NegotiationAction? _actionFrom(String? name) {
    for (final action in NegotiationAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }

  /// The ladder's own answer: the level it picked, and a template for it.
  ///
  /// Deliberately conservative. With no model, Van proposes the smallest thing
  /// the level allows rather than the largest - a wrong `hold` costs one more
  /// notification, a wrong `release` loses the work.
  @override
  NegotiationProposal fallback(NegotiationRequest input) {
    final level = levelFor(input);
    final copy = _templates.pick(
      NudgeCopyRequest(
        type: input.minutesLate == 0
            ? NudgeType.sessionStart
            : NudgeType.sessionMissed,
        level: level,
        taskTitle: input.taskTitle,
        minutes: input.minutes,
        minutesLate: input.minutesLate,
        moves: input.moves,
      ),
    );

    final action = _fallbackAction(input, level);
    return NegotiationProposal(
      action: action,
      message: copy.text,
      shrinkToMinutes: action == NegotiationAction.shrink
          ? _halved(input.minutes)
          : null,
      templateId: copy.templateId,
    );
  }

  NegotiationAction _fallbackAction(
    NegotiationRequest input,
    InterventionLevel level,
  ) {
    // Conceding is only right when the block can no longer be salvaged by
    // making it smaller. Halving a 20-minute block lands under the floor.
    if (InterventionPolicy.concedes(level)) {
      return _halved(input.minutes) == null
          ? NegotiationAction.release
          : NegotiationAction.shrink;
    }
    if (InterventionPolicy.offersShrink(level) &&
        _halved(input.minutes) != null) {
      return NegotiationAction.shrink;
    }
    return NegotiationAction.hold;
  }

  /// Half of [minutes], or null when that would be too small to be work.
  int? _halved(int minutes) {
    final half = minutes ~/ 2;
    return half >= _rules.minimumBlockMinutes ? half : null;
  }
}
