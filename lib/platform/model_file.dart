import 'package:flutter/services.dart';

/// Whether the on-device model's weights are installed, and where.
class ModelFileStatus {
  /// Creates a status.
  const ModelFileStatus({
    required this.present,
    required this.path,
    required this.bytes,
    required this.expectedName,
    this.pendingDownload = false,
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

  /// Whether a finished download is sitting there waiting to be moved into
  /// place.
  ///
  /// Read from the filesystem rather than from anything Van remembers, which
  /// is what makes it survive the app being closed - the bug this exists to
  /// fix was a completed 2.6 GB download that nothing ever claimed, because
  /// the only record of it was a variable in a page that had been disposed.
  final bool pendingDownload;

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
/// **Two routes in, and Van has no HTTP client on either.** The download hands
/// a URL to Android's `DownloadManager`, which fetches it in a system process;
/// the manual route takes a file the user already has. `AGENTS.md` forbids
/// adding a network dependency, which asking the OS to fetch something is not.
/// See `DECISIONS_PENDING.md` D79.
///
/// **A finished download is claimed from the filesystem, not from memory.**
/// [ModelFileStatus.pendingDownload] is read off disk every time, because the
/// first version tracked it in a variable on a page - so a download that
/// completed while that page was closed left 2.6 GB unclaimed and a screen
/// offering to fetch it all over again.
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
        pendingDownload: row['pending'] as bool? ?? false,
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
