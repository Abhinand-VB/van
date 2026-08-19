import 'package:nova_core/nova_core.dart';
import 'package:test/test.dart';

/// Drives the nudge engine across a virtual timeline with scripted responses.
///
/// This is the single highest-value test asset in the project. Tuning whether
/// Nova feels present or feels like spam means replaying days of behaviour
/// against different weights, and nobody is going to do that by living through
/// it. A simulated week here runs in milliseconds.
///
/// The harness ticks once per virtual minute, which is finer than the real
/// alarm schedule and therefore strictly harder to pass.
class SimulationHarness {
  /// Creates a harness parked at [startAt].
  SimulationHarness({
    required DateTime startAt,
    NudgeEngine? engine,
    WakingHours waking = const WakingHours(utcOffset: Duration.zero),
    PlannerConstraints constraints = const PlannerConstraints(),
  }) : _clock = FakeClock(startAt),
       _waking = waking,
       _engine =
           engine ??
           NudgeEngine(suppression: SuppressionPolicy(waking: waking)),
       _planner = SessionPlanner(
         ids: SequentialIds('s'),
         constraints: constraints,
         waking: waking,
       );

  final FakeClock _clock;
  final WakingHours _waking;
  final NudgeEngine _engine;
  final SessionPlanner _planner;

  final _tasks = <String, Task>{};
  final _sessions = <String, WorkSession>{};
  final _gaveReason = <String>{};
  final _refused = <String>{};
  final _responses = <String, List<ResponseType>>{};
  final _dismissals = <NudgeType, int>{};
  final _timeline = <String>[];

  DateTime? _lastNudgeAt;
  String? _lastNudgeSessionId;
  final _lastLevelBySession = <String, InterventionLevel>{};
  NudgeDecision? _pending;
  String? _pendingSessionId;
  int _taskSeq = 0;

  /// The current virtual instant.
  DateTime get now => _clock.now();

  /// Every delivered nudge and notable event, in order, as readable lines.
  List<String> get timeline => List.unmodifiable(_timeline);

  /// Adds a task and returns its id.
  String addTask(
    String title, {
    DateTime? deadline,
    int minutes = 60,
  }) {
    final id = 't${++_taskSeq}';
    _tasks[id] = Task(
      id: id,
      title: title,
      createdAt: now,
      deadline: deadline,
      estimatedMinutes: minutes,
      status: TaskStatus.active,
    );
    _log('task added: $title (${minutes}m)');
    return id;
  }

  /// Plans sessions for every task, across [days] of free time.
  ///
  /// Returns the sessions created, so a scenario can assert on the plan
  /// itself rather than only on the nudges that follow.
  List<WorkSession> planSessions({int days = 7}) {
    final created = <WorkSession>[];

    for (final task in _tasks.values) {
      final slots = FreeSlotFinder(waking: _waking).find(
        commitments: _sessions.values
            .map(
              (s) => Commitment(
                start: s.plannedStart,
                end: s.plannedEnd,
                label: s.taskId,
              ),
            )
            .toList(),
        from: now,
        to: now.add(Duration(days: days)),
      );
      final result = _planner.plan(task: task, slots: slots, clock: _clock);
      final placed = result.okOrNull ?? result.errOrNull!.scheduled;
      for (final session in placed) {
        _sessions[session.id] = session;
        created.add(session);
      }
      if (result.isErr) {
        _log(
          'plan incomplete for ${task.title}: short by '
          '${result.errOrNull!.shortfallMinutes}m',
        );
      }
    }
    _log('${created.length} session(s) planned');
    return created;
  }

  /// Schedules a session directly, bypassing the planner.
  ///
  /// Scenarios that are about escalation rather than planning use this so the
  /// timing under test is explicit.
  WorkSession scheduleSession({
    required String taskId,
    required DateTime start,
    int minutes = 45,
    int rescheduleCount = 0,
  }) {
    final session = WorkSession(
      id: 's${_sessions.length + 1}',
      taskId: taskId,
      plannedStart: start,
      plannedMinutes: minutes,
      rescheduleCount: rescheduleCount,
    );
    _sessions[session.id] = session;
    _log('session ${session.id} at ${_hhmm(start)} (${minutes}m)');
    return session;
  }

  /// Advances to [target], ticking every virtual minute along the way.
  void advanceTo(DateTime target) {
    while (_clock.now().isBefore(target)) {
      _clock.advance(const Duration(minutes: 1));
      _tick();
    }
  }

  /// Advances by a duration, ticking every virtual minute.
  void advanceBy({int minutes = 0, int hours = 0, int days = 0}) => advanceTo(
    _clock.now().add(
      Duration(minutes: minutes, hours: hours, days: days),
    ),
  );

