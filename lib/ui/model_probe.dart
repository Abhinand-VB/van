import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:van/inference/backend.dart';
import 'package:van/inference/capabilities/extract_task.dart';
import 'package:van/inference/golden_run_store.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/platform/local_llm.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/golden_run_screen.dart';
import 'package:van_core/van_core.dart';

/// What one run of the model produced.
class ProbeResult {
  /// Creates a result.
  const ProbeResult({
    required this.raw,
    required this.milliseconds,
    this.draft,
    this.error,
  });

  /// Exactly what came back, before anything tried to make sense of it.
  final String raw;

  /// How long it took, end to end.
  final int milliseconds;

  /// What `extract_task` made of it, when it could make anything.
  final TaskDraft? draft;

  /// Why it failed, when it did.
  final String? error;

  /// Whether the model answered at all.
  bool get ok => error == null;
}

/// Runs one prompt through the on-device model and shows what came back.
///
/// **This is the harness issue 14 has been waiting for.** `GemmaBackend` could
/// not be reached from `tool/run_goldens.dart` - it needs the platform channel
/// and a model file, neither of which exists off a phone - so nothing about
/// the model could be measured, and therefore nothing could be routed to it.
/// The gate in `STATUS.md` 3e was unevaluable rather than unmet.
///
/// It deliberately does **not** change any routing. It asks the engine a
/// question and shows the answer, the latency, and what `ExtractTask` would
/// have made of it. Deciding whether that is good enough is a judgement for a
/// person holding the phone, which is the only place that judgement can
/// currently be made.
class ModelProbe extends StatefulWidget {
  /// Creates the probe.
  const ModelProbe({
    required this.llm,
    required this.prompts,
    required this.clock,
    super.key,
  });

  /// The channel to the on-device engine.
  final LocalLlm llm;

  /// Source of the current time, for resolving "tomorrow" in the prompt.
  final Clock clock;

  /// The versioned prompt assets, so this asks what Van would ask.
  final Prompts prompts;

  @override
  State<ModelProbe> createState() => _ModelProbeState();
}

class _ModelProbeState extends State<ModelProbe> {
  /// The sentence that started this. Real, and the parser gets it wrong.
  static const _default =
      'Go to the shop take a stroll cook lunch and do my remaining works '
      'also I need to do taxes';

  late final _input = TextEditingController(text: _default);
  ProbeResult? _result;
  bool _running = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
    });

    final capability = ExtractTask(prompt: widget.prompts.extractTask);
    final input = ExtractTaskInput(
      _input.text.trim(),
      now: widget.clock.now(),
    );
    // The same request Van would build, so what is measured here is what
    // would actually happen if this capability were routed to the model -
    // not a hand-written prompt that flatters it.
    final request = capability.buildRequest(
      input,
      const BackendCapabilities(isLocal: true),
    );

    // A stopwatch rather than two readings of the wall clock: this is a
    // duration, and a duration measured against a clock that can be changed
    // underneath it is not a measurement. The layer guard forbids ambient
    // time here anyway, and is right to.
    final elapsed = Stopwatch()..start();
    ProbeResult outcome;
    try {
      final raw = await widget.llm.generate(
        system: request.system,
        prompt: request.prompt,
        maxOutputTokens: request.maxOutputTokens,
        temperature: request.temperature,
      );
      outcome = ProbeResult(
        raw: raw,
        milliseconds: elapsed.elapsedMilliseconds,
        draft: capability.parse(raw),
      );
    } on LocalLlmException catch (e) {
      outcome = ProbeResult(
        raw: '',
        milliseconds: elapsed.elapsedMilliseconds,
        error: '${e.error.name}: ${e.message}',
      );
    } on Object catch (e) {
      outcome = ProbeResult(
        raw: '',
        milliseconds: elapsed.elapsedMilliseconds,
        error: '$e',
      );
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = outcome;
    });
  }

  /// Opens the whole-set run, which needs somewhere to save its progress.
  Future<void> _openSet() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoldenRunScreen(
          llm: widget.llm,
          prompts: widget.prompts,
          store: FileGoldenRunStore(directory.path),
          clock: widget.clock,
        ),
      ),
    );
  }

  /// What Van made of the reply, in one line.
  static String _understood(TaskDraft? draft) {
    if (draft == null) {
      return 'Nothing — the reply could not be parsed as a task.';
    }
    final minutes = draft.estimatedMinutes;
    final deadline = draft.deadline;
    return [
      '"${draft.title}"',
      if (minutes != null) '$minutes min',
      if (deadline != null) 'due ${deadline.toLocal()}',
    ].join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Try the model')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Runs one sentence through the model on this phone and shows what '
            'comes back, how long it took, and what Van would have made of '
            'it. Nothing is captured and no routing changes.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Sentence',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : () => inBackground(_run()),
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_running ? 'Thinking…' : 'Run it'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('All 29 cases', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            'One sentence tells you the model works. The golden set tells you '
            'whether it is worth using, which is the question STATUS 3e '
            'actually asks.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : () => inBackground(_openSet()),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Run the golden set'),
          ),
          if (result != null) ...[
            const SizedBox(height: 24),
            Text(
              result.ok
                  ? 'Answered in ${result.milliseconds} ms'
                  : 'Failed after ${result.milliseconds} ms',
              style: theme.textTheme.titleSmall?.copyWith(
                color: result.ok ? null : theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            if (result.error case final error?)
              SelectableText(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontFamily: 'monospace',
                ),
              )
            else ...[
              Text('What Van understood', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                // The line that decides everything. A model that answers
                // quickly and unparseably is worse than the parser, and this
                // is where that shows.
                _understood(result.draft),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text('Raw reply', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(
                result.raw,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
