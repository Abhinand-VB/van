import 'dart:async';

import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/router.dart';
import 'package:van/platform/notifications.dart';
import 'package:van_core/van_core.dart';

/// What happened when a sentence was captured.
class CaptureResult {
  /// Creates a result.
  const CaptureResult({
    required this.task,
    required this.sessions,
    this.shortfallMinutes = 0,
  });

  /// The task that was stored.
  final Task task;

  /// The blocks that were scheduled.
  final List<WorkSession> sessions;

  /// Minutes that would not fit before the deadline. Zero when it all fit.
  final int shortfallMinutes;

  /// Whether some of the work could not be placed.
  bool get isPartial => shortfallMinutes > 0;
}

/// Appends inference outcomes to the event log.
///
/// Lives here rather than in `lib/inference/` so the inference layer never
/// reaches into the data layer.
class EventLogInferenceObserver implements InferenceObserver {
  /// Creates an observer over [_events].
  EventLogInferenceObserver(this._events);

  final EventRepo _events;

  @override
  void onInference({
    required String capabilityId,
    required String backendId,
    required InferenceOutcome outcome,
    String? failureReason,
    int? latencyMs,
  }) {
    // Fire and forget: the observer interface is synchronous because callers
    // must not be made to wait on logging, and a failed log must never fail
    // the inference it was describing.
    unawaited(
      _events.append(
        outcome == InferenceOutcome.model
            ? EventType.inferenceOk
            : EventType.inferenceFallback,
        {
          'capability': capabilityId,
          'backend': backendId,
          'reason': ?failureReason,
          'latencyMs': ?latencyMs,
        },
      ),
    );
  }
}

/// The one place where capture, planning, persistence, notification and the
/// event log meet.
///
/// The UI calls this and nothing below it. Every method that changes something
/// writes an event, because a decision Van cannot explain later is a decision
/// it cannot learn from.
class VanService {
  /// Creates the service.
  VanService({
    required TaskRepo tasks,
    required SessionRepo sessions,
    required EventRepo events,
    required InferenceRouter router,
    required Notifications notifications,
    required NudgeTemplates templates,
    required Clock clock,
    required IdGenerator ids,
    WakingHours waking = const WakingHours(),
    InterventionPolicy policy = const InterventionPolicy(),
  }) : _tasks = tasks,
       _sessions = sessions,
       _events = events,
       _router = router,
       _notifications = notifications,
       _templates = templates,
       _clock = clock,
       _ids = ids,
       _waking = waking,
       _policy = policy;

  final TaskRepo _tasks;
  final SessionRepo _sessions;
  final EventRepo _events;
  final InferenceRouter _router;
  final Notifications _notifications;
  final NudgeTemplates _templates;
  final Clock _clock;
  final IdGenerator _ids;
  final WakingHours _waking;
  final InterventionPolicy _policy;

  /// Captures [text], plans it, stores it and arms the notifications.
  Future<CaptureResult> capture(String text) async {
    final now = _clock.now();

    final draft = await _router.run(
      const ExtractTask(),
      ExtractTaskInput(text, now: now),
    );

    final task = Task(
      id: _ids.next(),
      title: draft.title,
      createdAt: now,
      deadline: draft.deadline,
      estimatedMinutes: draft.estimatedMinutes,
      priority: draft.priority,
      status: TaskStatus.active,
      source: TaskSource.quickAdd,
    );
    await _tasks.save(task);
    await _events.append(EventType.taskCreated, {
      'taskId': task.id,
      'title': task.title,
      'deadline': task.deadline?.toIso8601String(),
      'estimatedMinutes': task.estimatedMinutes,
    });

    final planned = await _planFor(task, now);
    return planned;
  }

  Future<CaptureResult> _planFor(Task task, DateTime now) async {
    final existing = await _sessions.unresolved();
    final slots = FreeSlotFinder(waking: _waking).find(
      commitments: [
        for (final s in existing)
          Commitment(start: s.plannedStart, end: s.plannedEnd, label: s.taskId),
      ],
      from: now,
      to: now.add(const Duration(days: 7)),
    );

    final result = SessionPlanner(
      ids: _ids,
      waking: _waking,
    ).plan(task: task, slots: slots, clock: _clock);

    final sessions = result.okOrNull ?? result.errOrNull!.scheduled;
    final shortfall = result.errOrNull?.shortfallMinutes ?? 0;

    if (sessions.isNotEmpty) {
      await _sessions.saveAll(sessions);
      for (final session in sessions) {
        await _events.append(EventType.sessionPlanned, {
          'sessionId': session.id,
          'taskId': task.id,
          'start': session.plannedStart.toIso8601String(),
          'minutes': session.plannedMinutes,
        });
        await _armLadder(session, task);
      }
    }

    return CaptureResult(
      task: task,
      sessions: sessions,
      shortfallMinutes: shortfall,
    );
  }

