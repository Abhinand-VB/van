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
