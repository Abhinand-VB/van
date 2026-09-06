import 'package:meta/meta.dart';

/// How much of a task is figuring out what the task is.
///
/// Not difficulty and not importance. A three-hour tax return is shallow -
/// you know exactly what to do at every minute of it - and a twenty-minute
/// "think about whether to take the job" is deep. The distinction exists
/// because only one of them can be started by simply beginning.
enum TaskDepth {
  /// The first move is obvious. Send it, pay it, book it.
  shallow,

  /// The first move is itself work. Research, design, write, decide.
  deep,

  /// Nothing in the wording says either way.
  unknown,
}

/// A reading of a task's depth, with how much to trust it.
@immutable
class DepthReading {
  /// Creates a reading.
  const DepthReading(this.depth, this.confidence)
    : assert(
        confidence >= 0 && confidence <= 1,
        'confidence is a probability',
      );

  /// What the wording suggests.
  final TaskDepth depth;

  /// How far to trust it, from 0 to 1.
  ///
  /// **Carried because the reading is weak and pretending otherwise is the
  /// failure mode.** A verb list is a crude instrument: it cannot tell
  /// "design the poster" (deep) from "design is due friday" (shallow), and it
  /// knows nothing about what this particular person finds hard. Recording
  /// how sure Van was is what makes it possible to find out later whether the
  /// guess was worth acting on - and it is the seam a model plugs into,
  /// because a model's own confidence goes in the same field.
  final double confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DepthReading &&
          depth == other.depth &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(depth, confidence);

  @override
  String toString() => 'DepthReading(${depth.name}, $confidence)';
}

/// Guesses, from the wording alone, whether starting is the hard part.
///
/// **Deliberately weak, and honest about it.** This is a verb list and a word
/// count. It exists because depth has to change behaviour before a model is
/// worth adding - a model that improves a signal nothing acts on improves
/// nothing - and because `DepthReading.confidence` gives the model somewhere
/// to be better than this without anything downstream changing.
///
/// Pure and separate from the planner, so the rule can be argued with as a
/// rule rather than inferred from where blocks landed.
@immutable
class DepthReader {
  /// Creates the reader.
  const DepthReader();

  /// Verbs whose work begins with deciding what the work is.
  static const _deep = <String>{
    'analyse',
    'analyze',
    'brainstorm',
    'decide',
    'design',
    'draft',
    'essay',
    'figure',
    'learn',
    'outline',
    'plan',
    'prepare',
    'research',
    'revise',
    'review',
    'sketch',
    'study',
    'think',
    'understand',
    'write',
  };

  /// Verbs whose first move is the whole move.
  static const _shallow = <String>{
    'add',
    'book',
    'buy',
    'call',
    'cancel',
    'check',
    'clean',
    'confirm',
    'email',
    'file',
    'fill',
    'forward',
    'message',
    'order',
    'pay',
    'phone',
    'post',
    'print',
    'register',
    'renew',
    'reply',
    'return',
    'send',
    'sign',
    'submit',
    'text',
    'tidy',
    'upload',
  };

  /// Nouns that name a piece of work rather than an errand, even with no verb
  /// in front of them. "The assignment" is deep whatever you do to it.
  static const _deepNouns = <String>{
    'assignment',
    'chapter',
    'dissertation',
    'essay',
    'proposal',
    'report',
    'thesis',
  };

  /// Reads [title], with [statedMinutes] as a second opinion.
  ///
  /// The verb decides and the duration only nudges, in that order. Someone who
  /// says "two hours" has told Van how long, not what kind of work it is, and
  /// a length that outranked the wording would call every long errand deep.
  DepthReading read(String title, {int? statedMinutes}) {
    final words = title
        .toLowerCase()
        .split(RegExp('[^a-z]+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final deep = words.indexWhere(_deep.contains);
    final shallow = words.indexWhere(_shallow.contains);
    final deepNoun = words.any(_deepNouns.contains);

    // Both kinds of verb in one sentence - "email the design brief" - and the
    // reader has no business being confident either way. The earlier verb is
    // usually the actual instruction, so it wins, but barely.
    if (deep >= 0 && shallow >= 0) {
      return DepthReading(
        deep < shallow ? TaskDepth.deep : TaskDepth.shallow,
        0.35,
      );
    }

    if (shallow >= 0) {
      // A "shallow" errand quoted at half a day is not an errand. Say unknown
      // rather than insisting, because the two signals genuinely disagree.
      return statedMinutes != null && statedMinutes > 180
          ? const DepthReading(TaskDepth.unknown, 0.2)
          : const DepthReading(TaskDepth.shallow, 0.7);
    }

    if (deep >= 0) return const DepthReading(TaskDepth.deep, 0.6);
    if (deepNoun) return const DepthReading(TaskDepth.deep, 0.5);

    // No verb Van knows. A long quoted duration is the only thing left worth
    // reading anything into, and it is worth very little.
    if (statedMinutes != null && statedMinutes >= 180) {
      return const DepthReading(TaskDepth.deep, 0.3);
    }
    return const DepthReading(TaskDepth.unknown, 0.1);
  }
}
