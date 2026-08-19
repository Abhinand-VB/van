import 'package:van_core/van_core.dart';
import 'package:test/test.dart';

void main() {
  group('Ok', () {
    const ok = Ok<int, String>(42);

    test('reports isOk', () {
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
    });

    test('exposes the value and a null error', () {
      expect(ok.okOrNull, 42);
      expect(ok.errOrNull, isNull);
    });

    test('unwrapOr returns the value, not the fallback', () {
      expect(ok.unwrapOr(0), 42);
    });

    test('map transforms the value', () {
      expect(ok.map((v) => v * 2), const Ok<int, String>(84));
    });

    test('mapErr leaves it untouched', () {
      expect(ok.mapErr((e) => e.length), const Ok<int, int>(42));
    });

    test('fold takes the success branch', () {
      expect(ok.fold((v) => 'v$v', (e) => 'e$e'), 'v42');
    });

    test('compares by value', () {
      expect(ok, const Ok<int, String>(42));
      expect(ok, isNot(const Ok<int, String>(43)));
      expect(ok.hashCode, const Ok<int, String>(42).hashCode);
    });

    test('is distinguishable from Err in a switch', () {
      const Result<int, String> subject = ok;
      final label = switch (subject) {
        Ok<int, String>(:final value) => 'ok:$value',
        Err<int, String>(:final error) => 'err:$error',
      };
      expect(label, 'ok:42');
    });
  });

  group('Err', () {
    const err = Err<int, String>('no slot before deadline');

    test('reports isErr', () {
      expect(err.isErr, isTrue);
      expect(err.isOk, isFalse);
    });

    test('exposes the error and a null value', () {
      expect(err.errOrNull, 'no slot before deadline');
      expect(err.okOrNull, isNull);
    });

    test('unwrapOr returns the fallback', () {
      expect(err.unwrapOr(-1), -1);
    });

    test('map preserves the error and changes the value type', () {
      expect(
        err.map((v) => v.toString()),
        const Err<String, String>('no slot before deadline'),
      );
    });

    test('mapErr transforms the error', () {
      expect(err.mapErr((e) => e.length), const Err<int, int>(23));
    });

    test('fold takes the failure branch', () {
      expect(
        err.fold((v) => 'v$v', (e) => 'e:$e'),
        'e:no slot before deadline',
      );
    });

    test('compares by value', () {
      expect(err, const Err<int, String>('no slot before deadline'));
      expect(err, isNot(const Err<int, String>('something else')));
    });

    test('an Ok never equals an Err carrying the same payload', () {
      expect(
        const Ok<String, String>('x'),
        isNot(const Err<String, String>('x')),
      );
    });
  });
}
