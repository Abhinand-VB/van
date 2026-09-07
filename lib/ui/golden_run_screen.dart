import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:van/inference/golden_run_store.dart';
import 'package:van/inference/goldens.dart';
import 'package:van/inference/on_device_runner.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/platform/local_llm.dart';
import 'package:van/ui/background.dart';
import 'package:van_core/van_core.dart';

/// Runs the whole `extract_task` golden set against the model on this phone.
///
/// **This is the gate in `STATUS.md` 3e, finally evaluable.** Until now the
/// number that decides whether anything gets routed to the on-device model
/// could not be taken: `tool/run_goldens.dart` runs off a phone, where there
/// is no platform channel and no weights, so it only ever measured the
/// deterministic parser. The gate was unevaluable rather than unmet, which is
/// a different and much worse position to be in.
///
/// Three things make it usable rather than merely possible:
///
/// * **It reports what the model did, not what Van did.** `InferenceRouter`
///   always returns an answer; when the model fails the parser answers
///   instead, and the case would score as a pass. `LastInference` separates
///   the two, and the headline number counts only cases a model both answered
///   and got right.
/// * **It is resumable.** At about two and three quarter minutes a case the
///   run is eighty minutes long, and the phone locks every fifteen. Each case
///   is written to disk as it finishes.
/// * **It changes no routing.** It measures. What to do about the number is a
///   decision for a person, and 3e says what that decision is.
class GoldenRunScreen extends StatefulWidget {
  /// Creates the screen.
  const GoldenRunScreen({
    required this.llm,
    required this.prompts,
    required this.store,
    required this.clock,
    super.key,
    this.loadAsset,
  });

  /// The channel to the on-device engine.
  final LocalLlm llm;

  /// The versioned prompts, so this asks what Van would ask.
  final Prompts prompts;

  /// Where a part-finished run is kept.
  final GoldenRunStore store;

  /// Source of the current time, for stamping when a run began.
  final Clock clock;

  /// Reads the golden set. Injected so this is testable off a phone.
  ///
  /// Null means the app's own bundle, which is what the phone wants and what
  /// a const constructor cannot name as a default.
  final Future<String> Function(String key)? loadAsset;

  @override
  State<GoldenRunScreen> createState() => _GoldenRunScreenState();
}

class _GoldenRunScreenState extends State<GoldenRunScreen> {
  static const _capability = 'extract_task';
  static const _asset = 'test/golden/$_capability.json';

