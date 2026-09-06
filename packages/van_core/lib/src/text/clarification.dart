import 'package:meta/meta.dart';
import 'package:van_core/src/text/temporal_parser.dart';

/// A part of a task Van may need to be told about.
///
/// Two members although only one of them is ever asked about today. The
/// deterministic rule below asks about duration and nothing else, but a model
/// answering the same question may reasonably decide the deadline is the
/// missing piece - and a type that could not carry that answer would put the
/// model back behind a type change, which is exactly the trap
/// `docs/WP_JUDGEMENT.md` section 1 is about.
enum TaskField {
  /// How long the work will take.
  duration,

  /// When it is due.
  deadline,
}

/// Something Van needs to know before it can plan honestly.
///
/// Carries the field so the caller knows what an answer would mean, and an
/// optional better-worded [question] so a model can improve the asking
/// without anything around it changing.
@immutable
class Clarification {
  /// Creates a question about [field].
  const Clarification({required this.field, this.question});

  /// What Van is short of.
  final TaskField field;

  /// A specific question, when something could write a better one than the
  /// standard wording for [field]. Null is the normal case.
  ///
  /// The standard wording is not here on purpose: it is user-facing copy and
  /// this package holds no English the user reads.
  final String? question;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Clarification &&
          field == other.field &&
          question == other.question;

  @override
  int get hashCode => Object.hash(field, question);

  @override
  String toString() => 'Clarification(${field.name}, $question)';
}

/// Decides whether a captured sentence left Van guessing.
///
/// **This is the whole of "Van asks when it does not know" and it needs no
/// model.** Before it, `SessionPlanner` substituted `defaultEstimateMinutes`
/// for a task nobody had given a duration for and blocked out time as though
/// the user had said so. The plan looked identical whether they had said an
/// hour or said nothing at all, which is the difference between a schedule
/// and a guess wearing one.
///
/// Pure, and separate from [TemporalParser] deliberately: the parser's job is
/// to report what a sentence said, and deciding that a silence is worth
/// interrupting someone over is a product judgement, not a reading of the
/// text.
@immutable
class CaptureQuestions {
  /// Creates the rule set.
  const CaptureQuestions();

  /// The one thing worth asking about [draft], or null to say nothing.
  ///
  /// **One question, never a form.** A person capturing a thought is not
  /// filling in a record, and a second question is how a two-second capture
  /// becomes a dialog they learn to dismiss. So when more than one thing is
  /// missing, only the most consequential is asked about.
  ///
  /// **Duration outranks deadline, and it is the only thing asked about
  /// today.** Without a duration the planner cannot proceed honestly - it has
  /// to invent one. Without a deadline it can: work with no deadline is
  /// scheduled soon rather than wrongly, which is a plan and not a guess. So
  /// a missing deadline is a silence Van can live with and a missing duration
  /// is not.
  Clarification? about(TaskDraft draft) => draft.estimatedMinutes == null
      ? const Clarification(field: TaskField.duration)
      : null;
}