  void _tick() {
    final state = NudgeEngineState(
      sessions: _sessions.values
          .map(
            (s) => SessionContext(
              session: s,
              task: _tasks[s.taskId]!,
              priorResponses: _responses[s.id] ?? const [],
              userGaveReason: _gaveReason.contains(s.id),
              userRefused: _refused.contains(s.id),
            ),
          )
          .toList(),
      lastNudgeAt: _lastNudgeAt,
      lastNudgeSessionId: _lastNudgeSessionId,
      lastLevelBySession: _lastLevelBySession,
      consecutiveDismissals: _dismissals,
    );

    for (final decision in _engine.tick(_clock.now(), state)) {
      if (!decision.willDeliver) continue;
      _lastNudgeAt = _clock.now();
      _lastNudgeSessionId = decision.sessionId;
      _lastLevelBySession[decision.sessionId!] = decision.level;
      _pending = decision;
      _pendingSessionId = decision.sessionId;
      _log(
        'NUDGE ${decision.type.name} ${decision.level.name} '
        'score=${decision.importance} session=${decision.sessionId}',
      );
    }
  }

  /// Asserts a nudge is waiting, optionally of a particular level or type.
  void expectNudge({InterventionLevel? level, NudgeType? type}) {
    expect(
      _pending,
      isNotNull,
      reason: 'expected a nudge at ${_hhmm(now)}\n${dumpTimeline()}',
    );
    if (level != null) {
      expect(
        _pending!.level,
        level,
        reason: 'wrong level at ${_hhmm(now)}\n${dumpTimeline()}',
      );
    }
    if (type != null) {
      expect(
        _pending!.type,
        type,
        reason: 'wrong type at ${_hhmm(now)}\n${dumpTimeline()}',
      );
    }
  }

  /// Asserts nothing is waiting for the user.
  void expectNoNudge() {
    expect(
      _pending,
      isNull,
      reason: 'unexpected nudge at ${_hhmm(now)}\n${dumpTimeline()}',
    );
  }

  /// The user presses START.
  void userStarts() {
    final id = _requirePending();
    _sessions[id] = _sessions[id]!.start(now);
    _record(id, ResponseType.started);
    _dismissals.clear();
    _pending = null;
    _log('user STARTED $id');
  }

  /// The user finishes the running session.
  void userCompletes(String sessionId) {
    _sessions[sessionId] = _sessions[sessionId]!.complete(now);
    _log('user COMPLETED $sessionId');
  }

  /// The user swipes the nudge away without engaging.
  void userIgnores() {
    final id = _requirePending();
    final type = _pending!.type;
    _dismissals[type] = (_dismissals[type] ?? 0) + 1;
    _record(id, ResponseType.ignored);
    _pending = null;
    _log('user IGNORED $id (streak ${_dismissals[type]})');
  }

  /// The user explains themselves.
  void userSays(String reason) {
    final id = _requirePending();
    _gaveReason.add(id);
    _record(id, ResponseType.reason);
    _pending = null;
    _log('user SAID "$reason" about $id');
  }

  /// The user says no outright.
  void userRefuses() {
    final id = _requirePending();
    _refused.add(id);
    _record(id, ResponseType.dismissed);
    _pending = null;
    _log('user REFUSED $id');
  }

  /// Moves the pending session to [newStart], as the L5 concession does.
  void rescheduleTo(DateTime newStart, {int? minutes}) {
    final id = _requirePending();
    final old = _sessions[id]!;
    _sessions[id] = old.markRescheduled();
    final next = old.replacement(
      newId: 's${_sessions.length + 1}',
      newStart: newStart,
      newMinutes: minutes,
    );
    _sessions[next.id] = next;
    _gaveReason.remove(id);
    _refused.remove(id);
    _pending = null;
    _log(
      'rescheduled $id -> ${next.id} at ${_hhmm(newStart)} '
      '(move ${next.rescheduleCount})',
    );
  }

  /// The session currently under discussion, if any.
  WorkSession? get pendingSession =>
      _pendingSessionId == null ? null : _sessions[_pendingSessionId];

  /// How many nudges have actually reached the user.
  int get deliveredCount => _timeline.where((l) => l.contains('NUDGE')).length;

  /// A readable dump of everything that happened, for failure messages and
  /// for eyeballing whether a week of Nova would be tolerable.
  String dumpTimeline() =>
      '--- simulation timeline ---\n${_timeline.join('\n')}\n---';

  String _requirePending() {
    expect(
      _pending,
      isNotNull,
      reason: 'no nudge to respond to at ${_hhmm(now)}\n${dumpTimeline()}',
    );
    return _pending!.sessionId!;
  }

  void _record(String sessionId, ResponseType response) =>
      (_responses[sessionId] ??= <ResponseType>[]).add(response);

  void _log(String line) => _timeline.add('${_hhmm(now)}  $line');

  String _hhmm(DateTime utc) {
    final wall = _waking.toLocalWall(utc);
    final d = wall.day.toString().padLeft(2, '0');
    final h = wall.hour.toString().padLeft(2, '0');
    final m = wall.minute.toString().padLeft(2, '0');
    return 'D$d $h:$m';
  }
}
