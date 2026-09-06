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

/// Where the weights come from, and what to look for when you get there.
///
/// One place, so the page, the docs and anything later that needs to name the
/// model cannot drift apart. Verified to resolve on 6 September 2026; if the
/// vendor moves it, this constant is the only thing to change.
abstract final class ModelSource {
  /// The page the file lives on, for anyone who wants to look before they
  /// fetch two and a half gigabytes.
  static const url =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm';

  /// The file itself.
  ///
  /// **Not licence-gated.** An earlier version of this screen said it was,
  /// which was wrong: `litert-community` republishes these weights under
  /// Apache 2.0 and the repository answers an anonymous request. There is
  /// nothing to accept and nobody to sign in as, which is what makes a
  /// one-tap download honest here.
  static const fileUrl =
      '$url/resolve/main/gemma-4-E2B-it.litertlm?download=true';

  /// What is being fetched, for a person deciding whether to.
  static const description = 'Gemma 4 E2B, about 2.6 GB';
}

/// How a download is getting on.
enum DownloadState {
  /// Nothing is downloading.
  idle,

  /// In progress.
  running,

  /// Waiting for Wi-Fi. The expected state on mobile data, not a fault.
  paused,

  /// The bytes are on the phone and want moving into place.
  done,

  /// It stopped and will not resume on its own.
  failed,
}

/// A download in flight.
class DownloadProgress {
  /// Creates a progress report.
  const DownloadProgress({
    required this.state,
    this.bytes = 0,
    this.total = 0,
  });

  /// Nothing is happening.
  static const idle = DownloadProgress(state: DownloadState.idle);

  /// What it is doing.
  final DownloadState state;

  /// Bytes fetched so far.
  final int bytes;

  /// Bytes expected, or zero before the server has said.
  final int total;

  /// Fraction complete, or null while the size is unknown - which is the
  /// difference between a progress bar and a spinner, and they should not be
  /// made to look the same.
  double? get fraction => total <= 0 ? null : (bytes / total).clamp(0.0, 1.0);

  /// How far along, for a person to read.
  String get readable => total <= 0
      ? '${(bytes / (1 << 20)).round()} MB'
      : '${(bytes / (1 << 30)).toStringAsFixed(1)} of '
            '${(total / (1 << 30)).toStringAsFixed(1)} GB';
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

  /// Opens [ModelSource.url] in the phone's browser.
  ///
  /// **Van makes no request and gains no HTTP client.** A URI is handed to the
  /// OS and the browser does everything after that. Kept alongside the
  /// download for anyone who would rather look at the source first, or fetch
  /// it on a computer.
  Future<void> openSourcePage();

  /// Asks Android to fetch the weights.
  ///
  /// **Still no HTTP client in Van.** `DownloadManager` is a system service in
  /// its own process; this hands it a URL exactly as [openSourcePage] hands a
  /// browser one. It survives Van being closed, resumes by itself, and waits
  /// for Wi-Fi rather than spending two and a half gigabytes of someone's
  /// mobile data. See `DECISIONS_PENDING.md` D79.
  Future<DownloadProgress> startDownload();

  /// How the download is getting on. Polled; there is no push.
  Future<DownloadProgress> downloadProgress();

  /// Abandons a download in flight.
  Future<DownloadProgress> cancelDownload();

  /// Moves a finished download to where the engine looks.
  Future<ModelFileStatus> adoptDownload();
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

  @override
  Future<void> openSourcePage() async {
    try {
      await channel.invokeMethod<void>('openPage', {
        'url': ModelSource.url,
      });
    } on PlatformException catch (_) {
      // No browser, or the intent was refused. The page still shows the URL
      // as selectable text, so this is a lost convenience rather than a dead
      // end.
    } on MissingPluginException catch (_) {}
  }

  @override
  Future<DownloadProgress> startDownload() =>
      _progress('download', {'url': ModelSource.fileUrl});

  @override
  Future<DownloadProgress> downloadProgress() => _progress('downloadStatus');

  @override
  Future<DownloadProgress> cancelDownload() => _progress('cancelDownload');

  @override
  Future<ModelFileStatus> adoptDownload() => _call('adoptDownload');

  Future<DownloadProgress> _progress(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final row = await channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      if (row == null) return DownloadProgress.idle;
      return DownloadProgress(
        state: switch (row['state'] as String?) {
          'running' => DownloadState.running,
          'paused' => DownloadState.paused,
          'done' => DownloadState.done,
          'failed' => DownloadState.failed,
          _ => DownloadState.idle,
        },
        bytes: (row['bytes'] as num?)?.toInt() ?? 0,
        total: (row['total'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (_) {
      return const DownloadProgress(state: DownloadState.failed);
    } on MissingPluginException catch (_) {
      return DownloadProgress.idle;
    }
  }

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

  @override
  Future<void> openSourcePage() async {}

  @override
  Future<DownloadProgress> startDownload() async => DownloadProgress.idle;

  @override
  Future<DownloadProgress> downloadProgress() async => DownloadProgress.idle;

  @override
  Future<DownloadProgress> cancelDownload() async => DownloadProgress.idle;

  @override
  Future<ModelFileStatus> adoptDownload() async => ModelFileStatus.unknown;
}
