import 'package:van_core/van_core.dart';
import 'package:test/test.dart';

DateTime u(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, day, hour, minute);

FreeSlot slot(DateTime start, DateTime end) => FreeSlot(start: start, end: end);

WorkSession session({
  String id = 's1',
  String taskId = 't1',
  DateTime? start,
  int minutes = 45,
  int moves = 0,
  SessionStatus status = SessionStatus.planned,
  DateTime? actualStart,
}) => WorkSession(
  id: id,
  taskId: taskId,
  plannedStart: start ?? u(19, 9),
  plannedMinutes: minutes,
  rescheduleCount: moves,
  status: status,
  actualStart: actualStart,
);

void main() {
  late StaleSessionSweep sweep;
  late FakeClock clock;

  setUp(() {
    sweep = StaleSessionSweep(
      rescheduler: Rescheduler(ids: SequentialIds('r')),
    );
    // 11:00, two hours after the 09:00 block these tests keep missing.
    clock = FakeClock(u(19, 11));
  });

  group('staleness', () {
    test('a block an hour and a minute past its start is stale', () {
      expect(sweep.isStale(session(start: u(19, 9, 59)), u(19, 11)), isTrue);
    });

    test('a block exactly at the give-up threshold is not yet stale', () {
      // The engine gives up *after* 60 minutes, so 60 is still a live
      // conversation and the sweep must keep its hands off it.
      expect(sweep.isStale(session(start: u(19, 10)), u(19, 11)), isFalse);
    });

    test('a started block is never stale, however long ago it began', () {
      expect(
        sweep.isStale(
          session(
            start: u(19, 9),
            status: SessionStatus.started,
            actualStart: u(19, 9),
          ),
          u(19, 20),
        ),
        isFalse,
      );
    });

    test('a resolved block is never stale', () {
      for (final status in [
        SessionStatus.completed,
        SessionStatus.partial,
        SessionStatus.skipped,
        SessionStatus.rescheduled,
      ]) {
        expect(
          sweep.isStale(session(start: u(19, 9), status: status), u(19, 20)),
          isFalse,
          reason: '${status.name} should not be swept',
        );
      }
    });

    test('a block that has not come due yet is not stale', () {
      expect(sweep.isStale(session(start: u(19, 14)), u(19, 11)), isFalse);
    });
  });

  group('run', () {
    test('does nothing when nothing is stale', () {
      final outcomes = sweep.run(
        candidates: [SweepCandidate(session: session(start: u(19, 14)))],
        slots: [slot(u(19, 12), u(19, 18))],
        clock: clock,
      );
      expect(outcomes, isEmpty);
    });

    test('moves an abandoned block into the next slot that fits', () {
      final outcomes = sweep.run(
        candidates: [SweepCandidate(session: session(start: u(19, 9)))],
        slots: [slot(u(19, 12), u(19, 18))],
        clock: clock,
      );

      expect(outcomes, hasLength(1));
      final outcome = outcomes.single;
      expect(outcome.wasMoved, isTrue);
      expect(outcome.replacement!.plannedStart, u(19, 12));
      expect(outcome.replacement!.plannedMinutes, 45);
    });

    test('the original is closed as rescheduled, not left planned', () {
      final outcome = sweep
          .run(
            candidates: [SweepCandidate(session: session(start: u(19, 9)))],
            slots: [slot(u(19, 12), u(19, 18))],
            clock: clock,
          )
          .single;

      expect(outcome.stale.status, SessionStatus.rescheduled);
      expect(outcome.stale.isResolved, isTrue);
    });

    test('the replacement carries the move count and its parent', () {
      final outcome = sweep
          .run(
            candidates: [
              SweepCandidate(session: session(start: u(19, 9), moves: 1)),
            ],
            slots: [slot(u(19, 12), u(19, 18))],
            clock: clock,
          )
          .single;

      expect(outcome.replacement!.rescheduleCount, 2);
      expect(outcome.replacement!.parentSessionId, 's1');
    });

    test('honours the deadline and skips work that can no longer land', () {
      final outcome = sweep
          .run(
            candidates: [
              SweepCandidate(
                session: session(start: u(19, 9)),
                deadline: u(19, 11, 30),
              ),
            ],
            slots: [slot(u(19, 12), u(19, 18))],
            clock: clock,
          )
          .single;

      expect(outcome.wasMoved, isFalse);
      expect(outcome.skipReason, SweepSkipReason.pastDeadline);
      expect(outcome.stale.status, SessionStatus.skipped);
    });

    test('skips when no slot is left big enough', () {
      final outcome = sweep
          .run(
            candidates: [SweepCandidate(session: session(start: u(19, 9)))],
            slots: [slot(u(19, 12), u(19, 12, 20))],
            clock: clock,
          )
          .single;

      expect(outcome.skipReason, SweepSkipReason.noSlotAvailable);
      expect(outcome.stale.status, SessionStatus.skipped);
    });

    test('gives up on work that has already been moved too often', () {
      final outcome = sweep
          .run(
            candidates: [
              SweepCandidate(session: session(start: u(19, 9), moves: 5)),
            ],
            slots: [slot(u(19, 12), u(19, 18))],
            clock: clock,
          )
          .single;

      expect(outcome.skipReason, SweepSkipReason.tooManyMoves);
      expect(outcome.stale.status, SessionStatus.skipped);
    });

    test('the move cap is the last chance, not one move early', () {
      final outcome = sweep
          .run(
            candidates: [
              SweepCandidate(session: session(start: u(19, 9), moves: 4)),
            ],
            slots: [slot(u(19, 12), u(19, 18))],
            clock: clock,
          )
          .single;

      expect(outcome.wasMoved, isTrue);
      expect(outcome.replacement!.rescheduleCount, 5);
    });

    test('two abandoned blocks never land on the same half hour', () {
      final outcomes = sweep.run(
        candidates: [
          SweepCandidate(session: session(start: u(19, 9))),
          SweepCandidate(
            session: session(id: 's2', taskId: 't2', start: u(19, 9, 30)),
          ),
        ],
        slots: [slot(u(19, 12), u(19, 18))],
        clock: clock,
      );

      expect(outcomes, hasLength(2));
      final a = outcomes[0].replacement!;
      final b = outcomes[1].replacement!;
      expect(
        a.plannedEnd.isAfter(b.plannedStart) &&
            b.plannedEnd.isAfter(a.plannedStart),
        isFalse,
        reason: 'replacements overlap: $a and $b',
      );
    });

    test('scarce time goes to the work that has waited longest', () {
      // One 50-minute hole left, and two 45-minute blocks want it.
      final outcomes = sweep.run(
        candidates: [
          SweepCandidate(
            session: session(id: 'later', start: u(19, 9, 30)),
          ),
          SweepCandidate(
            session: session(id: 'earlier', start: u(19, 8)),
          ),
        ],
        slots: [slot(u(19, 12), u(19, 12, 50))],
        clock: clock,
      );

      final moved = outcomes.where((o) => o.wasMoved).toList();
      expect(moved, hasLength(1));
      expect(moved.single.replacement!.parentSessionId, 'earlier');
    });

    test('a long free stretch is split, not consumed, by the first block', () {
      final outcomes = sweep.run(
        candidates: [
          SweepCandidate(session: session(start: u(19, 9))),
          SweepCandidate(
            session: session(id: 's2', taskId: 't2', start: u(19, 9, 30)),
          ),
        ],
        slots: [slot(u(19, 12), u(19, 14))],
        clock: clock,
      );

      expect(outcomes.every((o) => o.wasMoved), isTrue);
      expect(outcomes[0].replacement!.plannedStart, u(19, 12));
      expect(outcomes[1].replacement!.plannedStart, u(19, 12, 45));
    });

    test('is deterministic: the same input sweeps the same way twice', () {
      List<String> ids() => sweep
          .run(
            candidates: [
              SweepCandidate(session: session(start: u(19, 9))),
              SweepCandidate(
                session: session(id: 's2', taskId: 't2', start: u(19, 9, 30)),
              ),
            ],
            slots: [slot(u(19, 12), u(19, 18))],
            clock: FakeClock(u(19, 11)),
          )
          .map((o) => '${o.stale.id}->${o.replacement?.plannedStart}')
          .toList();

      expect(ids(), ids());
    });
  });
}
