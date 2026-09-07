import 'dart:async';

import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/capabilities/negotiate.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/inference/router.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/platform/notifications.dart';
import 'package:van_core/van_core.dart';

/// What happened when a sentence was captured.
/// One task that came out of a capture, and the blocks planned for it.
class CapturedTask {
  /// Creates a captured task.
  const CapturedTask({
    required this.task,
    required this.sessions,
    this.shortfallMinutes = 0,
  });

  /// The task that was stored.
  final Task task;

  /// The blocks that were scheduled for it.
  final List<WorkSession> sessions;

  /// Minutes of this task that would not fit before its deadline.
  final int shortfallMinutes;
}

/// What happened when a sentence was captured.
///
/// **Plural, because a sentence is.** The owner typed "go to the shop take a
/// stroll cook lunch and do my remaining works also I need to do taxes" and
/// got one task with a 25-word title; the model, asked the same thing, kept
/// four words and threw the rest away. Neither could do better while this
/// type held one task. See `docs/WP_CAPTURE.md`.
class CaptureResult {
  /// Creates a result.
  const CaptureResult({
    required this.captured,
    this.clarification,
    this.clarificationTaskId,
    this.assumedMinutes,
  });

  /// Every task the sentence produced, in the order it was written.
  final List<CapturedTask> captured;

  /// The one thing Van wants to be told about this, if anything.
  ///
  /// **One question for the whole capture, however many tasks it made.** Five
  /// tasks with no stated durations must not produce five questions; that is
  /// the form `CaptureQuestions` exists to avoid, arriving by a different
  /// route.
  final Clarification? clarification;

  /// Which task [clarification] is about. Null when there is no question.
  ///
  /// **Not necessarily the first one, which is why this has to be carried.**
  /// "email the landlord 15 minutes and pay the rent" states a duration for
  /// the first job and not the second, so the question belongs to the second.
  /// The event log recorded that correctly from the start; the result did
  /// not, so the screen had nothing to go on and used [task] - and answering
  /// would have replanned the landlord to the length meant for the rent,
  /// overwriting a duration the user had actually given. See
  /// `DECISIONS_PENDING.md` D89.
  final String? clarificationTaskId;

  /// The duration Van invented because nobody stated one, in minutes.
  ///
  /// Null when the user said how long. Set here rather than left implicit so
  /// the screen can *say* what was assumed: a plan built on a guess and a
  /// plan built on a statement look identical, and the difference is the
  /// whole reason to ask.
  final int? assumedMinutes;

  /// The first task, which is the only one when a sentence held one job.
  ///
  /// Kept so every caller that predates splitting still reads correctly: a
  /// screen that says "Captured X" wants the first thing typed, and the
  /// common case is still exactly one.
  Task get task => captured.first.task;

  /// Every block planned, across every task the sentence produced.
  List<WorkSession> get sessions => [
    for (final one in captured) ...one.sessions,
  ];

  /// Every task id, for an undo that takes back the whole sentence.
  List<String> get taskIds => [for (final one in captured) one.task.id];

  /// Minutes that would not fit, added up across the capture.
  int get shortfallMinutes =>
      captured.fold(0, (sum, one) => sum + one.shortfallMinutes);

  /// Whether the sentence produced more than one task.
  bool get isMany => captured.length > 1;

  /// Whether some of the work could not be placed.
  bool get isPartial => shortfallMinutes > 0;
}

/// What came of answering one of Van's questions.
///
/// Three outcomes rather than a bool, because "I did not understand that" and
/// "that work has already started" call for different things to be said and
/// the caller cannot tell them apart from a failure.
enum AnswerOutcome {
  /// The plan was rebuilt on what the user said.
  replanned,

  /// Nothing in the answer looked like a duration. The question still stands.
  notUnderstood,

  /// The task is gone, or a block of it is already under way, so there is
  /// nothing left to re-plan. Changing the estimate under work in progress
  /// would move a block the user is sitting in.
  tooLate,
}

/// The result of answering a question Van asked at capture time.
class AnswerResult {
  /// Creates a result.
  const AnswerResult(this.outcome, {this.task, this.sessions = const []});

  /// What happened.
  final AnswerOutcome outcome;

  /// The task as it now stands, when it was re-planned.
  final Task? task;

  /// The blocks that replaced the ones planned on the guess.
  final List<WorkSession> sessions;
}

/// One event from the device calendar, resolved to real instants and ready to
/// draw.
///
/// Exists so the UI never has to know that providers store all-day entries as
/// UTC midnights naming local dates. That arithmetic belongs to
/// [CalendarFilter], which is also what planning uses, and two copies of it
/// would eventually disagree by a timezone.
///
/// **[title] may be drawn and may not be recorded.** It never enters the
/// event log, a notification, or the week report - see `CalendarEntry`.
class CalendarOccurrence {
  /// Creates an occurrence.
  const CalendarOccurrence({
    required this.calendarId,
    required this.start,
    required this.end,
    required this.title,
    required this.isAllDay,
    required this.blocks,
    required this.attendance,
  });

