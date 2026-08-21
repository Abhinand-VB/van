// Measures a backend against a capability's golden set.
//
// CI runs the same cases through the same runner against the deterministic
// parser (test/inference/goldens_test.dart). This exists for the other half:
// pointing them at a real model before anything is routed to it.
//
//   dart run tool/run_goldens.dart                    # the parser, as shipped
//   dart run tool/run_goldens.dart --verbose          # every case, not just fails
//   dart run tool/run_goldens.dart --set extract_task
//
// The gate is 80% and it is not a formality: below that a model is worse than
// the parser it would replace, and switching would be a downgrade dressed as
// progress. Exit code is 1 when the gate is missed, so this can be trusted in
// a script.
//
// There is deliberately no flag for the on-device backend. GemmaBackend needs
// a platform channel and a model file, so measuring it means running on a
// phone, not here - see STATUS section 3e.
import 'dart:io';

import 'package:van/inference/backends/mock_backend.dart';
import 'package:van/inference/goldens.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/inference/router.dart';

Future<void> main(List<String> args) async {
  final verbose = args.contains('--verbose') || args.contains('-v');
  final name = _valueOf(args, '--set') ?? 'extract_task';

  final file = File('test/golden/$name.json');
  if (!file.existsSync()) {
    stderr.writeln('no golden set at ${file.path}');
    exit(2);
  }

  final set = GoldenSet.fromJson(file.readAsStringSync());

  // No model here. Every call falls through to the capability's deterministic
  // fallback, which is exactly what ships today and therefore the number any
  // candidate has to beat.
  final report = await GoldenRunner(
    InferenceRouter(defaultBackend: MockBackend(available: false)),
    prompts: await Prompts.load(
      (path) async => File(path).readAsString(),
    ),
  ).run(set);

  stdout
    ..writeln('${set.cases.length} cases, resolved at ${set.now}')
    ..write(report.describe(verbose: verbose));

  if (!report.clearsGate) exit(1);
}

String? _valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