  GoldenSet? _set;
  GoldenRun? _run;
  String? _error;
  bool _running = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    inBackground(_load());
  }

  Future<void> _load() async {
    try {
      final read = widget.loadAsset ?? rootBundle.loadString;
      final set = GoldenSet.fromJson(await read(_asset));
      final saved = await widget.store.read(_capability);
      if (!mounted) return;
      setState(() {
        _set = set;
        // A run measured against a different prompt is not a run of this one.
        // Dropping it costs an hour; keeping it would report a number that
        // describes nothing.
        _run = saved != null && saved.matches(_promptText) ? saved : null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _start({required bool fresh}) async {
    final set = _set;
    if (set == null) return;

    if (fresh) await widget.store.clear(_capability);
    final done = fresh ? <GoldenOutcome>[] : _run?.outcomes ?? [];
    var run = GoldenRun(
      capability: _capability,
      promptFingerprint: GoldenRun.fingerprint(_promptText),
      startedAt: _run?.startedAt ?? widget.clock.now(),
      outcomes: done,
    );

    setState(() {
      _cancelled = false;
      _running = true;
      _run = run;
    });

    // Built here rather than taken from the app, deliberately: this must
    // measure the on-device backend whatever `inference_config.json`
    // currently routes, and it must not disturb the router the rest of the
    // app is using.
    final runner = onDeviceRunner(widget.llm, prompts: widget.prompts);

    try {
      await runner.run(
        set,
        done: done,
        stop: () => _cancelled || !mounted,
        onOutcome: (outcome) async {
          run = GoldenRun(
            capability: run.capability,
            promptFingerprint: run.promptFingerprint,
            startedAt: run.startedAt,
            outcomes: [...run.outcomes, outcome],
          );
          // Written before the screen is told, so a crash between the two
          // loses nothing.
          await widget.store.write(run);
          if (!mounted) return;
          setState(() => _run = run);
        },
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }

    if (!mounted) return;
    setState(() => _running = false);
  }

  /// Both halves of the prompt these cases are asked with.
  ///
  /// The system half frames the task and changing it changes the answers, so
  /// a fingerprint that ignored it would happily resume a run measured
  /// against different instructions.
  String get _promptText {
    final template = widget.prompts.extractTask;
    return '${template.system}\n${template.prompt}';
  }

  /// The report over whatever has been measured so far.
  GoldenReport get _report => GoldenReport(
    capability: _capability,
    outcomes: _run?.outcomes ?? const [],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = _set;
    final report = _report;
    final total = set?.cases.length ?? 0;
    final finished = report.total;
    final remaining = total - finished;

    return Scaffold(
      appBar: AppBar(title: const Text('Golden set')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Runs all $total extract_task cases through the model on this '
            'phone and reports how many it answered correctly. About three '
            'minutes a case, so roughly '
            '${(total * 2.75).round()} minutes for the set. It saves after '
            'every case, so closing Van loses nothing. Nothing is captured '
            'and no routing changes.\n\n'
            'Each case is allowed '
            '${measurementTimeout.inMinutes} minutes rather than the 20 '
            'seconds a capture waits, because at 20 seconds every case would '
            'time out and the answer would be an unearned zero. This measures '
            'whether the model is right, not whether it is quick — it is not '
            'quick, and the times below say by how much.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (_error case final error?)
            SelectableText(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontFamily: 'monospace',
              ),
            ),
          if (set != null) ...[
            LinearProgressIndicator(
              value: total == 0 ? 0 : finished / total,
            ),
            const SizedBox(height: 12),
            Text(
              '$finished of $total measured'
              '${_running ? ' · running' : ''}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              // The headline, and the only number that answers 3e. Cases the
              // parser rescued are not the model's.
              'The model answered ${report.answeredByModel} and got '
              '${report.passedViaModel} of those right — '
              '${(report.modelPassRate * 100).toStringAsFixed(0)}% of the '
              'whole set, ${report.modelClearsGate ? 'clearing' : 'below'} '
              'the 80% gate.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Van itself would have got ${report.passed} of $finished right, '
              'because the parser answers whatever the model does not.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_running)
              OutlinedButton.icon(
                onPressed: () => setState(() => _cancelled = true),
                icon: const Icon(Icons.stop),
                label: const Text('Stop after this case'),
              )
            else ...[
              FilledButton.icon(
                onPressed: remaining == 0
                    ? null
                    : () => inBackground(_start(fresh: false)),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  finished == 0 ? 'Run the set' : 'Continue — $remaining left',
                ),
              ),
              if (finished > 0) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => inBackground(_start(fresh: true)),
                  child: const Text('Start over'),
                ),
              ],
            ],
            const SizedBox(height: 24),
            for (final outcome in report.outcomes) _CaseRow(outcome: outcome),
          ] else if (_error == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/// One measured case.
class _CaseRow extends StatelessWidget {
  const _CaseRow({required this.outcome});

  final GoldenOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Three states, not two. A case the parser answered is neither a pass nor
    // a failure of the model, and colouring it green would be the lie this
    // whole screen exists to avoid.
    final (icon, colour) = switch ((outcome.viaModel, outcome.passed)) {
      (false, _) => (Icons.remove, theme.colorScheme.onSurfaceVariant),
      (true, true) => (Icons.check, theme.colorScheme.primary),
      (true, false) => (Icons.close, theme.colorScheme.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(outcome.name, style: theme.textTheme.bodyMedium),
                Text(
                  [
                    if (!outcome.viaModel)
                      'fell back${outcome.failureReason == null ? '' : ' — '
                                '${outcome.failureReason}'}'
                    else
                      'model',
                    if (outcome.latencyMs case final ms?) '$ms ms',
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final failure in outcome.failures)
                  Text(
                    failure,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
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