  /// Which calendar it came from, so a view can colour it the way the phone
  /// does.
  ///
  /// **For drawing only, and it goes no further than [title] does.** Planning
  /// never sees this type: `CalendarFilter.commitments` yields nameless,
  /// sourceless commitments and that is what reaches the log. An id here is
  /// no more recorded than a meeting's name is.
  final String calendarId;

  /// When it begins. UTC, and real - an all-day entry is already resolved.
  final DateTime start;

  /// When it ends. UTC.
  final DateTime end;

  /// What it is called, or empty for an untitled event.
  final String title;

  /// Whether the provider marks it all-day.
  final bool isAllDay;

  /// Whether Van treats this as time it may not plan into.
  ///
  /// Carried rather than re-derived so the screen and the planner cannot
  /// disagree: a view that shaded a slot Van had scheduled into would be
  /// lying about one of the two.
  final bool blocks;

  /// The user's own answer, when there was something to answer.
  final Attendance attendance;
}

/// One stretch of the user's day, as the calendar screen draws it.
///
/// Two lists rather than one merged timeline, because they are not the same
/// kind of thing and must not be made to look like it: [blocks] is work Van
/// planned, chose the time for, and will nudge about; [events] is what the
/// device calendar says, which Van reads and never writes.
class DayPlan {
  /// Creates a day.
  const DayPlan({this.blocks = const [], this.events = const []});

  /// Van's own work sessions that start in the window, earliest first.
  final List<({WorkSession session, Task task})> blocks;

  /// Everything on the calendars the user has not excluded, including the
  /// entries that do not block.
  ///
  /// A view is not a planner: an entry marked free still belongs on screen,
  /// because the user put it there and expects to see it. Which of them Van
  /// refuses to plan into is carried per occurrence.
  final List<CalendarOccurrence> events;