  /// Pre-schedules the escalation ladder for [session].
  ///
  /// The prompt at the start, the check ten minutes later, the diagnose at
  /// twenty-five. All three are cancelled the moment the user responds, so an
  /// answered nudge never escalates behind their back.
  Future<void> _armLadder(WorkSession session, Task task) async {
    final rungs = <(InterventionLevel, int)>[
      (InterventionLevel.l0Gentle, 0),
      (InterventionLevel.l1Check, _policy.checkAfterMinutes),
      (InterventionLevel.l2Diagnose, _policy.diagnoseAfterMinutes),
    ];

    for (var i = 0; i < rungs.length; i++) {
      final (level, offset) = rungs[i];
      final at = session.plannedStart.add(Duration(minutes: offset));
      if (at.isBefore(_clock.now())) continue;

      final type = offset == 0
          ? NudgeType.sessionStart
          : NudgeType.sessionMissed;
      final copy = await _router.run(
        ComposeNudge(_templates),
        NudgeCopyRequest(
          type: type,
          level: level,
          taskTitle: task.title,
          minutes: session.plannedMinutes,
          minutesLate: offset,
          moves: session.rescheduleCount,
        ),
      );

      await _notifications.schedule(
        PendingNudge(
          id: notificationId(session.id, i),
          sessionId: session.id,
          at: at,
          title: 'Van',
          body: copy.text,
          level: level,
          urgent: (task.hoursUntilDeadline(at) ?? 999) < 6,
        ),
      );

      await _events.append(EventType.nudgeScheduled, {
        'sessionId': session.id,
        'level': level.name,
        'at': at.toIso8601String(),
        'templateId': copy.templateId,
      });
    }
  }

  /// A stable notification id for rung [rung] of [sessionId].
  static int notificationId(String sessionId, int rung) =>
      (sessionId.hashCode & 0x3FFFFF) * 8 + rung;

  /// Records an explicit START and stands the remaining nudges down.
  Future<WorkSession?> startSession(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null) return null;

    final started = session.start(_clock.now());
    await _sessions.save(started);
    await _notifications.cancelForSession(sessionId);
    await _events.append(EventType.sessionStarted, {
      'sessionId': sessionId,
      'minutesLate': session.minutesLate(_clock.now()),
    });
    return started;
  }

  /// Records a completed session.
  Future<void> completeSession(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null) return;
    await _sessions.save(session.complete(_clock.now()));
    await _events.append(EventType.sessionCompleted, {
      'sessionId': sessionId,
    });
    await _maybeFinishTask(session.taskId);
  }

  /// Records a session that started but stopped early.
  Future<void> stopEarly(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null) return;
    await _sessions.save(session.stopEarly(_clock.now()));
    await _events.append(EventType.sessionPartial, {'sessionId': sessionId});
  }

  /// Pushes a session back by [minutes], re-arming the ladder.
  Future<WorkSession?> snooze(String sessionId, {int minutes = 10}) async {
    final session = await _sessions.byId(sessionId);
    if (session == null) return null;
    final task = await _tasks.byId(session.taskId);
    if (task == null) return null;

    await _notifications.cancelForSession(sessionId);
    await _sessions.save(session.markRescheduled());

    final next = session.replacement(
      newId: _ids.next(),
      newStart: _clock.now().add(Duration(minutes: minutes)),
    );
    await _sessions.save(next);
    await _events.append(EventType.rescheduleApplied, {
      'from': sessionId,
      'to': next.id,
      'moves': next.rescheduleCount,
      'reason': 'snooze',
    });
    await _armLadder(next, task);
    return next;
  }

  /// Gives up on a session for today.
  Future<void> notToday(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null) return;
    await _notifications.cancelForSession(sessionId);
    await _sessions.save(session.skip());
    await _events.append(EventType.sessionMissed, {
      'sessionId': sessionId,
      'reason': 'not_today',
    });
  }

  /// Marks the task done once no unresolved sessions remain.
  Future<void> _maybeFinishTask(String taskId) async {
    final remaining = (await _sessions.forTask(
      taskId,
    )).where((s) => !s.isResolved).toList();
    if (remaining.isNotEmpty) return;

    final task = await _tasks.byId(taskId);
    if (task == null) return;
    await _tasks.save(task.copyWith(status: TaskStatus.done));
    await _events.append(EventType.taskUpdated, {
      'taskId': taskId,
      'status': TaskStatus.done.name,
    });
  }

  /// The next thing to do, or null when there is nothing scheduled.
  ///
  /// A session already running wins over anything merely planned, because the
  /// Now screen should show what you are doing before what you might do.
  Future<({WorkSession session, Task task})?> next() async {
    final running = await _sessions.inProgress();
    final candidate =
        running ??
        await _sessions.next(
          _clock.now().subtract(const Duration(hours: 1)),
        );
    if (candidate == null) return null;

    final task = await _tasks.byId(candidate.taskId);
    if (task == null) return null;
    return (session: candidate, task: task);
  }

  /// Everything still open, deadline first.
  Future<List<Task>> openTasks() => _tasks.open();

  /// Sessions awaiting an outcome.
  Future<List<WorkSession>> upcoming() => _sessions.unresolved();

  /// Records that the app came to the foreground.
  Future<void> noteAppOpened() =>
      _events.append(EventType.appOpened).then((_) {});
}
