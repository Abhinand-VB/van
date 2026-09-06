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
/// **Nor is it a downloader.** Van has no HTTP client and is not getting one
/// in v1, and the weights are licence-gated so whoever installs them must have
/// accepted that licence. Both point the same way: the page says where the
/// file must go and takes it when the user has it. See `DECISIONS_PENDING.md`
/// D77.
class ModelScreen extends StatefulWidget {
  /// Creates the page.
  const ModelScreen({required this.modelFile, super.key});

  /// The weights on this device.
  final ModelFile modelFile;

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  ModelFileStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    inBackground(_refresh());
  }

  Future<void> _refresh() async {
    final status = await widget.modelFile.status();
    if (!mounted) return;
    setState(() => _status = status);
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
                const SizedBox(height: 24),
                // Two steps, numbered, because "go and find a file" is not an
                // instruction anybody can follow. Van cannot do step one -
                // there is no HTTP client in it and the licence is not an
                // app's to accept - but it can take you to the exact page,
                // which is the difference between a rule and an obstacle.
                _Step(
                  number: 1,
                  title: 'Get the file',
                  body:
                      'Opens the model page in your browser. Accept the '
                      'licence there and download ${ModelSource.description}. '
                      'Van makes no network request of its own — your browser '
                      'does the downloading.',
                  action: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => inBackground(widget.modelFile.openSourcePage()),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open the model page'),
                  ),
                ),
                const SizedBox(height: 20),
                _Step(
                  number: 2,
                  title: 'Point Van at it',
                  body:
                      'Pick the downloaded file. Van copies it into its own '
                      'private storage under its own name, so it does not '
                      'matter what the download is called.',
                  action: FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => inBackground(_run(widget.modelFile.install)),
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      status.present ? 'Replace the file' : 'Choose the file',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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

/// One numbered step, with the thing it asks you to do attached to it.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.action,
  });

  final int number;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colours.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Text('$number', style: theme.textTheme.labelMedium),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colours.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: action),
            ],
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
