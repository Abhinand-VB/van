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

  /// Set once any of the three buttons is pressed.
  ///
  /// Each writes to the database and then pops, and until the pop lands all
  /// three stay tappable. Done followed by Need more time is one fumbled
  /// thumb away, and the service refuses the second call - so without this
  /// the user would press a button and watch nothing happen.
  bool _deciding = false;

  @override
  void initState() {
    super.initState();
    _remaining = _remainingFor(widget.session, widget.clock.now());
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
    // Recomputed from the clock rather than decremented, so the timer cannot
    // drift and cannot be fooled by the screen sleeping through a tick.
    setState(
      () => _remaining = _remainingFor(widget.session, widget.clock.now()),
    );
  }

  /// How much of [session] is left at [now].
  ///
  /// Measured from when START was actually pressed, not from when this screen
  /// opened. The Now card offers RESUME on a running block, so this screen is
  /// routinely reached partway through - and a timer that restarted at the
  /// full length each time would quietly turn a 45-minute block into as much
  /// time as you liked.
  static Duration _remainingFor(WorkSession session, DateTime now) {
    final planned = Duration(minutes: session.plannedMinutes);
    final start = session.actualStart;
    if (start == null) return planned;

    final left = planned - now.difference(start);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _done() async {
    if (_deciding) return;
    setState(() => _deciding = true);
    await widget.service.completeSession(widget.session.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _needMoreTime() async {
    if (_deciding) return;
    setState(() => _deciding = true);
    // Stopping early still counts as having started, which is the behaviour
    // Van most wants to reinforce.
    await widget.service.stopEarly(widget.session.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stuck() async {
    if (_deciding) return;
    setState(() => _deciding = true);
    // One call, because it is one decision. Doing this as stopEarly followed
    // by snooze meant an interruption between them could leave the block
    // stopped with nothing scheduled to pick it up again.
    await widget.service.stuck(widget.session.id);
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
                  onPressed: _deciding ? null : _done,
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _deciding ? null : _needMoreTime,
                  child: const Text('Need more time'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _deciding ? null : _stuck,
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
