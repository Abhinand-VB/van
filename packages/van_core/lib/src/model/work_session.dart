import 'package:meta/meta.dart';

/// What happened to a planned block of work.
enum SessionStatus {
  /// Scheduled, not yet due or not yet acted on.
  planned,

  /// The user explicitly pressed START. This is Van's ground truth for
  /// "did they actually begin" - it is never inferred.
  started,

  /// Ran to the end.
  completed,

  /// Started but stopped early. Still counts as initiation, which is the
  /// behaviour Van most wants to encourage.
  partial,

  /// Never started and not moved.
  skipped,

  /// Never started, but a replacement session was created.
  rescheduled,
}

/// A concrete commitment: this task, this window, this many minutes.
///
/// Sessions are the unit Van nudges about, measures, and renegotiates. A task
/// that is never turned into a session is just a wish.
@immutable
class WorkSession {
  /// Creates a session. All instants must be UTC.
  WorkSession({
    required this.id,
    required this.taskId,
    required this.plannedStart,
    required this.plannedMinutes,
    this.actualStart,
    this.actualEnd,
    this.status = SessionStatus.planned,
    this.rescheduleCount = 0,
    this.parentSessionId,
    this.isOpener = false,
  }) : assert(plannedMinutes > 0, 'plannedMinutes must be positive'),
       assert(plannedStart.isUtc, 'plannedStart must be UTC'),
       assert(rescheduleCount >= 0, 'rescheduleCount must not be negative');

  /// Stable identifier.
  final String id;

  /// The task this session works on.
  final String taskId;

  /// When the user agreed to start. UTC.
  final DateTime plannedStart;

  /// How long the block is.
  final int plannedMinutes;

  /// When START was actually pressed. UTC. Null until it is.
  final DateTime? actualStart;

  /// When the session ended, however it ended. UTC.
  final DateTime? actualEnd;

  /// Current status.
  final SessionStatus status;

  /// How many times this piece of work has been moved. Drives escalation.
  final int rescheduleCount;

  /// The session this one replaced, if it came from a reschedule.
  final String? parentSessionId;

  /// Whether this block exists to find the first step rather than to do the
  /// work.
  ///
  /// Carried on the session rather than derived from "is it the earliest one
  /// of a deep task", because blocks move. The moment the sweep reschedules
  /// something, earliest is no longer a fact about the plan Van made, and a
  /// screen that recomputed it would rename a block by moving it.
  final bool isOpener;

  /// When the block was due to finish.
  DateTime get plannedEnd =>
      plannedStart.add(Duration(minutes: plannedMinutes));

  /// Whether START has been pressed.
  bool get hasStarted => actualStart != null;

  /// Whether this session is finished, by any route.
  bool get isResolved => const {
    SessionStatus.completed,
    SessionStatus.partial,
    SessionStatus.skipped,
    SessionStatus.rescheduled,
  }.contains(status);

  /// Minutes past [plannedStart] without a start. Zero if not yet due or
  /// already started. This is the single input the escalation ladder cares
  /// about most.
  int minutesLate(DateTime now) {
    if (hasStarted || now.isBefore(plannedStart)) return 0;
    return now.difference(plannedStart).inMinutes;
  }

  /// Whether the block is due and nothing has happened.
  bool isMissed(DateTime now) =>
      !hasStarted && status == SessionStatus.planned && now.isAfter(plannedEnd);

  /// Records an explicit START.
  WorkSession start(DateTime at) => _copy(
    actualStart: at,
    status: SessionStatus.started,
  );

  /// Records a session that ran to the end.
  WorkSession complete(DateTime at) => _copy(
    actualStart: actualStart ?? at,
    actualEnd: at,
    status: SessionStatus.completed,
  );

  /// Records a session that started but stopped early.
  WorkSession stopEarly(DateTime at) => _copy(
    actualStart: actualStart ?? at,
    actualEnd: at,
    status: SessionStatus.partial,
  );

  /// Records that this block was abandoned without a replacement.
  WorkSession skip() => _copy(status: SessionStatus.skipped);

  /// Marks this block as superseded. The replacement is a separate session
  /// carrying an incremented [rescheduleCount]; see `Rescheduler`.
  WorkSession markRescheduled() => _copy(status: SessionStatus.rescheduled);

  /// Builds the replacement session for a move to [newStart].
  ///
  /// [newMinutes] lets the caller shrink the block, which is what the L3
  /// intervention does when a full session is too big to face.
  WorkSession replacement({
    required String newId,
    required DateTime newStart,
    int? newMinutes,
  }) => WorkSession(
    id: newId,
    taskId: taskId,
    plannedStart: newStart,
    plannedMinutes: newMinutes ?? plannedMinutes,
    rescheduleCount: rescheduleCount + 1,
    parentSessionId: id,
  );

  WorkSession _copy({
    DateTime? actualStart,
    DateTime? actualEnd,
    SessionStatus? status,
  }) => WorkSession(
    id: id,
    taskId: taskId,
    plannedStart: plannedStart,
    plannedMinutes: plannedMinutes,
    actualStart: actualStart ?? this.actualStart,
    actualEnd: actualEnd ?? this.actualEnd,
    status: status ?? this.status,
    rescheduleCount: rescheduleCount,
    parentSessionId: parentSessionId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkSession &&
          id == other.id &&
          taskId == other.taskId &&
          plannedStart == other.plannedStart &&
          plannedMinutes == other.plannedMinutes &&
          actualStart == other.actualStart &&
          actualEnd == other.actualEnd &&
          status == other.status &&
          rescheduleCount == other.rescheduleCount &&
          parentSessionId == other.parentSessionId;

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    plannedStart,
    plannedMinutes,
    actualStart,
    actualEnd,
    status,
    rescheduleCount,
    parentSessionId,
  );

  @override
  String toString() =>
      'WorkSession($id, task=$taskId, ${plannedStart.toIso8601String()}, '
      '${plannedMinutes}m, ${status.name}, moved=$rescheduleCount)';
}
