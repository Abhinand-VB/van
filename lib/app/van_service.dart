import 'dart:async';

import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/capabilities/negotiate.dart';
import 'package:van/inference/prompts.dart';
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

/// What one pass of the stale-session sweep did.
class SweepReport {
  /// Creates a report.
  const SweepReport({this.moved = const [], this.dropped = const []});

  /// The replacement sessions that were placed and armed.
  final List<WorkSession> moved;

  /// Abandoned blocks that had nowhere left to go, with the reason.
  final List<({WorkSession session, SweepSkipReason reason})> dropped;

  /// How many abandoned blocks the sweep dealt with.
  int get total => moved.length + dropped.length;

  /// Whether the sweep found nothing to do.
  bool get isEmpty => total == 0;

  @override
  String toString() =>
      'SweepReport(moved=${moved.length}, dropped=${dropped.length})';
}

/// What Van proposes doing about a block that has stalled.
///
/// Carries the proposal *and* whether the domain would let Van act on it, so
/// the UI can offer the button or explain the refusal rather than silently
/// swallowing a model that overreached.
class NegotiationOutcome {
  /// Creates an outcome.
  const NegotiationOutcome({
    required this.session,
    required this.task,
    required this.proposal,
    required this.level,
    this.modelWasRefused,
  });

  /// The block being renegotiated.
  final WorkSession session;

  /// The work it belongs to.
  final Task task;

  /// What Van proposes. Always something the rules accept: a model proposal
  /// that fails validation is replaced by the deterministic fallback.
  final NegotiationProposal proposal;

  /// How hard Van is pushing. Chosen by the ladder, never by a model.
  final InterventionLevel level;

  /// Why a model proposal was thrown away, or null when none was.
  final NegotiationRejection? modelWasRefused;

  /// Whether the words came from a model rather than a template.
  bool get fromModel => proposal.fromModel;

