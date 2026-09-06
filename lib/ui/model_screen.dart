import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/platform/model_file.dart';
import 'package:van/ui/background.dart';

/// Where the on-device model's weights are, and how to put them there.
///
/// **This is not a model picker, and `AGENTS.md` forbids one.** Which backend
/// answers which capability lives in `assets/inference_config.json` and stays
/// there; nothing on this page changes routing. It manages one file, and the
/// routing stays at `"none"` until somebody who has measured the model against
/// the golden set decides otherwise.
///
/// **It does download, and Van still has no HTTP client.** The button hands a
/// URL to Android's `DownloadManager`, a system service in its own process -
/// the same shape as handing a URI to a browser. An earlier version of this
/// page refused to download at all and told the user to go and find a 2.6 GB
/// file themselves, on the grounds that the weights were licence-gated. That
/// was two mistakes: the repository is Apache 2.0 and answers an anonymous
/// request, and "no network dependency" never meant "no button". See
/// `DECISIONS_PENDING.md` D79.
///
/// The manual route stays underneath, because a computer and a cable is often
/// the better way to move two and a half gigabytes.
class ModelScreen extends StatefulWidget {
  /// Creates the page.
  const ModelScreen({required this.modelFile, this.onTryIt, super.key});

  /// The weights on this device.
  final ModelFile modelFile;

  /// Opens the probe, when this build can reach the engine.
  ///
  /// Null on a platform with no channel to it, which is every test and every
  /// desktop build - so the button is simply absent there rather than
  /// present and broken.
  final VoidCallback? onTryIt;

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  ModelFileStatus? _status;
  DownloadProgress _download = DownloadProgress.idle;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    inBackground(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final status = await widget.modelFile.status();
    final download = await widget.modelFile.downloadProgress();
    if (!mounted) return;
    setState(() {
      _status = status;
      _download = download;
    });

    // A download that finished while this page was closed - or while Van was
    // not running at all - is claimed the moment anyone looks. Without this
    // the file sat in external storage for ever and the page cheerfully
    // offered to fetch it again, which is exactly what happened.
    if (status.pendingDownload && !status.present) {
      await _run(widget.modelFile.adoptDownload);
      return;
    }
    _watch();
  }

