import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:van/app/van_service.dart';
import 'package:van_core/van_core.dart';

/// The screen you are on while actually working.
///
/// Three buttons, because those are the three true outcomes: it is done, it
/// needs longer, or you are stuck. "Stuck" is not a failure state - it is the
/// most useful thing Van can learn, so it gets equal billing.
class FocusScreen extends StatefulWidget {
  /// Creates the screen.
  const FocusScreen({
    required this.service,
    required this.clock,
    required this.session,
    required this.task,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// The running session.
  final WorkSession session;

  /// The task it belongs to.
  final Task task;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  Timer? _ticker;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = Duration(minutes: widget.session.plannedMinutes);
    // The screen stays awake: a focus timer that blanks out is a focus timer
    // you stop trusting.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _tick(Timer _) {
    if (!mounted) return;
    setState(() {
      _remaining = _remaining - const Duration(seconds: 1);
      if (_remaining.isNegative) _remaining = Duration.zero;
    });
  }

  Future<void> _done() async {
    await widget.service.completeSession(widget.session.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _needMoreTime() async {
    // Stopping early still counts as having started, which is the behaviour
    // Van most wants to reinforce.
    await widget.service.stopEarly(widget.session.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stuck() async {
    await widget.service.stopEarly(widget.session.id);
    if (!mounted) return;
    await widget.service.snooze(widget.session.id, minutes: 20);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text(
                widget.task.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              Text(
                '$minutes:$seconds',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _done,
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _needMoreTime,
                  child: const Text('Need more time'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _stuck,
                  child: const Text("I'm stuck"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
