/// The words Van uses about a plan it made, in one place.
///
/// Here rather than in `van_core` because that package holds no English the
/// user reads, and here rather than inline in each screen because the Now
/// card, the focus timer and the calendar all name the same block and must
/// not name it three different things.
library;

import 'package:flutter/material.dart';
import 'package:van_core/van_core.dart';

/// The wording Van uses to ask about [clarification].
///
/// Here rather than in `van_core` because it is copy the user reads, and that
/// package holds no English. A model that supplied its own question wins:
/// the standard wording is the floor, not the ceiling, which is what makes
/// "with a model this becomes a much better question" true without anything
/// around it changing.
///
/// The examples are load-bearing. "Roughly how long?" on its own invites "a
/// while"; naming two units gets a number back, and a bare number is read as
/// minutes precisely because these examples set that expectation.
String questionFor(Clarification clarification) =>
    clarification.question ??
    switch (clarification.field) {
      TaskField.duration => 'Roughly how long? e.g. 45 minutes, or 2 hours',
      TaskField.deadline => 'When does this need to be done by?',
    };

/// What an opening block is for, in the words shown on it.
///
/// A block named "Write the dissertation" and lasting twenty-five minutes
/// reads as Van having got the estimate wrong. Naming it for its actual job
/// is the difference between a strange short block and an obviously sensible
/// one, and it is most of why depth is worth reading at all: the point was
/// never to classify the task, it was to make the first block startable.
const openerLabel = 'Work out where to start';

/// What Van says it assumed, so a guess never passes for a statement.
String assumptionOf(int minutes) => minutes % 60 == 0
    ? 'assumed ${minutes ~/ 60} ${minutes == 60 ? "hour" : "hours"}'
    : 'assumed $minutes minutes';

/// The question Van is waiting on, sitting where the answer will be typed.
///
/// A bar rather than a dialog, and this is the whole difference between
/// asking and interrupting. A dialog steals the field, clears what was typed
/// and demands an answer before anything else can happen; this sits under the
/// composer with the task already captured and already planned behind it, and
/// dismissing it costs nothing because the work was never waiting on it.
class ClarifyBar extends StatelessWidget {
  /// Creates the bar.
  const ClarifyBar({
    required this.clarification,
    required this.about,
    required this.onDismiss,
    this.assumed,
    super.key,
  });

  /// What is being asked.
  final Clarification clarification;

  /// The task it is about, named so the question cannot be about the wrong
  /// thing after a second capture.
  final String about;

  /// The duration Van used in the meantime, in minutes.
  final int? assumed;

  /// Drops the question. The plan Van already made stands.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;
    final assumption = assumed;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: colours.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$about — ${questionFor(clarification)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colours.onSecondaryContainer,
                  ),
                ),
                if (assumption != null)
                  Text(
                    'Scheduled on an ${assumptionOf(assumption)} for now.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colours.onSecondaryContainer.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            color: colours.onSecondaryContainer,
            onPressed: onDismiss,
            tooltip: 'Leave it',
          ),
        ],
      ),
    );
  }
}

/// How an estimate reads on a card, with a default when nobody has said.
///
/// **It never renders as blank or as "unknown".** A card that says nothing
/// about how long the work is invites no correction, and the whole point of
/// showing this is that correcting a number is far easier than inventing one.
/// So an unstated estimate shows the planner's own assumption, marked as one.
String estimateLabel(int? stated, int fallback) {
  final minutes = stated ?? fallback;
  final text = minutes % 60 == 0 && minutes >= 60
      ? '${minutes ~/ 60}h'
      : minutes > 60
      ? '${minutes ~/ 60}h ${minutes % 60}m'
      : '${minutes}m';
  return stated == null ? '$text (assumed)' : text;
}

/// Edits how long a task is expected to take.
///
/// A sheet rather than an inline field, because an inline field on a card
/// fights the keyboard for the card it is editing. Opens pre-filled and with
/// the presets people actually pick, so the common case is one tap and the
/// uncommon one is still typeable.
///
/// **The field does not autofocus, and that is a fix rather than an
/// omission.** It did, and on the phone the keyboard came straight up over
/// the presets and overflowed the sheet by 152 pixels - which no widget test
/// could see, because a test surface has no keyboard. Presets are the common
/// case; the keyboard belongs to the uncommon one and can wait to be asked
/// for. The sheet scrolls as well, so the same mistake cannot cost a layout
/// again.
///
/// Open it with `isScrollControlled: true` or it is capped at half the
/// screen with a keyboard up.
class EstimateSheet extends StatefulWidget {
  /// Creates the sheet.
  const EstimateSheet({
    required this.title,
    required this.initialMinutes,
    required this.isAssumed,
    super.key,
  });

  /// The task being estimated, named so the sheet cannot be about the wrong
  /// one.
  final String title;

  /// What to open with. Never zero and never blank - see [estimateLabel].
  final int initialMinutes;

  /// Whether [initialMinutes] is Van's assumption rather than the user's
  /// figure, which is worth saying out loud on the one screen that can fix it.
  final bool isAssumed;

  @override
  State<EstimateSheet> createState() => _EstimateSheetState();
}

class _EstimateSheetState extends State<EstimateSheet> {
  late final _field = TextEditingController(text: '${widget.initialMinutes}');

  /// The lengths a person actually picks. Not a scale - a shortlist.
  static const _presets = [15, 25, 45, 60, 90, 120, 180];

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final minutes = int.tryParse(_field.text.trim());
    // Refusing zero here rather than downstream, so the sheet stays open with
    // the bad value visible instead of closing and silently changing nothing.
    if (minutes == null || minutes <= 0) return;
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.isAssumed
                ? 'Nobody said how long, so Van assumed this.'
                : 'How long you said it would take.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in _presets)
                ActionChip(
                  label: Text(estimateLabel(preset, preset)),
                  onPressed: () => Navigator.of(context).pop(preset),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _field,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
