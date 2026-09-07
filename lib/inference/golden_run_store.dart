import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:van/inference/goldens.dart';

/// Keeps a golden run on disk so it survives the app being killed.
///
/// **A run on the phone takes about eighty minutes.** One `extract_task` case
/// costs two and three quarter minutes against the on-device model, there are
/// twenty-nine of them, and in eighty minutes the screen will lock, Android
/// will decide the app is a good candidate for memory, or somebody will pick
/// the phone up. Holding the results only in a widget's state means every one
/// of those throws away the whole measurement, and the measurement is the
/// point.
///
/// So each case is written the moment it finishes. The file is the record;
/// nothing is held anywhere else.
///
/// The prompt hash is stored beside the outcomes and checked on resume. A run
/// half-measured against one prompt and half against another is not a
/// measurement of either, and prompts are versioned assets that do change.
abstract interface class GoldenRunStore {
  /// Reads a run that was in progress, or null if there is nothing usable.
  Future<GoldenRun?> read(String capability);

  /// Writes [run], replacing whatever was there.
  Future<void> write(GoldenRun run);

  /// Throws the saved run away, for starting over.
  Future<void> clear(String capability);
}

/// A [GoldenRunStore] backed by one JSON file per capability.
///
/// The only implementation that matters on a phone. It is separated from the
/// interface so the screen depends on "somewhere to save progress" rather than
/// on a filesystem: a widget test that does real file I/O inside
/// `pumpAndSettle` deadlocks, and a screen that cannot be tested without a
/// disk is a screen whose logic goes untested.
class FileGoldenRunStore implements GoldenRunStore {
  /// Creates a store writing under [directory].
  const FileGoldenRunStore(this.directory);

  /// Where the file lives. The app's own documents directory in practice.
  final String directory;

  /// The one file. Named for the capability so a second set gets its own.
  File _file(String capability) =>
      File(p.join(directory, 'golden-run-$capability.json'));

  /// Reads a run that was in progress, or null if there is nothing usable.
  ///
  /// Returns null rather than throwing on a file that cannot be read: a
  /// corrupt half-write must cost the run, not the screen.
  @override
  Future<GoldenRun?> read(String capability) async {
    final file = _file(capability);
    if (!file.existsSync()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return GoldenRun(
        capability: json['capability'] as String,
        promptFingerprint: json['promptFingerprint'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        outcomes: [
          for (final raw in json['outcomes'] as List<dynamic>)
            GoldenOutcome.fromJson(raw as Map<String, dynamic>),
        ],
      );
    } on Object {
      return null;
    }
  }

  /// Writes [run], replacing whatever was there.
  @override
  Future<void> write(GoldenRun run) async {
    final file = _file(run.capability);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'capability': run.capability,
        'promptFingerprint': run.promptFingerprint,
        'startedAt': run.startedAt.toIso8601String(),
        'outcomes': [for (final o in run.outcomes) o.toJson()],
      }),
    );
  }

  /// Throws the saved run away, for starting over.
  @override
  Future<void> clear(String capability) async {
    final file = _file(capability);
    if (file.existsSync()) await file.delete();
  }
}

/// A golden run, finished or part-way through.
class GoldenRun {
  /// Creates a run.
  const GoldenRun({
    required this.capability,
    required this.promptFingerprint,
    required this.startedAt,
    required this.outcomes,
  });

  /// Which capability is being measured.
  final String capability;

  /// Identifies the prompt these cases were asked with.
  ///
  /// Cheap and sufficient: it only has to notice that the asset changed, and
  /// this is compared against itself rather than published anywhere.
  final String promptFingerprint;

  /// When the first case ran.
  final DateTime startedAt;

  /// Every case finished so far, in the order they were run.
  final List<GoldenOutcome> outcomes;

  /// Whether [prompt] is the one this run was measured against.
  bool matches(String prompt) => promptFingerprint == fingerprint(prompt);

  /// The fingerprint of a prompt.
  static String fingerprint(String prompt) =>
      '${prompt.length}:${prompt.hashCode}';
}
