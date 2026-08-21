import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:van/inference/backends/mock_backend.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/config.dart';
import 'package:van/inference/router.dart';

void main() {
  final none = MockBackend(id: 'none');
  final gemma = MockBackend(id: 'gemma_e2b');
  final cloud = MockBackend(id: 'cloud');

  InferenceConfig parse(String source) => InferenceConfig.fromJson(source);

  group('the shipped asset', () {
    late InferenceConfig shipped;

    setUp(() {
      shipped = parse(File('assets/inference_config.json').readAsStringSync());
    });

    test('is actually read, rather than being decoration', () {
      // It was decoration until now: the file existed, four comments claimed
      // routing lived in it, and no code ever opened it.
      expect(shipped.routes, isNotEmpty);
      expect(shipped.defaultBackend, isNotEmpty);
    });

    test('routes every capability Van has', () {
      expect(
        shipped.routes.keys,
        containsAll(<String>['extract_task', 'compose_nudge', 'negotiate']),
      );
    });

    test('names only backends it also declares', () {
      for (final entry in shipped.routes.entries) {
        expect(
          shipped.backendTypes.keys,
          contains(entry.value),
          reason: '"${entry.key}" routes to an undeclared backend',
        );
      }
    });

    test('resolves cleanly against what main.dart can build', () {
      final warnings = <ConfigWarning>[];
      shipped.router(
        available: {'none': none, 'gemma_e2b': gemma},
        fallbackBackend: const NullBackend(),
        warnings: warnings,
      );
      expect(warnings, isEmpty, reason: warnings.join('\n'));
    });

    test('still ships with no model, which is a working configuration', () {
      final router = shipped.router(
        available: {'none': none, 'gemma_e2b': gemma},
        fallbackBackend: const NullBackend(),
      );
      for (final capability in shipped.routes.keys) {
        expect(router.backendFor(capability).id, 'none');
      }
    });
  });

  group('routing', () {
    test('sends a capability to the backend it names', () {
      final router =
          parse('''
        {
          "default_backend": "none",
          "backends": {"none": {"type": "null"}, "cloud": {"type": "http"}},
          "routes": {"extract_task": "cloud", "compose_nudge": "none"}
        }
      ''').router(
            available: {'none': none, 'cloud': cloud},
            fallbackBackend: const NullBackend(),
          );

      expect(router.backendFor('extract_task').id, 'cloud');
      expect(router.backendFor('compose_nudge').id, 'none');
    });

    test('an unrouted capability gets the default', () {
      final router =
          parse('''
        {
          "default_backend": "cloud",
          "backends": {"cloud": {"type": "http"}},
          "routes": {}
        }
      ''').router(
            available: {'cloud': cloud},
            fallbackBackend: const NullBackend(),
          );

      expect(router.backendFor('anything').id, 'cloud');
    });
  });

  group('a config with mistakes in it', () {
    test('a route to a backend with no instance warns and falls back', () {
      // The realistic mistake: config switched to a provider before the code
      // that builds it exists. Van must still start.
      final warnings = <ConfigWarning>[];
      final router =
          parse('''
        {
          "default_backend": "none",
          "backends": {"none": {"type": "null"}, "cloud": {"type": "http"}},
          "routes": {"extract_task": "cloud"}
        }
      ''').router(
            available: {'none': none},
            fallbackBackend: const NullBackend(),
            warnings: warnings,
          );

      expect(router.backendFor('extract_task').id, 'none');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('extract_task'));
      expect(warnings.single.message, contains('cloud'));
    });

    test('a route to an undeclared backend warns', () {
      final warnings = <ConfigWarning>[];
      parse('''
        {
          "default_backend": "none",
          "backends": {"none": {"type": "null"}},
          "routes": {"extract_task": "typo"}
        }
      ''').router(
        available: {'none': none},
        fallbackBackend: const NullBackend(),
        warnings: warnings,
      );

      expect(warnings.map((w) => w.message).join(), contains('not declared'));
    });

    test('a default with no instance still yields a usable router', () {
      final warnings = <ConfigWarning>[];
      final router =
          parse('''
        {
          "default_backend": "missing",
          "backends": {},
          "routes": {}
        }
      ''').router(
            available: {},
            fallbackBackend: const NullBackend(),
            warnings: warnings,
          );

      expect(router.backendFor('anything'), isA<NullBackend>());
      expect(warnings, isNotEmpty);
    });

    test('missing sections do not throw', () {
      final config = parse('{}');
      expect(config.defaultBackend, 'none');
      expect(config.routes, isEmpty);
      expect(config.backendTypes, isEmpty);
    });

    test('a non-string route is ignored rather than crashing', () {
      final config = parse('''
        {"routes": {"extract_task": 7, "compose_nudge": "none"}}
      ''');
      expect(config.routes.keys, ['compose_nudge']);
    });
  });

  group('the observer survives routing', () {
    test('reaches the router it builds', () async {
      // Losing it here would silently stop every inference outcome reaching
      // the event log, which is the only record of whether the model helps.
      final seen = <String>[];
      final router =
          parse('''
        {"default_backend": "none", "backends": {"none": {"type": "null"}}}
      ''').router(
            available: {'none': MockBackend(id: 'none', available: false)},
            fallbackBackend: const NullBackend(),
            observer: _RecordingObserver(seen),
          );

      await router.run(
        const ExtractTask(),
        ExtractTaskInput('call the bank', now: DateTime.utc(2026, 8, 19, 9)),
      );

      expect(seen, ['extract_task/none/fallback']);
    });
  });
}

class _RecordingObserver implements InferenceObserver {
  _RecordingObserver(this.seen);

  final List<String> seen;

  @override
  void onInference({
    required String capabilityId,
    required String backendId,
    required InferenceOutcome outcome,
    String? failureReason,
    int? latencyMs,
  }) => seen.add('$capabilityId/$backendId/${outcome.name}');
}
