import 'package:nova_core/nova_core.dart';
import 'package:test/test.dart';

DateTime u(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, day, hour, minute);

const utcWaking = WakingHours(utcOffset: Duration.zero);

void main() {
  group('InterventionPolicy', () {
    const policy = InterventionPolicy();

    test('on time is a plain prompt', () {
      expect(
        policy.select(const InterventionContext()),
        InterventionLevel.l0Gentle,
      );
    });

    test('escalates with lateness', () {
      expect(
        policy.select(const InterventionContext(minutesLate: 9)),
        InterventionLevel.l0Gentle,
      );
      expect(
        policy.select(const InterventionContext(minutesLate: 10)),
        InterventionLevel.l1Check,
      );
      expect(
        policy.select(const InterventionContext(minutesLate: 24)),
        InterventionLevel.l1Check,
      );
      expect(
        policy.select(const InterventionContext(minutesLate: 25)),
        InterventionLevel.l2Diagnose,
      );
    });

    test('a reason is met with a smaller ask, not a louder one', () {
      expect(
        policy.select(
          const InterventionContext(minutesLate: 40, userGaveReason: true),
        ),
        InterventionLevel.l3Shrink,
      );
    });

    test('a refusal outranks lateness', () {
      // Continuing to escalate at someone who already said no is how an
      // accountability app becomes an uninstalled app.
      expect(
        policy.select(
          const InterventionContext(minutesLate: 90, userRefused: true),
        ),
        InterventionLevel.l3Shrink,
      );
    });

    test('repeated moves plus a near deadline reach renegotiation', () {
      expect(
        policy.select(
          const InterventionContext(rescheduleCount: 3, hoursToDeadline: 20),
        ),
        InterventionLevel.l4Renegotiate,
      );
    });

    test('repeated moves without a near deadline do not', () {
      expect(
        policy.select(const InterventionContext(rescheduleCount: 5)),
        InterventionLevel.l0Gentle,
      );
      expect(
        policy.select(
          const InterventionContext(rescheduleCount: 5, hoursToDeadline: 100),
        ),
        InterventionLevel.l0Gentle,
      );
    });

    test('refusing at renegotiation makes Nova concede', () {
      expect(
        policy.select(
          const InterventionContext(
            rescheduleCount: 3,
            hoursToDeadline: 10,
            userRefused: true,
          ),
        ),
        InterventionLevel.l5Concede,
      );
    });

    test('classifies which levels shrink and which concede', () {
      expect(
        InterventionPolicy.offersShrink(InterventionLevel.l3Shrink),
        isTrue,
      );
      expect(
        InterventionPolicy.offersShrink(InterventionLevel.l4Renegotiate),
        isTrue,
      );
      expect(
        InterventionPolicy.offersShrink(InterventionLevel.l0Gentle),
        isFalse,
      );
      expect(InterventionPolicy.concedes(InterventionLevel.l5Concede), isTrue);
      expect(InterventionPolicy.concedes(InterventionLevel.l1Check), isFalse);
    });

    test('counts ignored replies', () {
      const context = InterventionContext(
        priorResponses: [
          ResponseType.ignored,
          ResponseType.dismissed,
          ResponseType.ignored,
        ],
      );
      expect(context.ignoredCount, 2);
    });

    test('custom thresholds are honoured', () {
      const eager = InterventionPolicy(checkAfterMinutes: 2);
      expect(
        eager.select(const InterventionContext(minutesLate: 3)),
        InterventionLevel.l1Check,
      );
    });
  });

  group('ImportanceScorer', () {
    const scorer = ImportanceScorer();

    test('starts from the type baseline', () {
      expect(
        scorer.score(const ScoringContext(type: NudgeType.sessionStart)),
        6,
      );
      expect(scorer.score(const ScoringContext(type: NudgeType.hydration)), 2);
    });

    test('a deadline inside a day lifts the score', () {
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionStart,
            hoursToDeadline: 20,
          ),
        ),
        8,
      );
    });

    test('a deadline inside six hours lifts it further', () {
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionStart,
            hoursToDeadline: 3,
          ),
        ),
        9,
      );
    });

    test('repeated moves add urgency, but only up to a cap', () {
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionStart,
            rescheduleCount: 2,
          ),
        ),
        8,
      );
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionStart,
            rescheduleCount: 99,
          ),
        ),
        9,
      );
    });

    test('a recent interruption about something else costs points', () {
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionStart,
            minutesSinceLastNudge: 5,
          ),
        ),
        3,
      );
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionStart,
            minutesSinceLastNudge: 45,
          ),
        ),
        5,
      );
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionStart,
            minutesSinceLastNudge: 120,
          ),
        ),
        6,
      );
    });

    test('dismissals cost points', () {
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionMissed,
            consecutiveDismissals: 2,
          ),
        ),
        3,
      );
    });

    test('continuing one conversation skips the recency and fatigue costs', () {
      // Applying them inside a single escalation drove the score below
      // threshold before the ladder could reach L1 - the bug the simulation
      // harness caught.
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.sessionMissed,
            minutesSinceLastNudge: 5,
            consecutiveDismissals: 2,
            continuesSameSession: true,
          ),
        ),
        7,
      );
    });

    test('the score never leaves 0 to 10', () {
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.hydration,
            consecutiveDismissals: 9,
          ),
        ),
        0,
      );
      expect(
        scorer.score(
          const ScoringContext(
            type: NudgeType.meetingImminent,
            hoursToDeadline: 1,
            rescheduleCount: 5,
          ),
        ),
        10,
      );
    });

    test('the threshold is what decides delivery', () {
      expect(scorer.clearsThreshold(5), isTrue);
      expect(scorer.clearsThreshold(4), isFalse);
    });
  });

  group('SuppressionPolicy', () {
    const policy = SuppressionPolicy(waking: utcWaking);

    SuppressionContext ctx({
      NudgeType type = NudgeType.sessionStart,
      DateTime? now,
      bool focus = false,
      int? since,
      int dismissals = 0,
      bool dnd = false,
      bool continues = false,
    }) => SuppressionContext(
      type: type,
      now: now ?? u(19, 18),
      focusInProgress: focus,
      minutesSinceLastNudge: since,
      consecutiveDismissals: dismissals,
      deviceDoNotDisturb: dnd,
      continuesSameSession: continues,
    );

    test('allows an ordinary nudge in the middle of the day', () {
      expect(policy.evaluate(ctx()).suppressed, isFalse);
    });

    test('blocks anything outside waking hours', () {
      expect(
        policy.evaluate(ctx(now: u(19, 3))).reason,
        SuppressionReason.quietHours,
      );
      expect(
        policy.evaluate(ctx(now: u(19, 23, 30))).reason,
        SuppressionReason.quietHours,
      );
    });

    test('a hard commitment still gets through at 3am', () {
      expect(
        policy
            .evaluate(ctx(type: NudgeType.meetingImminent, now: u(19, 3)))
            .suppressed,
        isFalse,
      );
    });

    test('never interrupts work it asked for', () {
      expect(
        policy.evaluate(ctx(focus: true)).reason,
        SuppressionReason.focusInProgress,
      );
    });

    test('respects device do-not-disturb', () {
      expect(
        policy.evaluate(ctx(dnd: true)).reason,
        SuppressionReason.deviceDoNotDisturb,
      );
    });

    test('stops after repeated dismissals, whatever the importance', () {
      expect(
        policy.evaluate(ctx(dismissals: 3)).reason,
        SuppressionReason.dismissalFatigue,
      );
      expect(
        policy
            .evaluate(ctx(type: NudgeType.deadlineTomorrow, dismissals: 3))
            .reason,
        SuppressionReason.dismissalFatigue,
      );
    });

    test('enforces spacing between unrelated interruptions', () {
      expect(
        policy.evaluate(ctx(since: 5)).reason,
        SuppressionReason.tooSoonAfterLast,
      );
      expect(policy.evaluate(ctx(since: 25)).suppressed, isFalse);
    });

    test('an escalation about the same session may move faster', () {
      expect(
        policy.evaluate(ctx(since: 10, continues: true)).suppressed,
        isFalse,
      );
      expect(
        policy.evaluate(ctx(since: 3, continues: true)).reason,
        SuppressionReason.tooSoonAfterLast,
      );
    });

    test('an urgent nudge overrides the spacing rule', () {
      expect(
        policy
            .evaluate(ctx(type: NudgeType.deadlineTomorrow, since: 2))
            .suppressed,
        isFalse,
      );
    });

    test('the decision prints readably for the log', () {
      expect(policy.evaluate(ctx()).toString(), 'allowed');
      expect(
        policy.evaluate(ctx(focus: true)).toString(),
        'suppressed(focusInProgress)',
      );
    });
  });

  group('NudgeEngine', () {
    const engine = NudgeEngine(
      suppression: SuppressionPolicy(waking: utcWaking),
    );

    Task task({DateTime? deadline}) => Task(
      id: 't1',
      title: 'Assignment',
      createdAt: u(19, 8),
      deadline: deadline,
    );

    WorkSession session({
      String id = 's1',
      DateTime? start,
      SessionStatus status = SessionStatus.planned,
      DateTime? actualStart,
    }) => WorkSession(
      id: id,
      taskId: 't1',
      plannedStart: start ?? u(19, 18),
      plannedMinutes: 45,
      status: status,
      actualStart: actualStart,
    );

    test('says nothing when there is nothing due', () {
      final decisions = engine.tick(
        u(19, 17),
        NudgeEngineState(
          sessions: [SessionContext(session: session(), task: task())],
        ),
      );
      expect(decisions, isEmpty);
    });

    test('says nothing about a session already running', () {
      final decisions = engine.tick(
        u(19, 18),
        NudgeEngineState(
          sessions: [
            SessionContext(
              session: session(
                status: SessionStatus.started,
                actualStart: u(19, 18),
              ),
              task: task(),
            ),
          ],
        ),
      );
      expect(decisions, isEmpty);
    });

    test('says nothing about a resolved session', () {
      final decisions = engine.tick(
        u(19, 18),
        NudgeEngineState(
          sessions: [
            SessionContext(
              session: session(status: SessionStatus.skipped),
              task: task(),
            ),
          ],
        ),
      );
      expect(decisions, isEmpty);
    });

    test('gives up on a block that is hours stale', () {
      final decisions = engine.tick(
        u(19, 20),
        NudgeEngineState(
          sessions: [SessionContext(session: session(), task: task())],
        ),
      );
      expect(decisions, isEmpty);
    });

    test('holds back a repeat of the level already delivered', () {
      final decisions = engine.tick(
        u(19, 18),
        NudgeEngineState(
          sessions: [SessionContext(session: session(), task: task())],
          lastNudgeSessionId: 's1',
          lastLevelBySession: const {'s1': InterventionLevel.l0Gentle},
        ),
      );
      expect(
        decisions.single.suppressedBecause,
        SuppressionReason.nothingNewToSay,
      );
    });

    test('reports held-back nudges rather than hiding them', () {
      final decisions = engine.tick(
        u(19, 3),
        NudgeEngineState(
          sessions: [
            SessionContext(
              session: session(start: u(19, 3)),
              task: task(),
            ),
          ],
        ),
      );
      expect(decisions.single.willDeliver, isFalse);
      expect(decisions.single.suppressedBecause, SuppressionReason.quietHours);
    });

    test('speaks about at most one thing per tick', () {
      final decisions = engine.tick(
        u(19, 18),
        NudgeEngineState(
          sessions: [
            SessionContext(
              session: session(id: 'a'),
              task: task(deadline: u(19, 22)),
            ),
            SessionContext(
              session: session(id: 'b'),
              task: task(),
            ),
          ],
        ),
      );
      expect(decisions.where((d) => d.willDeliver).length, 1);
      expect(
        decisions.firstWhere((d) => !d.willDeliver).suppressedBecause,
        SuppressionReason.supersededByHigherPriority,
      );
    });

    test('a decision prints readably', () {
      final decisions = engine.tick(
        u(19, 18),
        NudgeEngineState(
          sessions: [SessionContext(session: session(), task: task())],
        ),
      );
      expect(decisions.single.toString(), contains('deliver'));
    });
  });
}
