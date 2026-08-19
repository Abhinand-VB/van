import 'package:nova_core/nova_core.dart';
import 'package:test/test.dart';

void main() {
  group('FakeClock', () {
    test('parks at the instant it was given, normalised to UTC', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19, 14, 30));
      expect(clock.now(), DateTime.utc(2026, 8, 19, 14, 30));
      expect(clock.now().isUtc, isTrue);
    });

    test('coerces a local start time to UTC', () {
      final local = DateTime(2026, 8, 19, 14, 30);
      final clock = FakeClock(local);
      expect(clock.now().isUtc, isTrue);
      expect(clock.now(), local.toUtc());
    });

    test('advance moves forward by exactly the duration', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19, 14, 30));
      clock.advance(const Duration(minutes: 25));
      expect(clock.now(), DateTime.utc(2026, 8, 19, 14, 55));
    });

    test('advance accumulates across calls', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19));
      clock
        ..advance(const Duration(hours: 6))
        ..advance(const Duration(minutes: 30));
      expect(clock.now(), DateTime.utc(2026, 8, 19, 6, 30));
    });

    test('advance rejects a negative duration', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19));
      expect(
        () => clock.advance(const Duration(minutes: -1)),
        throwsArgumentError,
      );
    });

    test('advance accepts zero', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19));
      clock.advance(Duration.zero);
      expect(clock.now(), DateTime.utc(2026, 8, 19));
    });

    test('advanceTo jumps to the target instant', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19, 9));
      clock.advanceTo(DateTime.utc(2026, 8, 21, 18, 45));
      expect(clock.now(), DateTime.utc(2026, 8, 21, 18, 45));
    });

    test('advanceTo rejects a target in the past', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19, 9));
      expect(
        () => clock.advanceTo(DateTime.utc(2026, 8, 19, 8)),
        throwsArgumentError,
      );
    });

    test('advanceTo rejects the current instant', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19, 9));
      expect(
        () => clock.advanceTo(DateTime.utc(2026, 8, 19, 9)),
        throwsArgumentError,
      );
    });

    test('advanceTo normalises a local target to UTC', () {
      final clock = FakeClock(DateTime.utc(2020));
      final localTarget = DateTime(2026, 8, 19, 14, 30);
      clock.advanceTo(localTarget);
      expect(clock.now(), localTarget.toUtc());
      expect(clock.now().isUtc, isTrue);
    });

    test('survives a simulated week without drift', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 19));
      for (var i = 0; i < 7 * 24 * 60; i++) {
        clock.advance(const Duration(minutes: 1));
      }
      expect(clock.now(), DateTime.utc(2026, 8, 26));
    });
  });
}
