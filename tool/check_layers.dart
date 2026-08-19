// Architectural fitness function for Van.
//
// The rules in docs/ARCHITECTURE.md are only real if something enforces them.
// This script is that something. It runs in CI ahead of the tests, because a
// layering violation is cheaper to fix in the commit that introduced it than
// six months later when the iOS port or a cloud backend needs the boundary.
//
// Run: dart run tool/check_layers.dart
import 'dart:io';

void main(List<String> args) {
  final violations = <Violation>[
    ...checkCorePurity(),
    ...checkAmbientTime(),
    ...checkProviderLeakage(),
  ];

  if (violations.isEmpty) {
    stdout.writeln('check_layers: OK - all architectural rules hold.');
    exit(0);
  }

  stderr.writeln('check_layers: ${violations.length} violation(s)\n');
  for (final v in violations) {
    stderr
      ..writeln('  ${v.file}:${v.line}')
      ..writeln('    rule: ${v.rule}')
      ..writeln('    ${v.detail}')
      ..writeln('    > ${v.source.trim()}\n');
  }
  exit(1);
}

/// Rule A: the domain core imports nothing that ties it to a platform.
///
/// van_core is a separate package precisely so most of this is impossible,
/// but a dependency could be added to its pubspec by accident. This catches it.
Iterable<Violation> checkCorePurity() sync* {
  const allowedPrefixes = <String>[
    'dart:core',
    'dart:math',
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:typed_data',
    'package:meta/',
    'package:collection/',
    'package:van_core/',
  ];

  for (final file in dartFilesUnder('packages/van_core/lib')) {
    final lines = stripComments(file.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      final match = _importPattern.firstMatch(lines[i]);
      if (match == null) continue;
      final uri = match.group(1)!;
      // No scheme means a relative path, which stays inside the package.
      if (!uri.contains(':')) continue;
      if (allowedPrefixes.any(uri.startsWith)) continue;
      yield Violation(
        file: relative(file.path),
        line: i + 1,
        rule: 'A - core purity (ARCHITECTURE.md P1)',
        detail:
            'van_core must not depend on "$uri". The core has to stay '
            'runnable under plain `dart test` and liftable to a server.',
        source: lines[i],
      );
    }
  }
}

/// Rule B: ambient time is banned outside the one place that owns it.
///
/// This is the rule that makes a time-driven app testable, and the one most
/// likely to be broken by a well-meaning "just for logging" call.
Iterable<Violation> checkAmbientTime() sync* {
  const allowed = <String>[
    'lib/platform/system_clock.dart',
    'lib/main.dart',
  ];

  for (final file in [
    ...dartFilesUnder('lib'),
    ...dartFilesUnder('packages/van_core/lib'),
  ]) {
    final path = relative(file.path);
    if (allowed.contains(path)) continue;
    if (path.endsWith('.g.dart')) continue;

    final lines = stripComments(file.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!_ambientTimePattern.hasMatch(lines[i])) continue;
      yield Violation(
        file: path,
        line: i + 1,
        rule: 'B - no ambient time (ARCHITECTURE.md P2)',
        detail:
            'Take a Clock in the constructor instead. Only '
            '${allowed.join(" and ")} may read the wall clock.',
        source: lines[i],
      );
    }
  }
}

/// Rule C: no provider names leak into the domain or the UI.
///
/// If "claude" or "gemma" appears in core or ui, swapping providers has stopped
/// being a config change and the abstraction in ARCHITECTURE.md section 5 has
/// failed. Fail loudly rather than discover it during the phase 3 port.
Iterable<Violation> checkProviderLeakage() sync* {
  const banned = <String>[
    'gemma',
    'claude',
    'anthropic',
    'openai',
    'gemini',
    'litert',
    'mediapipe',
  ];

  for (final file in [
    ...dartFilesUnder('packages/van_core/lib'),
    ...dartFilesUnder('lib/ui'),
  ]) {
    final path = relative(file.path);
    if (path.endsWith('.g.dart')) continue;

    final lines = stripComments(file.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      for (final name in banned) {
        if (!lower.contains(name)) continue;
        yield Violation(
          file: path,
          line: i + 1,
          rule: 'C - no provider names in core or ui (ARCHITECTURE.md 5.3)',
          detail:
              'Found "$name". Talk to InferenceRouter and Capability '
              'instead; routing belongs in assets/inference_config.json.',
          source: lines[i],
        );
        break;
      }
    }
  }
}

final _importPattern = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');
final _ambientTimePattern = RegExp(r'DateTime\s*\.\s*now\s*\(');

/// Removes line and block comments so that documentation discussing a rule is
/// not itself reported as breaking it.
String stripComments(String source) {
  final out = StringBuffer();
  var inBlock = false;
  for (final line in source.split('\n')) {
    final buf = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      if (inBlock) {
        if (i + 1 < line.length && line[i] == '*' && line[i + 1] == '/') {
          inBlock = false;
          i++;
        }
        continue;
      }
      if (i + 1 < line.length && line[i] == '/' && line[i + 1] == '/') break;
      if (i + 1 < line.length && line[i] == '/' && line[i + 1] == '*') {
        inBlock = true;
        i++;
        continue;
      }
      buf.write(line[i]);
    }
    out.writeln(buf);
  }
  return out.toString();
}

Iterable<File> dartFilesUnder(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) return const <File>[];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
}

String relative(String path) =>
    path.replaceAll(r'\', '/').replaceFirst(RegExp('^.*?/Van/'), '');

class Violation {
  Violation({
    required this.file,
    required this.line,
    required this.rule,
    required this.detail,
    required this.source,
  });

  final String file;
  final int line;
  final String rule;
  final String detail;
  final String source;
}
