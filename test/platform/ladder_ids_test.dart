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

    test('ids stay inside the 32-bit range Android accepts', () {
      for (final id in LadderIds.forSession('a-fairly-long-session-id-1234')) {
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(1 << 31));
      }
    });
  });
}