  /// Polls while something is in flight, and stops the moment it is not.
  ///
  /// A timer rather than a stream from the platform: `DownloadManager` will
  /// tell Van when it finished and nothing in between, and a bar that moves
  /// once at the end is worse than none at all on a file this size.
  void _watch() {
    final live =
        _download.state == DownloadState.running ||
        _download.state == DownloadState.paused;
    if (!live) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      final progress = await widget.modelFile.downloadProgress();
      if (!mounted) return;
      setState(() => _download = progress);
      // A finished download is not an installed model until it has been moved
      // to where the engine looks, and doing that without being asked is the
      // whole point - the user pressed one button and expects one outcome.
      if (progress.state == DownloadState.done) {
        _poll?.cancel();
        _poll = null;
        await _run(widget.modelFile.adoptDownload);
      } else if (progress.state != DownloadState.running &&
          progress.state != DownloadState.paused) {
        _poll?.cancel();
        _poll = null;
      }
    });
  }

  Future<void> _startDownload() async {
    final progress = await widget.modelFile.startDownload();
    if (!mounted) return;
    setState(() => _download = progress);
    _watch();
  }

  Future<void> _cancelDownload() async {
    final progress = await widget.modelFile.cancelDownload();
    if (!mounted) return;
    setState(() => _download = progress);
    _watch();
  }

  Future<void> _run(Future<ModelFileStatus> Function() action) async {
    setState(() => _busy = true);
    final status = await action();
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  Future<void> _confirmRemove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the model file?'),
        content: const Text(
          'Van goes back to its deterministic behaviour, which is what it '
          'does today. You would have to download the file again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes ?? false) await _run(widget.modelFile.remove);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: const Text('On-device model')),
      body: status == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _Card(
                  present: status.present,
                  size: status.size,
                  expectedName: status.expectedName,
                ),
                const SizedBox(height: 20),
                Text(
                  status.present
                      ? 'The weights are installed. Van is still using its '
                            'deterministic behaviour: nothing is routed to the '
                            'model until it has been measured against the '
                            'golden set and beaten it.'
                      : 'Van works fully without this. Every AI capability has '
                            'a deterministic fallback, and that is what is '
                            'running today — a working configuration, not a '
                            'degraded one.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (status.present && widget.onTryIt != null) ...[
                  const SizedBox(height: 16),
                  // The only way to find out whether any of this was worth
                  // it. Nothing is routed to the model, so without a way to
                  // ask it a question by hand there is no evidence on which
                  // to route anything - see issue 14.
                  OutlinedButton.icon(
                    onPressed: widget.onTryIt,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Try the model'),
                  ),
                ],
                const SizedBox(height: 24),
                // One button, because "go and find a 2.6 GB file" is not an
                // instruction anybody follows. The rule was never the
                // problem - the missing button was.
                _Download(
                  progress: _download,
                  present: status.present,
                  busy: _busy,
                  onStart: () => inBackground(_startDownload()),
                  onCancel: () => inBackground(_cancelDownload()),
                ),
                const SizedBox(height: 28),
                Text('Or do it yourself', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  // Kept, because a 2.6 GB download over a phone connection is
                  // not always the best route: a computer and a cable often
                  // is, and a phone that already has the file should not be
                  // made to fetch it twice.
                  'Fetch it on a computer, copy it across, and point Van at '
                  'it. Van copies whatever you pick into its own storage '
                  'under its own name, so the download can be called '
                  'anything.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => inBackground(
                                widget.modelFile.openSourcePage(),
                              ),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Model page'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () =>
                                  inBackground(_run(widget.modelFile.install)),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(
                          status.present ? 'Replace' : 'Choose a file',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SelectableText(
                  ModelSource.url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (status.present) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => inBackground(_confirmRemove()),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove it'),
                  ),
                ],
                if (status.path.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('It goes here', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  SelectableText(
                    status.path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The one-button route: Android fetches it, Van puts it away.
class _Download extends StatelessWidget {
  const _Download({
    required this.progress,
    required this.present,
    required this.busy,
    required this.onStart,
    required this.onCancel,
  });

  final DownloadProgress progress;
  final bool present;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;

    if (progress.state == DownloadState.running ||
        progress.state == DownloadState.paused) {
      final waiting = progress.state == DownloadState.paused;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            waiting ? 'Waiting for Wi-Fi' : 'Downloading',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            waiting
                // Said plainly, because a download that appears stuck is
                // indistinguishable from a broken one, and this is deliberate.
                ? 'It is ${ModelSource.description}, so Van will not spend '
                      'your mobile data on it. Connect to Wi-Fi and it '
                      'continues by itself.'
                : '${progress.readable}  ·  carries on if you leave the app',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colours.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress.fraction),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          present ? 'Download it again' : 'Download it',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${ModelSource.description}, fetched once and then it works '
          'offline forever. Android does the downloading, so it survives '
          'you closing Van and resumes on its own.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colours.onSurfaceVariant,
          ),
        ),
        if (progress.state == DownloadState.failed) ...[
          const SizedBox(height: 8),
          Text(
            'That download stopped. Trying again usually works; if it does '
            'not, fetch it on a computer instead.',
            style: theme.textTheme.bodySmall?.copyWith(color: colours.error),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onStart,
            icon: const Icon(Icons.download),
            label: Text(
              present ? 'Download again' : 'Download the model',
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.present,
    required this.size,
    required this.expectedName,
  });

  final bool present;
  final String size;
  final String expectedName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: present
            ? colours.primaryContainer
            : colours.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            present ? Icons.memory : Icons.memory_outlined,
            color: present ? colours.onPrimaryContainer : colours.outline,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  present ? 'Installed  ·  $size' : 'Not installed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: present ? colours.onPrimaryContainer : null,
                  ),
                ),
                if (expectedName.isNotEmpty)
                  Text(
                    expectedName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: present
                          ? colours.onPrimaryContainer
                          : colours.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