  /// Whether this changes anything if applied.
  bool get changesThePlan => proposal.action != NegotiationAction.hold;
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
    required NudgeRepo nudges,
    required InferenceRouter router,
    required Notifications notifications,
    required NudgeTemplates templates,
    required Prompts prompts,
    required Clock clock,
    required IdGenerator ids,
    WakingHours waking = const WakingHours(),
    InterventionPolicy policy = const InterventionPolicy(),
    NegotiationRules rules = const NegotiationRules(),
    ImportanceScorer scorer = const ImportanceScorer(),
    SuppressionPolicy? suppression,
    int giveUpAfterMinutes = 60,
  }) : _tasks = tasks,
       _sessions = sessions,
       _events = events,
       _nudges = nudges,
       _router = router,
       _scorer = scorer,
       _suppression = suppression ?? SuppressionPolicy(waking: waking),
       _notifications = notifications,
       _templates = templates,
       _prompts = prompts,
       _negotiate = Negotiate(
         prompt: prompts.negotiate,
         templates: templates,
         policy: policy,
       ),
       _clock = clock,
       _ids = ids,
       _waking = waking,
       _policy = policy,
       _rules = rules,
       _sweep = StaleSessionSweep(
         rescheduler: Rescheduler(ids: ids),
         giveUpAfterMinutes: giveUpAfterMinutes,
       );

  final TaskRepo _tasks;
  final SessionRepo _sessions;
  final EventRepo _events;
  final NudgeRepo _nudges;
  final InferenceRouter _router;
  final ImportanceScorer _scorer;
  final SuppressionPolicy _suppression;
  final Notifications _notifications;
  final NudgeTemplates _templates;
  final Prompts _prompts;
  final Negotiate _negotiate;
  final Clock _clock;
  final IdGenerator _ids;
  final WakingHours _waking;
  final InterventionPolicy _policy;
  final StaleSessionSweep _sweep;
  final NegotiationRules _rules;

  /// A renegotiated block never lands closer than this to now, so accepting
  /// a proposal does not fire a nudge in the same breath.
  static const _negotiatedLeadMinutes = 5;

  /// Captures [text], plans it, stores it and arms the notifications.
  Future<CaptureResult> capture(String text) async {
    final now = _clock.now();

    final draft = await _router.run(
      ExtractTask(prompt: _prompts.extractTask),
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
    final slots = _freeSlots(around: existing, from: now);

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

  /// The week ahead, minus the time [around] already claims.
  ///
  /// A week is the planning horizon everywhere in Van: far enough that a
  /// missed morning has somewhere to land, near enough that the plan is still
  /// about this week rather than a fantasy of next month.
  List<FreeSlot> _freeSlots({
    required Iterable<WorkSession> around,
    required DateTime from,
  }) => FreeSlotFinder(waking: _waking).find(
    commitments: [
      for (final s in around)
        Commitment(start: s.plannedStart, end: s.plannedEnd, label: s.taskId),
    ],
    from: from,
    to: from.add(const Duration(days: 7)),
  );

  /// Pre-schedules the escalation ladder for [session].
  ///
  /// The prompt at the start, the check ten minutes later, the diagnose at
  /// twenty-five. All three are cancelled the moment the user responds, so an
  /// answered nudge never escalates behind their back.
  ///
  /// Because the ladder is armed up front rather than decided live (see the
  /// WP-4 deviation in STATUS), the suppression gate has to be run *here*,
  /// against the instant each rung will fire at rather than the instant it is
  /// being scheduled. Quiet hours and the spacing between rungs are exactly
  /// knowable in advance; the dismissal streak is the freshest estimate Van
  /// has. Whether a focus session will be running, and whether the phone will
  /// be in do-not-disturb, are not knowable at all - the OS enforces the
  /// latter itself, and an answered session cancels its own remaining rungs.
  Future<void> _armLadder(WorkSession session, Task task) async {
    final rungs = <(InterventionLevel, int)>[
      (InterventionLevel.l0Gentle, 0),
      (InterventionLevel.l1Check, _policy.checkAfterMinutes),
      (InterventionLevel.l2Diagnose, _policy.diagnoseAfterMinutes),
    ];

    // Fatigue is a *today* measure, and "today" is the day the rung fires -
    // not the day it is armed. Arming a ladder for tomorrow morning right
    // after being nudged must not silence tomorrow morning, which is the same
    // reasoning as the spacing rule below and was applied there but not here.
    //
    // All three rungs share a day: the planner keeps blocks inside waking
    // hours, so a start plus twenty-five minutes cannot cross midnight.
    //
    // One read for the whole ladder: the streak cannot change while it is
    // being armed, and re-querying per rung would only cost three scans.
    final fatigueSince = _startOfDayContaining(session.plannedStart);
    final fatigue = <NudgeType, int>{
      for (final type in const [
        NudgeType.sessionStart,
        NudgeType.sessionMissed,
      ])
        type: await _nudges.consecutiveDismissals(type, fatigueSince),
    };

    // Spacing is measured to the instant a rung will *fire*, not the instant
    // it is being armed. Those are the same thing for a live engine and wildly
    // different for a pre-scheduled one: arming a ladder for tomorrow morning
    // seconds after being nudged must not silence tomorrow morning.
    final lastNudge = await _nudges.lastDelivered();
    final lastDeliveredAt = lastNudge?.deliveredAt;

    // A replacement block continues the conversation its parent started. Van
    // said "not started?", the user said "in ten minutes" - the reminder they
    // just asked for is not an unrelated second interruption, and the general
    // spacing rule must not swallow it.
    final continuesFromParent =
        lastNudge?.sessionId != null &&
        lastNudge!.sessionId == session.parentSessionId;

    // The offset of the last rung actually armed in *this* ladder. Null until
    // one is, which is what separates "continuing a conversation" from
    // starting one - a rung whose predecessor was suppressed is not a
    // continuation, and must be spaced against the last real nudge instead.
    int? lastArmedOffset;

    for (var i = 0; i < rungs.length; i++) {
      final (level, offset) = rungs[i];
      final at = session.plannedStart.add(Duration(minutes: offset));
      if (at.isBefore(_clock.now())) continue;

      final type = offset == 0
          ? NudgeType.sessionStart
          : NudgeType.sessionMissed;
      final dismissals = fatigue[type] ?? 0;
      final continuesSameSession =
          lastArmedOffset != null || continuesFromParent;
      final gapMinutes = lastArmedOffset != null
          ? offset - lastArmedOffset
          : lastDeliveredAt == null
          ? null
          : at.difference(lastDeliveredAt).inMinutes;

      final gate = _suppression.evaluate(
        SuppressionContext(
          type: type,
          now: at,
          minutesSinceLastNudge: gapMinutes,
          consecutiveDismissals: dismissals,
          continuesSameSession: continuesSameSession,
        ),
      );

      final copy = await _router.run(
        ComposeNudge(_templates, prompt: _prompts.composeNudge),
        NudgeCopyRequest(
          type: type,
          level: level,
          taskTitle: task.title,
          minutes: session.plannedMinutes,
          minutesLate: offset,
          moves: session.rescheduleCount,
        ),
      );

      // Recorded whether or not it goes out. What Van decided not to say is
      // as informative as what it said, and it is the only way to tell a
      // quiet day from a broken scheduler.
      await _nudges.save(
        Nudge(
          id: _ids.next(),
          sessionId: session.id,
          type: type,
          importance: _scorer.score(
            ScoringContext(
              type: type,
              hoursToDeadline: task.hoursUntilDeadline(at),
              rescheduleCount: session.rescheduleCount,
              minutesSinceLastNudge: gapMinutes,
              consecutiveDismissals: dismissals,
              continuesSameSession: continuesSameSession,
            ),
          ),
          level: level,
          scheduledAt: at,
          copy: copy.text,
          templateId: copy.templateId,
          wasSuppressed: gate.suppressed,
          suppressionReason: gate.reason?.name,
        ),
      );

      if (gate.suppressed) {
        await _events.append(EventType.nudgeSuppressed, {
          'sessionId': session.id,
          'level': level.name,
          'at': at.toIso8601String(),
          'reason': gate.reason!.name,
        });
        continue;
      }

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
      lastArmedOffset = offset;

      await _events.append(EventType.nudgeScheduled, {
        'sessionId': session.id,
        'level': level.name,
        'at': at.toIso8601String(),
        'templateId': copy.templateId,
      });
    }
  }

  /// Midnight local on the day [instant] falls in, as UTC.
  ///
  /// Fatigue is a *today* measure: yesterday's swipes must not silence Van
  /// this morning, and today's must not silence it tomorrow.
  DateTime _startOfDayContaining(DateTime instant) {
    final wall = _waking.toLocalWall(instant);
    return _waking.toUtcInstant(DateTime.utc(wall.year, wall.month, wall.day));
  }

  /// Records what the user said about the rung that most recently fired.
  ///
  /// The half of settling that does not stand anything down. A `hold` means
  /// the conversation continues and the remaining rungs must still fire, so it
  /// needs this without the rest.
  ///
  /// Marks fired rungs delivered on the way past, since delivery is inferred
  /// rather than observed - see [_settleLadder].
  Future<Nudge?> _recordAnswer(
    String sessionId,
    ResponseType response, {
    String? reasonText,
  }) async {
    final now = _clock.now();
    Nudge? answered;

    for (final nudge in await _nudges.forSession(sessionId)) {
      if (nudge.wasSuppressed || nudge.deliveredAt != null) continue;
      if (nudge.scheduledAt.isAfter(now)) continue;

      final delivered = nudge.deliver(nudge.scheduledAt);
      await _nudges.save(delivered);
      await _events.append(EventType.nudgeDelivered, {
        'sessionId': sessionId,
        'nudgeId': nudge.id,
        'level': nudge.level.name,
        'at': nudge.scheduledAt.toIso8601String(),
      });
      answered = delivered;
    }

    // Nothing fired, so there is nothing to have responded to. An event would
    // be a lie and a fatigue tick would be unearned.
    if (answered == null) return null;

    await _nudges.saveResponse(
      NudgeResponse(
        id: _ids.next(),
        nudgeId: answered.id,
        response: response,
        respondedAt: now,
        latencySeconds: now.difference(answered.deliveredAt!).inSeconds,
        reasonText: reasonText,
      ),
    );
    await _events.append(EventType.nudgeResponded, {
      'sessionId': sessionId,
      'nudgeId': answered.id,
      'response': response.name,
      'level': answered.level.name,
    });
    return answered;
  }

  /// Closes the books on [sessionId]'s ladder and records [response].
  ///
  /// Two steps, and only the first belongs to this method. Rungs still in the
  /// future are stood down: the user answered before Van got to them, which is
  /// the ladder working. They are marked suppressed rather than deleted,
  /// because the record of what was *not* said is what tells a quiet day from
  /// a broken scheduler.
  ///
  /// Recording the answer is then delegated to [_recordAnswer], which owns the
  /// inference that a rung whose instant has passed did reach the user. That
  /// inference underpins the entire fatigue count, so it lives in one place -
  /// which it briefly did not, when this method grew its own copy.
  Future<void> _settleLadder(
    String sessionId,
    ResponseType response, {
    String? reasonText,
  }) async {
    final now = _clock.now();

    for (final nudge in await _nudges.forSession(sessionId)) {
      if (nudge.wasSuppressed || nudge.deliveredAt != null) continue;
      if (!nudge.scheduledAt.isAfter(now)) continue;
      await _nudges.save(nudge.suppress('answeredBeforeItFired'));
    }

    await _recordAnswer(sessionId, response, reasonText: reasonText);
  }

  /// A stable notification id for rung [rung] of [sessionId].
  ///
  /// Delegates so there is exactly one formula: `cancelForSession` derives the
  /// same ids without being told them, which is what lets a ladder armed
  /// yesterday be stood down today.
  static int notificationId(String sessionId, int rung) =>
      LadderIds.forRung(sessionId, rung);

  /// Records an explicit START and stands the remaining nudges down.
  ///
  /// Idempotent, and it has to be. The Now card shows RESUME on a running
  /// block and wires it to this same call, so backing out of the focus screen
  /// and tapping again is one gesture away. Restarting would overwrite
  /// `actualStart` - the field `WorkSession` calls ground truth for whether
  /// they began, and the one number the whole product exists to measure - with
  /// whatever time they happened to come back.
  ///
  /// Closed work cannot be reopened either. A stale notification action can
  /// arrive for a block the sweep has already moved, and START on it must not
  /// resurrect a skipped session as a running one.
  Future<WorkSession?> startSession(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null || session.isResolved) return null;
    if (session.hasStarted) return session;

    final started = session.start(_clock.now());
    await _sessions.save(started);
    await _settleLadder(sessionId, ResponseType.started);
    await _notifications.cancelForSession(sessionId);
    await _events.append(EventType.sessionStarted, {
      'sessionId': sessionId,
      'minutesLate': session.minutesLate(_clock.now()),
    });
    return started;
  }

  /// Records a completed session.
  ///
  /// Refuses work that is already closed. The focus screen's three buttons
  /// stay live during the write, so tapping Done and then Need more time is
  /// one fumbled thumb away - and without this the second call would rewrite
  /// a completion as a partial. Every other mutating method on this class
  /// guards the same way; these two were the last without it.
  Future<void> completeSession(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null || session.isResolved) return;
    await _sessions.save(session.complete(_clock.now()));
    await _events.append(EventType.sessionCompleted, {
      'sessionId': sessionId,
    });
    await _maybeFinishTask(session.taskId);
  }

  /// Records a session that started but stopped early.
  ///
  /// Refuses work that is already closed - see [completeSession]. Stopping a
  /// finished block early is not a thing that can happen, and letting it
  /// would erase the completion.
  Future<void> stopEarly(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null || session.isResolved) return;
    await _sessions.save(session.stopEarly(_clock.now()));
    await _events.append(EventType.sessionPartial, {'sessionId': sessionId});
  }

  /// Pushes a session back by [minutes], re-arming the ladder.
  ///
  /// Refuses work that is already closed, and that guard is reachable rather
  /// than theoretical: with Van killed nothing cancels a notification until
  /// an action is actually processed, so the 09:00 and 09:10 rungs of one
  /// ladder can both be sitting in the shade. Pressing Snooze on each would
  /// otherwise move the same piece of work twice and leave two replacement
  /// blocks for it.
  Future<WorkSession?> snooze(String sessionId, {int minutes = 10}) async {
    final session = await _sessions.byId(sessionId);
    if (session == null || session.isResolved) return null;
    final task = await _tasks.byId(session.taskId);
    if (task == null) return null;

    await _settleLadder(sessionId, ResponseType.snoozed);
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

  /// Records that a running block was abandoned part-way, and offers another
  /// go in [minutes].
  ///
  /// Its own method rather than `stopEarly` followed by `snooze`, which is
  /// what the focus screen used to do. That pairing had two problems. The
  /// second call overwrote the first's status, so a block that was genuinely
  /// worked on ended up recorded only as moved. And it depended on `snooze`
  /// accepting a resolved session, which is exactly the guard `snooze` needed
  /// for its own sake.
  ///
  /// The original keeps `partial`: it was worked on, and the replacement
  /// records the link through `parentSessionId`. Nothing reads the status to
  /// decide behaviour - `hasStarted` and `isResolved` do that - so this is a
  /// choice about which fact the row tells, and "they got started" is the one
  /// worth keeping.
  Future<WorkSession?> stuck(String sessionId, {int minutes = 20}) async {
    final session = await _sessions.byId(sessionId);
    if (session == null || session.isResolved) return null;
    final task = await _tasks.byId(session.taskId);
    if (task == null) return null;

    final now = _clock.now();
    // The ladder was already settled when they pressed START; this only
    // clears anything the OS is still holding.
    await _notifications.cancelForSession(sessionId);
    await _sessions.save(session.stopEarly(now));
    await _events.append(EventType.sessionPartial, {
      'sessionId': sessionId,
      'reason': 'stuck',
    });

    final next = session.replacement(
      newId: _ids.next(),
      newStart: now.add(Duration(minutes: minutes)),
    );
    await _sessions.save(next);
    await _events.append(EventType.rescheduleApplied, {
      'from': sessionId,
      'to': next.id,
      'moves': next.rescheduleCount,
      'reason': 'stuck',
    });
    await _armLadder(next, task);
    return next;
  }

  /// Gives up on a session for today.
  ///
  /// Ignores work that is already closed - see the note on [snooze]; two
  /// notifications for one ladder can outlive the block they are about.
  Future<void> notToday(String sessionId) async {
    final session = await _sessions.byId(sessionId);
    if (session == null || session.isResolved) return;
    await _settleLadder(sessionId, ResponseType.dismissed);
    await _notifications.cancelForSession(sessionId);
    await _sessions.save(session.skip());
    await _events.append(EventType.sessionMissed, {
      'sessionId': sessionId,
      'reason': 'not_today',
    });
  }

  /// Moves work that was quietly abandoned, and closes what cannot move.
  ///
  /// `NudgeEngine` stops nudging about a block an hour past its start. That
  /// keeps Van from nagging, but on its own it leaves the block sitting in
  /// `planned` forever: never due again, never nudged again, silently gone
  /// from the plan without anyone deciding it should be. This is the other
  /// half of that behaviour, and it is the only thing that turns "you didn't
  /// start" into "here is when you will".
  ///
  /// Safe to call often. It is a no-op when nothing is stale, which is why
  /// app open is a good enough trigger and no background isolate is needed.
  Future<SweepReport> sweepStaleSessions() async {
    final now = _clock.now();
    final unresolved = await _sessions.unresolved();
    final stale = unresolved.where((s) => _sweep.isStale(s, now)).toList();
    if (stale.isEmpty) return const SweepReport();

    // The stale blocks are the ones being vacated, so their time is free
    // again and they must not be passed in as commitments against themselves.
    final staleIds = stale.map((s) => s.id).toSet();
    final slots = _freeSlots(
      around: unresolved.where((s) => !staleIds.contains(s.id)),
      from: now,
    );

    final tasks = <String, Task>{};
    final candidates = <SweepCandidate>[];
    for (final session in stale) {
      final task = tasks[session.taskId] ?? await _tasks.byId(session.taskId);
      if (task == null) continue;
      tasks[task.id] = task;
      candidates.add(
        SweepCandidate(session: session, deadline: task.deadline),
      );
    }

    final moved = <WorkSession>[];
    final dropped = <({WorkSession session, SweepSkipReason reason})>[];

    for (final outcome in _sweep.run(
      candidates: candidates,
      slots: slots,
      clock: _clock,
    )) {
      final original = outcome.stale;
      // The defining fatigue signal: Van asked, escalated, and was never
      // answered. Nothing else in the app can record an ignore, because an
      // ignore is the absence of an action.
      await _settleLadder(original.id, ResponseType.ignored);
      await _notifications.cancelForSession(original.id);
      await _sessions.save(original);
      await _events.append(EventType.sessionMissed, {
        'sessionId': original.id,
        'taskId': original.taskId,
        'reason': 'stale',
        'minutesLate': original.minutesLate(now),
        'outcome': outcome.wasMoved ? 'rescheduled' : 'dropped',
        'skipReason': ?outcome.skipReason?.name,
      });

      final replacement = outcome.replacement;
      if (replacement == null) {
        dropped.add((session: original, reason: outcome.skipReason!));
        continue;
      }

      await _sessions.save(replacement);
      await _events.append(EventType.rescheduleApplied, {
        'from': original.id,
        'to': replacement.id,
        'moves': replacement.rescheduleCount,
        'start': replacement.plannedStart.toIso8601String(),
        'reason': 'sweep',
      });
      await _armLadder(replacement, tasks[replacement.taskId]!);
      moved.add(replacement);
    }

    return SweepReport(moved: moved, dropped: dropped);
  }

  /// Marks [taskId] done from the task list, standing its blocks down.
  ///
  /// The list is flat and the gesture is a swipe, so this has to be safe to
  /// invoke on a task with blocks still planned - which is the common case,
  /// because work usually finishes somewhere other than where it was
  /// scheduled. Those blocks are marked skipped rather than completed: they
  /// genuinely never ran, and pretending otherwise would corrupt the record of
  /// what this person actually does.
  ///
  /// Any nudge that had already fired is settled as engagement. Finishing the
  /// work is the opposite of ignoring the ask, and letting those rungs rot
  /// unanswered would build fatigue against someone who did exactly what Van
  /// wanted.
  Future<Task?> completeTask(String taskId) async {
    final task = await _tasks.byId(taskId);
    if (task == null) return null;

    final open = (await _sessions.forTask(
      taskId,
    )).where((s) => !s.isResolved).toList();

    for (final session in open) {
      await _settleLadder(session.id, ResponseType.started);
      await _notifications.cancelForSession(session.id);
      await _sessions.save(session.skip());
    }

    final done = task.copyWith(status: TaskStatus.done);
    await _tasks.save(done);
    await _events.append(EventType.taskUpdated, {
      'taskId': taskId,
      'status': TaskStatus.done.name,
      'source': 'task_list',
      'blocksStoodDown': open.length,
    });
    return done;
  }

  /// Undoes a capture: removes the task, its blocks and its armed nudges.
  ///
  /// Deliberately a delete rather than `TaskStatus.abandoned`. Abandoned means
  /// *the user gave up on this work*, and that distinction is there to learn
  /// what they follow through on. A capture the user rejects seconds after
  /// making it is Van having misread a sentence, not a person quitting, and
  /// recording it as the latter would poison the only signal that status
  /// exists to carry.
  ///
  /// Nothing is truly lost: the `taskCreated` and `sessionPlanned` events stay
  /// in the append-only log, joined now by the undo itself.
  Future<bool> undoCapture(String taskId) async {
    final task = await _tasks.byId(taskId);
    if (task == null) return false;

    final sessions = await _sessions.forTask(taskId);
    for (final session in sessions) {
      await _notifications.cancelForSession(session.id);
      await _nudges.deleteForSession(session.id);
      await _sessions.delete(session.id);
    }
    await _tasks.delete(taskId);

    await _events.append(EventType.taskUpdated, {
      'taskId': taskId,
      'title': task.title,
      'status': 'undone',
      'blocksRemoved': sessions.length,
    });
    return true;
  }

  /// Asks what to do about a stalled block, optionally given [reason].
  ///
  /// This is the conversation Van was designed around: not "you did not
  /// start", but "you did not start - what would work instead". The reply is
  /// a *proposal*. Nothing changes until [applyNegotiation] is called, which
  /// is what keeps a language model on the right side of AGENTS.md rule 3.
  ///
  /// The returned proposal is always one the domain accepts. If a model
  /// proposes something the ladder does not permit at this level, it is
  /// discarded and the deterministic fallback answers instead - so a bad model
  /// degrades the wording, never the behaviour.
  Future<NegotiationOutcome?> negotiate(
    String sessionId, {
    String? reason,
  }) async {
    final session = await _sessions.byId(sessionId);
    // Nothing to negotiate about work that is finished or already underway.
    // Proposing a smaller block to someone mid-session is not help.
    if (session == null || session.isResolved || session.hasStarted) {
      return null;
    }
    final task = await _tasks.byId(session.taskId);
    if (task == null) return null;

    final now = _clock.now();
    final priors = await _priorResponses(sessionId);
    final explained = reason != null && reason.trim().isNotEmpty;

    final input = NegotiationRequest(
      taskTitle: task.title,
      minutes: session.plannedMinutes,
      minutesLate: session.minutesLate(now),
      moves: session.rescheduleCount,
      hoursToDeadline: task.hoursUntilDeadline(now),
      priorResponses: priors,
      userGaveReason: explained,
      reasonText: explained ? reason.trim() : null,
      userRefused: priors.contains(ResponseType.dismissed),
    );

    final level = _negotiate.levelFor(input);
    var proposal = await _router.run(_negotiate, input);

    // The gate. A model may propose; only the domain decides.
    final refused = _rules.reject(proposal, _negotiate.contextFor(input));
    if (refused != null) proposal = _negotiate.fallback(input);

    await _events.append(EventType.interventionSelected, {
      'sessionId': sessionId,
      'level': level.name,
      'action': proposal.action.name,
      'source': proposal.fromModel ? 'model' : 'fallback',
      'refused': ?refused?.name,
      'gaveReason': explained,
    });

    return NegotiationOutcome(
      session: session,
      task: task,
      proposal: proposal,
      level: level,
      modelWasRefused: refused,
    );
  }

  /// Carries out a proposal the user accepted.
  ///
  /// Returns the block as it now stands, or null when the proposal was
  /// refused - which is the only thing null means.
  ///
  /// Re-validates rather than trusting the caller. The proposal may have been
  /// sitting on screen for a while, and a block that has since been started or
  /// moved must not be renegotiated out from under itself.
  ///
  /// [reason] must be whatever was passed to [negotiate], because the level -
  /// and therefore what is permitted - depends on it. Someone who explained
  /// themselves has earned a smaller ask; the same proposal without that
  /// context is above what the ladder allows. Forgetting it here made Van
  /// refuse its own proposal.
  ///
  /// That is not a hole in the gate: the reason is the *user's* own words, and
  /// the thing being guarded against is a model proposing something drastic,
  /// which is still checked against the level either way.
  Future<WorkSession?> applyNegotiation(
    String sessionId,
    NegotiationProposal proposal, {
    String? reason,
  }) async {
    final session = await _sessions.byId(sessionId);
    // `isResolved` is not enough: a *started* block is neither resolved nor
    // renegotiable. Without the second check, accepting a shrink on work
    // already in progress replaces it with a smaller block later on - which
    // cancels what the user is doing at that moment, which is the single
    // worst thing Van could do to someone who did exactly what it asked.
    if (session == null || session.isResolved || session.hasStarted) {
      return null;
    }
    final task = await _tasks.byId(session.taskId);
    if (task == null) return null;

    final now = _clock.now();
    final priors = await _priorResponses(sessionId);
    final explained = reason != null && reason.trim().isNotEmpty;
    final input = NegotiationRequest(
      taskTitle: task.title,
      minutes: session.plannedMinutes,
      minutesLate: session.minutesLate(now),
      moves: session.rescheduleCount,
      hoursToDeadline: task.hoursUntilDeadline(now),
      priorResponses: priors,
      userGaveReason: explained,
      reasonText: explained ? reason.trim() : null,
      userRefused: priors.contains(ResponseType.dismissed),
    );
    if (_rules.reject(proposal, _negotiate.contextFor(input)) != null) {
      return null;
    }

    switch (proposal.action) {
      case NegotiationAction.hold:
        // The deal on the table is still the deal, so the remaining rungs must
        // still fire - _settleLadder would stand them down, which is the
        // opposite of holding. Only the answer is recorded, and only when the
        // user actually said something: a bare acknowledgement with no words
        // has no honest ResponseType, and inventing one would put Van's own
        // sentence in the log as if the user had written it.
        if (explained) {
          await _recordAnswer(
            sessionId,
            ResponseType.reason,
            reasonText: reason.trim(),
          );
        }
        return session;

      case NegotiationAction.release:
        await _settleLadder(sessionId, ResponseType.dismissed);
        await _notifications.cancelForSession(sessionId);
        final released = session.skip();
        await _sessions.save(released);
        await _events.append(EventType.sessionMissed, {
          'sessionId': sessionId,
          'reason': 'negotiated_release',
        });
        // Returns the closed block rather than null, so that null means one
        // thing only: the proposal was refused. It meant both, and the chat
        // card cheerfully reported "Let go for today" over a block that had
        // been started in the meantime and was still running.
        return released;

      case NegotiationAction.shrink:
      case NegotiationAction.defer:
        final start = proposal.action == NegotiationAction.defer
            ? now.add(Duration(minutes: proposal.deferByMinutes!))
            : _noEarlierThanNow(session.plannedStart, now);
        return _replaceWith(
          session: session,
          task: task,
          newStart: start,
          newMinutes: proposal.shrinkToMinutes,
          reason: proposal.action.name,
          // Renegotiating time without explaining is materially a snooze.
          answer: explained ? ResponseType.reason : ResponseType.snoozed,
          answerText: explained ? reason.trim() : null,
        );
    }
  }

  /// A shrunken block keeps its slot unless that slot has already gone.
  DateTime _noEarlierThanNow(DateTime plannedStart, DateTime now) {
    final earliest = now.add(const Duration(minutes: _negotiatedLeadMinutes));
    return plannedStart.isAfter(earliest) ? plannedStart : earliest;
  }

  /// Retires [session] and arms a replacement. The shape snooze, the sweep and
  /// negotiation all share.
  Future<WorkSession> _replaceWith({
    required WorkSession session,
    required Task task,
    required DateTime newStart,
    required String reason,
    required ResponseType answer,
    String? answerText,
    int? newMinutes,
  }) async {
    await _settleLadder(session.id, answer, reasonText: answerText);
    await _notifications.cancelForSession(session.id);
    await _sessions.save(session.markRescheduled());

    final next = session.replacement(
      newId: _ids.next(),
      newStart: newStart,
      newMinutes: newMinutes,
    );
    await _sessions.save(next);
    await _events.append(EventType.rescheduleApplied, {
      'from': session.id,
      'to': next.id,
      'moves': next.rescheduleCount,
      'minutes': next.plannedMinutes,
      'start': next.plannedStart.toIso8601String(),
      'reason': reason,
    });
    await _armLadder(next, task);
    return next;
  }

  /// How the user has answered nudges about [sessionId], oldest first.
  Future<List<ResponseType>> _priorResponses(String sessionId) async {
    final answers = <NudgeResponse>[];
    for (final nudge in await _nudges.forSession(sessionId)) {
      answers.addAll(await _nudges.responsesFor(nudge.id));
    }
    answers.sort((a, b) => a.respondedAt.compareTo(b.respondedAt));
    return [for (final a in answers) a.response];
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

  /// The block that is due and has not been started, if there is one.
  ///
  /// Earliest first, because the one that has been waiting longest is the one
  /// worth asking about. Deliberately not [next]: that answers "what should I
  /// do", and this answers "what did I say I would do and then not".
  Future<({WorkSession session, Task task})?> stalled() async {
    final now = _clock.now();
    final candidates =
        (await _sessions.unresolved())
            .where((s) => !s.hasStarted && s.plannedStart.isBefore(now))
            .toList()
          ..sort((a, b) => a.plannedStart.compareTo(b.plannedStart));
    if (candidates.isEmpty) return null;

    final session = candidates.first;
    final task = await _tasks.byId(session.taskId);
    if (task == null) return null;
    return (session: session, task: task);
  }

  /// Everything still open, deadline first.
  Future<List<Task>> openTasks() => _tasks.open();

  /// Sessions awaiting an outcome.
  Future<List<WorkSession>> upcoming() => _sessions.unresolved();

  /// Records that the app came to the foreground.
  Future<void> noteAppOpened() =>
      _events.append(EventType.appOpened).then((_) {});
}
