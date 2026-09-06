import 'package:flutter/services.dart';

/// Whether the on-device model's weights are installed, and where.
class ModelFileStatus {
  /// Creates a status.
  const ModelFileStatus({
    required this.present,
    required this.path,
    required this.bytes,
    required this.expectedName,
  });

  /// Nothing is known, because nothing can be asked.
  static const unknown = ModelFileStatus(
    present: false,
    path: '',
    bytes: 0,
    expectedName: '',
  );

  /// Whether a non-empty file is sitting where the engine expects one.
  final bool present;

  /// Where that is, whether or not anything is there yet.
  final String path;

  /// How big it is. Zero when absent.
  final int bytes;

  /// The file name the engine looks for.
  final String expectedName;

  /// Size in whole gigabytes and one decimal, for a person to read.
  String get size => bytes <= 0
      ? '—'
      : bytes >= 1 << 30
      ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
      : '${(bytes / (1 << 20)).round()} MB';
}

/// Installs and removes the on-device model's weights.
///
/// **This receives a file; it does not fetch one.** Two constraints decide
/// that between them, and they point the same way:
///
///  - `AGENTS.md` forbids a network dependency in v1 outright. There is no
///    HTTP client in the dependency set and adding one to download a model
///    would be the first thing in Van that talks to the internet.
///  - The weights are licence-gated. Whoever installs them has to accept that
///    licence, and that is the user - not the app, and certainly not an agent
///    working overnight.
///
/// So the honest surface is one that says where the file must go and takes it
/// when the user has it. See `DECISIONS_PENDING.md` D77.
///
/// **It does not choose a backend.** Routing lives in
/// `assets/inference_config.json` and stays there; `AGENTS.md` is explicit
/// that provider config is not a settings screen. This manages one file.
abstract interface class ModelFile {
  /// Whether the weights are installed, and where they are expected.
  Future<ModelFileStatus> status();

  /// Asks the user for a file and copies it into place.
  ///
  /// Returns the status afterwards, unchanged when they picked nothing.
  Future<ModelFileStatus> install();

  /// Deletes the installed weights.
  Future<ModelFileStatus> remove();
}

/// The Android implementation, over a method channel.
class MethodChannelModelFile implements ModelFile {
  /// Creates a client for the platform channel.
  const MethodChannelModelFile();

  /// The channel name, matching `ModelFilePlugin.CHANNEL` in Kotlin.
  static const channel = MethodChannel('dev.van.app/model_file');

  @override
  Future<ModelFileStatus> status() => _call('status');

  @override
  Future<ModelFileStatus> install() => _call('install');

  @override
  Future<ModelFileStatus> remove() => _call('remove');

  Future<ModelFileStatus> _call(String method) async {
    try {
      final row = await channel.invokeMapMethod<String, Object?>(method);
      if (row == null) return ModelFileStatus.unknown;
      return ModelFileStatus(
        present: row['present'] as bool? ?? false,
        path: row['path'] as String? ?? '',
        bytes: (row['bytes'] as num?)?.toInt() ?? 0,
        expectedName: row['expectedName'] as String? ?? '',
      );
    } on PlatformException catch (_) {
      // A failed copy or a file that could not be opened. The page shows the
      // status it already had rather than an error dialog over a screen whose
      // whole content is a status.
      return ModelFileStatus.unknown;
    } on MissingPluginException catch (_) {
      return ModelFileStatus.unknown;
    }
  }
}

/// A build with nowhere to put a model.
class UnsupportedModelFile implements ModelFile {
  /// Creates the empty implementation.
  const UnsupportedModelFile();

  @override
  Future<ModelFileStatus> status() async => ModelFileStatus.unknown;

  @override
  Future<ModelFileStatus> install() async => ModelFileStatus.unknown;

  @override
  Future<ModelFileStatus> remove() async => ModelFileStatus.unknown;
}
