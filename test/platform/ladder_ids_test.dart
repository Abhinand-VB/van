import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/platform/notifications.dart';

void main() {
  group('LadderIds', () {
    test('a rung has the same id every time it is asked for', () {
      // The property everything else rests on: nothing is remembered, so the
      // id must be recomputable from the session id alone.
      expect(LadderIds.forRung('s1', 0), LadderIds.forRung('s1', 0));
      expect(LadderIds.forRung('s1', 2), LadderIds.forRung('s1', 2));
    });

    test('rungs of one session do not collide with each other', () {
      final ids = LadderIds.forSession('s1');
      expect(ids.toSet(), hasLength(LadderIds.perSession));
    });

    test('different sessions get different blocks', () {
      final a = LadderIds.forSession('session-one').toSet();
      final b = LadderIds.forSession('session-two').toSet();
      expect(a.intersection(b), isEmpty);
    });

    test('the block covers every rung the ladder could arm', () {
      // cancelForSession cancels the whole block, so a rung outside it would
      // survive a cancel. Three rungs today, room for eight.
      expect(LadderIds.perSession, greaterThanOrEqualTo(3));
      expect(LadderIds.forSession('s1'), hasLength(LadderIds.perSession));
      for (var rung = 0; rung < LadderIds.perSession; rung++) {
        expect(
          LadderIds.forSession('s1'),
          contains(LadderIds.forRung('s1', rung)),
        );
      }
    });

    test('the service arms ids the canceller will look for', () {
      // These were two separate formulas once. If they ever diverge again,
      // every cancel becomes a silent no-op.
      for (var rung = 0; rung < 3; rung++) {
        expect(
          VanService.notificationId('s1', rung),
          LadderIds.forRung('s1', rung),
        );
        expect(
          LadderIds.forSession('s1'),
          contains(VanService.notificationId('s1', rung)),
        );
      }
    });

    test('the derivation is pinned, because Android remembers it', () {
      // These numbers are the contract, not an implementation detail. A rung
      // armed by one build gets cancelled by another - a later process, days
      // later, possibly a different app version - and the only thing joining
      // the two is that this function still returns what it returned before.
      //
      // The failure mode if it ever changes is silent: cancelling an id that
      // was never scheduled is a no-op, so Van reports success and the old
      // notification fires anyway, forever uncancellable.
      //
      // So this test failing is a decision to make, not a number to update.
      expect(LadderIds.forRung('s1', 0), 1116587592);
      expect(LadderIds.forRung('s1', 2), 1116587594);
      expect(LadderIds.forRung('session-one', 0), 620284464);
      expect(LadderIds.forRung('a-fairly-long-session-id-1234', 0), 1379946200);
    });

    test('five thousand sessions collide with none of the others', () {
      // Not a hypothetical. Two live sessions sharing a block means cancelling
      // one silently cancels the other's whole ladder, and the id space is the
      // only thing preventing it. The previous derivation kept 22 bits, and
      // produces 2 real collisions on exactly this sample - measured, not
      // predicted, before it was replaced.
      //
      // Deterministic: fixed inputs, fixed hash. It either holds or it does
      // not, the same way every run.
      final seen = <int>{};
      for (var i = 0; i < 5000; i++) {
        expect(
          seen.add(LadderIds.forRung('session-$i', 0)),
          isTrue,
          reason: 'session-$i landed on a block already taken',
        );
      }
    });

    test('every id in the space fits, not just the ones sampled', () {
      // The mask is derived from perSession rather than written down, so the
      // largest id the derivation can possibly produce is the one to check.
      const mask = 0x7FFFFFFF ~/ LadderIds.perSession;
      const largest = mask * LadderIds.perSession + LadderIds.perSession - 1;
      expect(largest, lessThan(1 << 31));
      expect(largest, greaterThan(1 << 30), reason: 'the space is not wasted');
    });

    test('ids stay inside the 32-bit range Android accepts', () {
      for (final id in LadderIds.forSession('a-fairly-long-session-id-1234')) {
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(1 << 31));
      }
    });
  });
}