  /// Whether there is nothing at all on this stretch of the day.
  bool get isEmpty => blocks.isEmpty && events.isEmpty;
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
    //
    // `unawaited` alone does not deliver that second half. It silences the
    // analyzer and catches nothing, so a failed append became an unhandled
    // asynchronous error in whichever zone the inference happened to run in -
    // reaching Flutter's error handler, or failing an unrelated test. The
    // promise above needs the catch to be true.
    unawaited(
      _events
          .append(
            outcome == InferenceOutcome.model
                ? EventType.inferenceOk
                : EventType.inferenceFallback,
            {
              'capability': capabilityId,
              'backend': backendId,
              'reason': ?failureReason,
              'latencyMs': ?latencyMs,
            },
          )
          .then<void>((_) {}, onError: _dropped),
    );
  }

  /// Swallows a failed log write, deliberately and with nowhere else to go.
  ///
  /// This is the logging path: a logging failure has no log to be reported to,
  /// and re-throwing it would take down the call it was only ever describing.
  /// Open issue 5 already accepts that a crash can lose the last few inference
  /// events; this makes losing them quiet rather than destructive.
  static void _dropped(Object error, StackTrace stack) {}
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
    Calendars calendars = const UnsupportedCalendars(),
    CalendarPreferences? calendarPreferences,
    WakingHours waking = const WakingHours(),
    InterventionPolicy policy = const InterventionPolicy(),
    NegotiationRules rules = const NegotiationRules(),
    ImportanceScorer scorer = const ImportanceScorer(),
    SuppressionPolicy? suppression,
    PlannerConstraints constraints = const PlannerConstraints(),
    int giveUpAfterMinutes = 60,
  }) : _tasks = tasks,
       _sessions = sessions,
       _events = events,
       _nudges = nudges,
       _router = router,
       _scorer = scorer,
       _suppression = suppression ?? SuppressionPolicy(waking: waking),
       _notifications = notifications,
       _calendars = calendars,
       _calendarPreferences = calendarPreferences,
       _calendarFilter = CalendarFilter(utcOffset: waking.utcOffset),
       _templates = templates,
       _prompts = prompts,
       // Both `policy` and `rules` have to reach Negotiate, not just policy.
       // Negotiate uses the rules twice - to tell the model which actions its
       // level permits, and as the floor its own deterministic fallback
       // shrinks to - while the gate below rejects against this class's copy.
       // Left unpassed they were two different rule sets that happened to be
       // equal, and any caller overriding `rules` would have got a fallback
       // Van then refused: the user accepts Van's own proposal and nothing
       // happens.
       _negotiate = Negotiate(
         prompt: prompts.negotiate,
         templates: templates,
         policy: policy,
         rules: rules,
       ),
       _clock = clock,
       _ids = ids,
       _waking = waking,
       // The parser reads wall-clock words - "friday", "tonight" - and must
       // read them in the same timezone the planner schedules in. Left at its
       // default it runs at UTC, which on a UTC-7 phone turned "by friday"
       // into Friday 16:59 local and made anything captured after five in the
       // afternoon "due today" and already overdue.
       _extractTask = ExtractTask(
         prompt: prompts.extractTask,
         parser: TemporalParser(utcOffset: waking.utcOffset),
       ),
       _policy = policy,
       _rules = rules,
       _constraints = constraints,
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
  SuppressionPolicy _suppression;
  final Notifications _notifications;
  final Calendars _calendars;
  final CalendarPreferences? _calendarPreferences;
  CalendarFilter _calendarFilter;
  final NudgeTemplates _templates;
  final Prompts _prompts;
  ExtractTask _extractTask;
  final Negotiate _negotiate;
  final Clock _clock;
  final IdGenerator _ids;
  WakingHours _waking;
  final InterventionPolicy _policy;
  final StaleSessionSweep _sweep;
  final NegotiationRules _rules;

  /// Held rather than defaulted at the call site, because the planner's
  /// assumed duration is now quoted back to the user. The number Van plans
  /// with and the number Van admits to have to be the same object or the
  /// admission is a second guess about the first one.
  final PlannerConstraints _constraints;

  /// Decides whether a captured sentence left Van guessing.
  static const _questions = CaptureQuestions();

  /// The duration Van uses when nobody has said how long.
  ///
  /// Exposed so a screen offering to *edit* an estimate can pre-fill the same
  /// number the planner already used, rather than showing an empty box. An
  /// empty box asks the user to invent a figure; a filled one asks them to
  /// correct Van's, which is a far easier question and the reason this is on
  /// the card at all.
  int get defaultEstimateMinutes => _constraints.defaultEstimateMinutes;

  /// Operations that pick a time by reading the current plan, run one at a
  /// time.
  ///
  /// One isolate is regularly mistaken for "cannot race". It cannot race in
  /// the middle of a statement, which is not the same thing. [capture] and
  /// [sweepStaleSessions] both read the schedule, choose a gap in it, and
  /// write - with awaits in between for the database, the model and the
  /// notification channel. A second one entering during any of those awaits
  /// chooses against a plan that is half-written, and takes a slot the first
  /// has already promised.
  ///
  /// Not a hypothetical pairing: the Now screen sweeps every time the app
  /// resumes, and its composer is on the same screen.
  ///
  /// Only these two need it. Everything else that moves a block - `snooze`,
  /// `stuck`, `applyNegotiation` - writes to a time the user named rather
  /// than to a gap it went looking for, so there is nothing to lose a race
  /// over.
  /// Null until the first serialised call, and deliberately so.
  ///
  /// An eagerly-created `Future.value()` here belongs to whichever zone built
  /// the service. Widget tests build it in `setUp` and then call in under
  /// `fakeAsync`, so a continuation chained onto it is scheduled in a zone the
  /// test never drains, and every such test hangs rather than fails. Starting
  /// empty keeps the chain inside the zone that is actually using it.
  Future<void>? _planQueue;

  Future<T> _serialised<T>(Future<T> Function() action) {
    final previous = _planQueue;
    final result = previous == null ? action() : previous.then((_) => action());
    // The chain has to survive a failed operation. Without swallowing the
    // error here, one thrown exception poisons every later call on it.
    _planQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// A renegotiated block never lands closer than this to now, so accepting
  /// a proposal does not fire a nudge in the same breath.
  static const _negotiatedLeadMinutes = 5;

  /// Whether the last plan was made without the calendar Van was told to use.
  ///
  /// False when there is no permission at all: that is the user's choice, not
  /// a fault, and a banner about it would follow around every person who
  /// never wanted the feature. True only when Van had the grant, tried, and
  /// could not read - which is worth saying out loud, because the resulting
  /// plan looks perfectly normal and is quietly wrong.
  bool get calendarIsUnreadable => _calendarIsUnreadable;
  bool _calendarIsUnreadable = false;

  /// The timezone offset Van is currently planning and parsing in.
  Duration get utcOffset => _waking.utcOffset;

  /// Re-reads the timezone offset, rebuilding everything derived from it.
  ///
  /// Returns whether anything actually moved, so a caller on a hot path -
  /// every resume - can tell a no-op from a real change without comparing
  /// offsets itself.
  ///
  /// The offset used to be read once in `main.dart` and frozen: a process
  /// alive across a DST change or a flight kept planning in the old zone
  /// while the phone had moved on, so the parser and the planner disagreed
  /// about what day it was. That is issue 18 again - which was seven hours
  /// wide - in a one-hour form, and it lasted until Van was restarted.
  ///
  /// Van cannot read the clock itself: `DateTime.now()` outside
  /// `lib/platform/` and `main.dart` is a build failure, and deliberately so.
  /// The offset therefore arrives as an argument, from the composition root.
  ///
  /// Four things derive from it and all four are rebuilt together, because
  /// leaving any one behind reproduces the original bug in a narrower place:
  /// quiet hours and free-slot finding through [WakingHours], the suppression
  /// gate, the temporal parser that turns "friday" into an instant, and the
  /// calendar filter that resolves all-day entries onto local days. The
  /// suppression policy is copied rather than reconstructed so tuning set by
  /// the composition root survives - see [SuppressionPolicy.withWaking].
  ///
  /// Work already planned keeps the instants it was given. Those are correct
  /// UTC instants; it is only the wall-clock reading of them that changes.
  bool refreshTimezone(Duration offset) {
    if (offset == _waking.utcOffset) return false;

    _waking = _waking.withUtcOffset(offset);
    _suppression = _suppression.withWaking(_waking);
    // Four things now, not three. All-day calendar entries are stored as
    // dates rather than instants, so the filter resolves them against the
    // offset exactly as the waking window does - and left behind here it
    // would place someone else's all-day commitment on the wrong day, which
    // is issue 18 wearing a different hat.
    _calendarFilter = _calendarFilter.withUtcOffset(offset);
    _extractTask = ExtractTask(
      prompt: _prompts.extractTask,
      parser: TemporalParser(utcOffset: offset),
    );
    return true;
  }

  /// Captures [text], plans it, stores it and arms the notifications.
  ///
  /// Serialised against the sweep and against other captures - see
  /// [_planQueue].
  ///
  /// **When the sentence never said how long, the result carries a question
  /// and the plan is still built.** Not asking at all was the sharper defect
  /// - `SessionPlanner` substituted its default and blocked out time as
  /// though the user had said so - but asking *instead of* capturing would be
  /// a worse one. A thought held hostage to a question is a thought lost, and
  /// this app's entire promise is that saying it once is enough. So Van
  /// guesses, says what it guessed, asks, and rebuilds the plan if anyone
  /// answers: see [answerDuration].
  Future<CaptureResult> capture(String text) =>
      _serialised(() => _capture(text));

  Future<CaptureResult> _capture(String text) async {
    final now = _clock.now();

    // One sentence can be several jobs, and until this line it could only
    // ever be one. Each clause then goes through exactly the same parser,
    // capability and planner it always did - the splitter sits in front of
    // them and nothing downstream knows it exists. See `WP_CAPTURE.md` 2.1.
    final clauses = const SentenceSplitter().split(text);
    if (clauses.isEmpty) {
      return const CaptureResult(captured: []);
    }

    final captured = <CapturedTask>[];
    Clarification? question;
    String? questionAbout;
    int? assumed;

    for (final clause in clauses) {
      final draft = await _router.run(
        _extractTask,
        ExtractTaskInput(clause, now: now),
      );
      // A model that asked for something specific wins over the standing
      // rule; otherwise the rule decides. Either way the question is about
      // the draft, not about the sentence, so a duration the parser found in
      // the text silences it exactly as one the model found does.
      final asked = draft.clarification ?? _questions.about(draft);

      final task = Task(
        id: _ids.next(),
        title: draft.title,
        createdAt: now,
        deadline: draft.deadline,
        estimatedMinutes: draft.estimatedMinutes,
        priority: draft.priority,
        status: TaskStatus.active,
        source: TaskSource.quickAdd,
        depth: draft.depth.depth,
      );
      await _tasks.save(task);
      await _events.append(EventType.taskCreated, {
        'taskId': task.id,
        'title': task.title,
        'deadline': task.deadline?.toIso8601String(),
        'estimatedMinutes': task.estimatedMinutes,
        'depth': task.depth.name,
        // How sure the reading was, recorded here rather than stored on the
        // task. Nothing acts on it - the planner reads depth alone - and this
        // is a fact about a moment's reading of a sentence, which is exactly
        // what the log is for. It is also how anyone finds out later whether
        // a verb list was worth trusting. See DECISIONS_PENDING D73.
        'depthConfidence': draft.depth.confidence,
        // The words this task came out of, when it was one of several. A
        // split that went wrong is otherwise impossible to find later, and
        // this is a fact about how the task came to exist rather than content
        // about it. Absent when the sentence was not split at all, because
        // then it is just the title again.
        if (clauses.length > 1) 'from': text,
      });

      // **One question for the whole capture.** Five clauses with no stated
      // durations would otherwise ask five times, which is the form
      // `CaptureQuestions` exists to prevent, arriving by another route.
      if (asked != null && question == null) {
        question = asked;
        questionAbout = task.id;
        assumed = task.estimatedMinutes == null
            ? _constraints.defaultEstimateMinutes
            : null;
        await _events.append(EventType.clarificationAsked, {
          'taskId': task.id,
          'field': asked.field.name,
        });
      }

      final planned = await _planFor(task, now);
      captured.add(
        CapturedTask(
          task: planned.task,
          sessions: planned.sessions,
          shortfallMinutes: planned.shortfallMinutes,
        ),
      );
    }

    return CaptureResult(
      captured: captured,
      clarification: question,
      clarificationTaskId: questionAbout,
      assumedMinutes: assumed,
    );
  }

  /// Answers a question [capture] asked, and rebuilds the plan on the answer.
  ///
  /// Serialised with capture and the sweep, because it chooses times: it
  /// throws away the blocks that were planned on Van's guess and plans the
  /// task again on what the user actually said.
  ///
  /// **Only untouched work is re-planned.** If a block of this task has been
  /// started, or resolved, the answer arrives too late and nothing moves -
  /// re-planning under someone mid-session would take away the block they are
  /// sitting in, which is a worse outcome than an estimate staying wrong.
  Future<AnswerResult> answerDuration(String taskId, String answer) =>
      _serialised(() => _answerDuration(taskId, answer));

  Future<AnswerResult> _answerDuration(String taskId, String answer) async {
    final minutes = _extractTask.parser.durationIn(answer);
    if (minutes == null || minutes <= 0) {
      return const AnswerResult(AnswerOutcome.notUnderstood);
    }

    final task = await _tasks.byId(taskId);
    if (task == null) return const AnswerResult(AnswerOutcome.tooLate);

    final existing = await _sessions.forTask(taskId);
    if (existing.any((s) => s.hasStarted || s.isResolved)) {
      return const AnswerResult(AnswerOutcome.tooLate);
    }

    for (final session in existing) {
      await _notifications.cancelForSession(session.id);
      await _nudges.deleteForSession(session.id);
      await _sessions.delete(session.id);
    }

    final revised = task.copyWith(estimatedMinutes: minutes);
    await _tasks.save(revised);
    await _events.append(EventType.clarificationAnswered, {
      'taskId': taskId,
      'field': TaskField.duration.name,
      'minutes': minutes,
      'blocksReplaced': existing.length,
    });

    final planned = await _planFor(revised, _clock.now());
    return AnswerResult(
      AnswerOutcome.replanned,
      task: planned.task,
      sessions: planned.sessions,
    );
  }

  Future<CapturedTask> _planFor(Task task, DateTime now) async {
    final existing = await _sessions.unresolved();
    final slots = await _freeSlots(around: existing, from: now);

    final result = SessionPlanner(
      ids: _ids,
      waking: _waking,
      constraints: _constraints,
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

    return CapturedTask(
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
  /// Every stretch of the next week the user is actually free.
  ///
  /// Commitments arrive from two sources and the finder cannot tell them
  /// apart: Van's own unresolved sessions, and whatever the device calendar
  /// says. That second half is not a feature so much as a correctness fix -
  /// before it, Van planned every day as if nothing else were on it and would
  /// cheerfully schedule work into a meeting the user had already agreed to.
  Future<List<FreeSlot>> _freeSlots({
    required Iterable<WorkSession> around,
    required DateTime from,
  }) async {
    final to = from.add(const Duration(days: 7));
    return FreeSlotFinder(waking: _waking).find(
      commitments: [
        for (final s in around)
          Commitment(start: s.plannedStart, end: s.plannedEnd, label: s.taskId),
        ...await _calendarCommitments(from, to),
      ],
      from: from,
      to: to,
    );
  }

  /// What the device calendar claims of the stretch between [from] and [to].
  ///
  /// **Read at plan time and never copied into Van's database.** The OS
  /// already persists the calendar and is the source of truth for it, so a
  /// copy here would only have to be invalidated - and the `events` table is
  /// append-only, which means anything written into it about a meeting is
  /// there permanently. This runs on capture and on sweep: a handful of
  /// platform calls a day, not a hot path.
  ///
  /// **A failed read must never fail the capture.** If the permission was
  /// revoked, the provider errored or the read timed out, Van plans with its
  /// own sessions and carries on - the user's typed sentence is worth more
  /// than a perfect plan. That is the lesson from a failed alarm once taking
  /// a whole capture down with it, in exactly this shape. The degradation is
  /// surfaced on the Now screen through [calendarIsUnreadable] rather than as
  /// an error on the thing the user was doing.
  Future<List<Commitment>> _calendarCommitments(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final read = await _readCalendar(from, to);
      // Not having the grant is not a degradation, it is a choice, and
      // reporting it as one would put a banner on the screen of every user
      // who never wanted this.
      _calendarIsUnreadable = false;
      if (read == null) return const [];

      final commitments = _calendarFilter.commitments(read.entries);

      // The count, never the content. Without this row, a day where Van
      // scheduled almost nothing looks identical to a day where it worked
      // correctly around a full calendar.
      await _events.append(EventType.calendarRead, {
        'commitments': commitments.length,
        'entries': read.entries.length,
        'excludedCalendars': read.excluded,
      });
      return commitments;
    } on Object catch (error) {
      _calendarIsUnreadable = true;
      await _noteCalendarFailure(error);
      return const [];
    }
  }

  /// Reads the calendar, or null when there is no permission to read it.
  ///
  /// Deliberately does no logging and touches no state: the two callers want
  /// different things from a read and only one of them is planning. Errors
  /// are left to propagate, because who absorbs them - and what they mean -
  /// differs between the two as well.
  Future<({List<CalendarEntry> entries, int excluded})?> _readCalendar(
    DateTime from,
    DateTime to,
  ) async {
    if (!await _calendars.hasPermission()) return null;

    final excluded = await _calendarPreferences?.excluded() ?? const <String>{};
    final entries = await _calendars.between(
      from: from,
      to: to,
      exclude: excluded,
    );
    return (entries: entries, excluded: excluded.length);
  }

  /// Everything on the user's calendars between [from] and [to], for drawing
  /// rather than for planning.
  ///
  /// Four differences from the planning read, all deliberate. It returns
  /// *every* entry rather than only the blocking ones, because a view that
  /// silently hid the meetings the user marked free would look broken to the
  /// person who marked them. It writes no `calendarRead` row, because looking
  /// at your week is not a planning decision and a row per scroll would drown
  /// the log. It leaves [calendarIsUnreadable] alone, because that flag is a
  /// statement about the *plan* on screen and a failed redraw says nothing
  /// about it. And a failure returns nothing rather than propagating: a
  /// calendar view missing its events is a lesser thing than a screen that
  /// will not paint.
  Future<List<CalendarOccurrence>> calendarOccurrences({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final read = await _readCalendar(from, to);
      if (read == null) return const [];

      return [
        for (final entry in read.entries)
          if (_calendarFilter.span(entry) case final at?)
            CalendarOccurrence(
              calendarId: entry.calendarId,
              start: at.start,
              end: at.end,
              title: entry.title,
              isAllDay: entry.isAllDay,
              blocks: _calendarFilter.blocks(entry),
              attendance: entry.attendance,
            ),
      ]..sort((a, b) => a.start.compareTo(b.start));
    } on Object catch (_) {
      return const [];
    }
  }

  /// Everything on the user's plan between [from] and [to].
  ///
  /// Blocks are those that *start* in the window, which is the query the
  /// database is indexed for. A block that runs past midnight therefore
  /// belongs to the day it began on, which is also how a person would file
  /// it - and a view that wants the tail of it asks for a slightly wider
  /// window rather than for a different query.
  Future<DayPlan> planBetween({
    required DateTime from,
    required DateTime to,
  }) async {
    final sessions = await _sessions.plannedBetween(from, to);

    final tasks = <String, Task>{};
    final blocks = <({WorkSession session, Task task})>[];
    for (final session in sessions) {
      final task = tasks[session.taskId] ?? await _tasks.byId(session.taskId);
      // A session whose task has been deleted is not drawable and not worth
      // failing the whole day over.
      if (task == null) continue;
      tasks[task.id] = task;
      blocks.add((session: session, task: task));
    }

    return DayPlan(
      blocks: blocks,
      events: await calendarOccurrences(from: from, to: to),
    );
  }

  /// What the log already knows about [session], for judging a proposal.
  ///
  /// **Every one of these numbers existed before and none of them reached the
  /// decision.** `Negotiate` saw the ladder rung and the block length while
  /// the move count, the start history and the calendar sat in the database
  /// being used for nothing. That is `WP_JUDGEMENT.md` 13c, and this method is
  /// the whole of the reading half.
  ///
  /// Three queries on a path the user is waiting on, so each one is bounded:
  /// the task's own sessions, four weeks of blocks at this hour, and a
  /// four-hour window of calendar. None of them is a scan of the event log.
  Future<NegotiationEvidence> _evidenceFor(
    WorkSession session,
    DateTime now,
  ) async {
    final siblings = await _sessions.forTask(session.taskId);
    final byId = {for (final s in siblings) s.id: s};

    // The chain of reschedules this block *is*, walked back through
    // parentSessionId - not every block of the task. Starting the first hour
    // of a three-hour task says nothing about whether the third hour will
    // begin, and treating them as one history would make "ever started" mean
    // almost nothing.
    var everStarted = false;
    for (
      WorkSession? link = session;
      link != null;
      link = byId[link.parentSessionId]
    ) {
      if (link.hasStarted) {
        everStarted = true;
        break;
      }
      // A chain cannot contain itself, but a corrupt parent pointer could
      // make it look like one. Stopping at the first repeat costs nothing and
      // turns a hang into a shorter answer.
      if (link.parentSessionId == link.id) break;
    }

    final hour = _waking.toLocalWall(session.plannedStart).hour;
    var startsAtHour = 0;
    var blocksAtHour = 0;
    for (final past in await _sessions.plannedBetween(
      now.subtract(const Duration(days: 28)),
      now,
    )) {
      if (_waking.toLocalWall(past.plannedStart).hour != hour) continue;
      blocksAtHour++;
      if (past.hasStarted) startsAtHour++;
    }

    // Two hours either side, which is the stretch a "move it later today"
    // would land in. Read for drawing rather than for planning, so it writes
    // no row and a broken provider costs the evidence and nothing else.
    const half = Duration(hours: 2);
    final from = session.plannedStart.subtract(half);
    final to = session.plannedStart.add(half);
    var busy = 0;
    for (final event in await calendarOccurrences(from: from, to: to)) {
      if (!event.blocks) continue;
      final start = event.start.isAfter(from) ? event.start : from;
      final end = event.end.isBefore(to) ? event.end : to;
      if (end.isAfter(start)) busy += end.difference(start).inMinutes;
    }
    final window = to.difference(from).inMinutes;

    return NegotiationEvidence(
      moves: session.rescheduleCount,
      everStarted: everStarted,
      startsAtThisHour: startsAtHour,
      blocksAtThisHour: blocksAtHour,
      // Overlapping meetings can add up past the window; clamped, because a
      // density over 1 is not a fact about anything.
      calendarBusyMinutes: busy > window ? window : busy,
      calendarWindowMinutes: window,
    );
  }

  /// Records a failed calendar read, and never throws doing it.
  ///
  /// The guard is the point: this is called from the one path whose entire
  /// promise is that a broken calendar cannot cost the user their capture,
  /// and an unguarded log write would hand that promise straight back.
  Future<void> _noteCalendarFailure(Object error) async {
    try {
      await _events.append(EventType.calendarUnavailable, {
        // The type and message of Van's own platform exception. Nothing here
        // comes from a calendar row.
        'reason': '${error.runtimeType}',
      });
    } on Object catch (_) {}
  }

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
        type: await _nudges.consecutiveUnansweredLadders(type, fatigueSince),
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

      // `Notifications.schedule` already absorbs the one refusal that is
      // expected - the exact-alarm permission - by dropping to an inexact
      // alarm. Anything else it rethrows, and by this point the task, the
      // block and their events are all committed. Letting that exception out
      // would abandon a capture the user has already been told about, and
      // lose the sentence they typed, over a reminder. A block with one
      // fewer rung is a far smaller harm, so the failure is recorded and the
      // ladder carries on.
      //
      // The nudge row above still says `wasSuppressed: false`, and that is
      // correct rather than sloppy: Van did decide to send this one. That it
      // never reached the platform is a different fact, and it lives here.
      String? scheduleError;
      try {
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
      } on Object catch (e) {
        scheduleError = e.toString();
      }

      if (scheduleError != null) {
        // Not counted as armed: nothing went out, so the next rung must be
        // spaced against the last nudge that really did.
        await _events.append(EventType.nudgeScheduleFailed, {
          'sessionId': session.id,
          'level': level.name,
          'at': at.toIso8601String(),
          'error': scheduleError,
        });
        continue;
      }

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
  ///
  /// Serialised against [capture] and against itself - see [_planQueue].
  Future<SweepReport> sweepStaleSessions() => _serialised(_sweepStaleSessions);

  Future<SweepReport> _sweepStaleSessions() async {
    final now = _clock.now();
    final unresolved = await _sessions.unresolved();
    final stale = unresolved.where((s) => _sweep.isStale(s, now)).toList();
    if (stale.isEmpty) return const SweepReport();

    // The stale blocks are the ones being vacated, so their time is free
    // again and they must not be passed in as commitments against themselves.
    final staleIds = stale.map((s) => s.id).toSet();
    final slots = await _freeSlots(
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

  /// Marks [taskId] done, standing its blocks down.
  ///
  /// Safe to invoke on a task with blocks still planned - which is the common
  /// case, because work usually finishes somewhere other than where it was
  /// scheduled. Those blocks are marked skipped rather than completed: they
  /// genuinely never ran, and pretending otherwise would corrupt the record of
  /// what this person actually does.
  ///
  /// Any nudge that had already fired is settled as engagement. Finishing the
  /// work is the opposite of ignoring the ask, and letting those rungs rot
  /// unanswered would build fatigue against someone who did exactly what Van
  /// wanted.
  ///
  /// [source] names the surface it was finished from. It used to be the
  /// string `task_list` because a swipe on that screen was the only way to
  /// finish anything; there are now three, and which one people actually use
  /// is worth knowing before deciding which to keep.
  Future<Task?> completeTask(
    String taskId, {
    String source = 'task_list',
    int? actualMinutes,
  }) async {
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

    final done = task.copyWith(
      status: TaskStatus.done,
      actualMinutes: actualMinutes,
    );
    await _tasks.save(done);
    await _events.append(EventType.taskUpdated, {
      'taskId': taskId,
      'status': TaskStatus.done.name,
      'source': source,
      'blocksStoodDown': open.length,
      'actualMinutes': ?actualMinutes,
      'estimatedMinutes': ?task.estimatedMinutes,
    });
    return done;
  }

  /// Records how long [taskId] actually took, after the fact.
  ///
  /// Separate from [completeTask] because finishing something and knowing how
  /// long it took are different moments. Forcing them together would make
  /// every completion a two-step action, and the number would get guessed to
  /// get past the dialog - which is worse than not having it.
  ///
  /// Works on an open task too. Someone who has spent three hours on
  /// something and is not finished has learned the estimate was wrong, and
  /// that is worth recording before they forget.
  Future<Task?> recordActualMinutes(String taskId, int minutes) async {
    if (minutes <= 0) return null;
    final task = await _tasks.byId(taskId);
    if (task == null) return null;

    final updated = task.copyWith(actualMinutes: minutes);
    await _tasks.save(updated);
    await _events.append(EventType.taskUpdated, {
      'taskId': taskId,
      'source': 'time_taken',
      'actualMinutes': minutes,
      // Both, so the log carries the comparison rather than requiring a join
      // against whatever the estimate happened to be at the time.
      'estimatedMinutes': ?task.estimatedMinutes,
    });
    return updated;
  }

  /// How much time Van actually watched being spent on [taskId], in minutes.
  ///
  /// Only blocks that were started and finished count, and only the time
  /// between those two instants. **This is not the same as how long the work
  /// took** - it is how long the user sat in a Van block for it, which
  /// excludes everything done outside the app. It exists to pre-fill the
  /// question rather than to answer it, which is the whole difference between
  /// a measurement and an assumption.
  Future<int> measuredMinutes(String taskId) async {
    var total = 0;
    for (final session in await _sessions.forTask(taskId)) {
      final from = session.actualStart;
      final to = session.actualEnd;
      if (from == null || to == null || !to.isAfter(from)) continue;
      total += to.difference(from).inMinutes;
    }
    return total;
  }

  /// Everything finished, most recently created first.
  Future<List<Task>> finishedTasks({int limit = 20}) async {
    final all = await _tasks.all();
    return [
      for (final task in all)
        if (task.status == TaskStatus.done) task,
    ].take(limit).toList();
  }

  /// Removes [taskId] entirely: the task, its blocks and its armed nudges.
  ///
  /// **A delete, not `TaskStatus.abandoned`, and the difference is not
  /// cosmetic.** Abandoned means *the user gave up on this work*, and that
  /// distinction exists so Van can learn what this person follows through on.
  /// Someone clearing a task off the list because it was a mistake, a
  /// duplicate, or no longer a thing that needs doing has not given up on
  /// anything, and recording it as though they had would poison the only
  /// signal that status carries.
  ///
  /// **Nothing is truly lost.** The `events` table is append-only: the
  /// `taskCreated` row, every `sessionPlanned`, every nudge decision all stay
  /// exactly where they were, joined now by this one. What goes is the task's
  /// place in the live list.
  Future<bool> deleteTask(String taskId, {String reason = 'deleted'}) async {
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
      'status': reason,
      'blocksRemoved': sessions.length,
    });
    return true;
  }

  /// Puts a finished task back on the list and plans it again.
  ///
  /// Exists because finishing is now one tap on the main screen rather than a
  /// deliberate swipe, and a one-tap irreversible action next to a list of
  /// tasks is a trap. This is the way back out.
  ///
  /// **It is not a true undo and does not pretend to be.** The blocks that
  /// were stood down stay skipped - the log is append-only and they really
  /// were skipped - and the task is planned afresh, so it comes back at
  /// whatever times are free *now* rather than the ones it had before. That is
  /// honest and it is also usually what someone wants: they finished it by
  /// accident a moment ago, and the plan around it has not moved.
  ///
  /// Serialised, because it picks times.
  Future<Task?> reopenTask(String taskId) => _serialised(() async {
    final task = await _tasks.byId(taskId);
    if (task == null || task.status != TaskStatus.done) return null;

    final active = task.copyWith(status: TaskStatus.active);
    await _tasks.save(active);
    await _events.append(EventType.taskUpdated, {
      'taskId': taskId,
      'status': TaskStatus.active.name,
      'source': 'undo',
    });

    final planned = await _planFor(active, _clock.now());
    return planned.task;
  });

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
  Future<bool> undoCapture(String taskId) =>
      deleteTask(taskId, reason: 'undone');

  /// Takes back a whole capture, however many tasks the sentence made.
  ///
  /// One sentence, one undo. A five-tap undo for one mis-typed line would be
  /// its own bug, and the user did not make five decisions - they made one.
  Future<int> undoCaptureAll(Iterable<String> taskIds) async {
    var removed = 0;
    for (final id in taskIds) {
      if (await undoCapture(id)) removed++;
    }
    return removed;
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
      evidence: await _evidenceFor(session, now),
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
      // The evidence the decision was taken on, so a proposal that looks
      // wrong later can be judged against what was actually known at the
      // time rather than against what is true now. Counts only: no titles,
      // no calendar ids, nothing that was not already a number.
      'everStarted': input.evidence.everStarted,
      'startsAtHour': input.evidence.startsAtThisHour,
      'blocksAtHour': input.evidence.blocksAtThisHour,
      'calendarBusyPercent': (input.evidence.calendarDensity * 100).round(),
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
      evidence: await _evidenceFor(session, now),
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
