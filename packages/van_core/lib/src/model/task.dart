import 'package:meta/meta.dart';
import 'package:van_core/src/text/depth_reader.dart';

/// Where a task is in its life.
enum TaskStatus {
  /// Captured but not yet scheduled.
  inbox,

  /// Has planned sessions.
  active,

  /// Finished.
  done,

  /// Deliberately given up on. Distinct from [done] because the difference
  /// matters when learning what this person actually follows through on.
  abandoned,
}

/// How the task got into Van. Recorded because capture friction is one of the
/// things worth measuring later.
enum TaskSource {
  /// Typed into the chat interface.
  chat,

  /// Typed into the one-line field on the Now screen.
  quickAdd,

  /// Extracted from a pasted URL. Phase 4.
  link,
}

/// How much this matters relative to everything else due around the same time.
enum Priority {
  /// Nice to do.
  low,

  /// The default.
  normal,

  /// Should displace other work.
  high,
}

/// Something the user intends to do.
///
/// A task carries intent and a deadline; the actual commitments live in
/// `WorkSession`s derived from it. Splitting the two is what lets Van shrink
/// or move work without losing the original promise.
@immutable
class Task {
  /// Creates a task. All instants must be UTC.
  Task({
    required this.id,
    required this.title,
    required this.createdAt,
    this.notes,
    this.deadline,
    this.estimatedMinutes,
    this.priority = Priority.normal,
    this.status = TaskStatus.inbox,
    this.source = TaskSource.quickAdd,
    this.depth = TaskDepth.unknown,
    this.actualMinutes,
  }) : assert(title.isNotEmpty, 'a task must have a title'),
       assert(
         estimatedMinutes == null || estimatedMinutes > 0,
         'estimatedMinutes must be positive when known',
       ),
       assert(
         actualMinutes == null || actualMinutes > 0,
         'actualMinutes must be positive when known',
       ),
       assert(createdAt.isUtc, 'createdAt must be UTC'),
       assert(deadline == null || deadline.isUtc, 'deadline must be UTC');

  /// Stable identifier.
  final String id;

  /// What the user called it, in their words.
  final String title;

  /// Free text captured alongside the title.
  final String? notes;

  /// When it is due, if the user said. UTC.
  final DateTime? deadline;

  /// Total effort in minutes, if known. Null means Van has not asked yet.
  final int? estimatedMinutes;

  /// Relative importance.
  final Priority priority;

  /// Lifecycle position.
  final TaskStatus status;

  /// When it was captured. UTC.
  final DateTime createdAt;

  /// How it was captured.
  final TaskSource source;

  /// Whether starting is itself the work.
  ///
  /// Persisted rather than re-read at plan time, because a task is re-planned
  /// long after the sentence that made it - by the sweep, by a reschedule, by
  /// an answered question - and re-reading the title each time would let the
  /// same task be deep on Monday and shallow on Tuesday because a verb list
  /// changed underneath it.
  ///
  /// How sure Van was is deliberately *not* here: nothing reads it, and it is
  /// recorded in the `taskCreated` event instead. See `DECISIONS_PENDING.md`
  /// D73.
  final TaskDepth depth;

  /// How long the work actually took, in minutes, once someone said.
  ///
  /// **This is the only number in Van that can tell an estimate it was
  /// wrong.** Everything else the app records is about whether work started;
  /// this is about whether the size of it was ever right. Null until it is
  /// given, and it is never inferred: a block that ran for forty minutes is
  /// evidence of forty minutes at the desk, not of a task that took forty
  /// minutes, and quietly conflating the two would put a number here that
  /// nobody stands behind.
  final int? actualMinutes;

  /// How far the estimate was out, as a multiple. Null until both are known.
  ///
  /// Greater than one means it took longer than planned, which is the
  /// direction that matters: an under-run costs a free afternoon, an over-run
  /// costs everything scheduled after it.
  double? get estimateRatio =>
      (estimatedMinutes == null || actualMinutes == null)
      ? null
      : actualMinutes! / estimatedMinutes!;

  /// Whether a deadline exists and has passed as of [now].
  bool isOverdue(DateTime now) =>
      deadline != null && now.isAfter(deadline!) && status != TaskStatus.done;

  /// Hours remaining until the deadline, or null when there is no deadline.
  /// Negative once the deadline has passed.
  double? hoursUntilDeadline(DateTime now) => deadline == null
      ? null
      : deadline!.difference(now).inMinutes / Duration.minutesPerHour;

  /// Returns a copy with the given fields replaced. Null means unchanged; use
  /// the dedicated methods below to clear a field.
  Task copyWith({
    String? title,
    String? notes,
    DateTime? deadline,
    int? estimatedMinutes,
    Priority? priority,
    TaskStatus? status,
    TaskSource? source,
    TaskDepth? depth,
    int? actualMinutes,
  }) => Task(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    notes: notes ?? this.notes,
    deadline: deadline ?? this.deadline,
    estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    source: source ?? this.source,
    depth: depth ?? this.depth,
    actualMinutes: actualMinutes ?? this.actualMinutes,
  );

  /// Returns a copy with no deadline.
  Task withoutDeadline() => Task(
    id: id,
    title: title,
    createdAt: createdAt,
    notes: notes,
    estimatedMinutes: estimatedMinutes,
    priority: priority,
    status: status,
    source: source,
    depth: depth,
    actualMinutes: actualMinutes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          id == other.id &&
          title == other.title &&
          notes == other.notes &&
          deadline == other.deadline &&
          estimatedMinutes == other.estimatedMinutes &&
          priority == other.priority &&
          status == other.status &&
          createdAt == other.createdAt &&
          source == other.source &&
          depth == other.depth &&
          actualMinutes == other.actualMinutes;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    deadline,
    estimatedMinutes,
    priority,
    status,
    createdAt,
    source,
    depth,
    actualMinutes,
  );

  @override
  String toString() => 'Task($id, "$title", ${status.name})';
}
