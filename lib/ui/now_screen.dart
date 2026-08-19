import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/ui/focus_screen.dart';
import 'package:van_core/van_core.dart';

/// The home screen, and deliberately the only thing on it.
///
/// One next action, one button. No dashboard, no streaks, no folders. The
/// person using Van already has low motivation; making them navigate a
/// productivity system before they can start is the problem, not the product.
class NowScreen extends StatefulWidget {
  /// Creates the screen.
  const NowScreen({required this.service, required this.clock, super.key});

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen> {
  final _input = TextEditingController();
  ({WorkSession session, Task task})? _next;
  List<Task> _open = const [];
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = await widget.service.next();
    final open = await widget.service.openTasks();
    if (!mounted) return;
    setState(() {
      _next = next;
      _open = open;
    });
  }

  Future<void> _capture() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);

    final result = await widget.service.capture(text);
    _input.clear();
    await _refresh();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _message = result.sessions.isEmpty
          ? 'Captured "${result.task.title}", but there was no room to '
                'schedule it.'
          : result.isPartial
          ? 'Scheduled ${result.sessions.length} blocks. '
                '${result.shortfallMinutes} minutes would not fit before the '
                'deadline.'
          : 'Scheduled ${result.sessions.length} '
                '${result.sessions.length == 1 ? "block" : "blocks"}.';
    });
  }

  Future<void> _start() async {
    final next = _next;
    if (next == null) return;
    final started = await widget.service.startSession(next.session.id);
    if (started == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FocusScreen(
          service: widget.service,
          clock: widget.clock,
          session: started,
          task: next.task,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = _next;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Van'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _CaptureField(
              controller: _input,
              busy: _busy,
              onSubmit: _capture,
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 28),
            if (next == null)
              _EmptyState(hasTasks: _open.isNotEmpty)
            else
              _NextCard(
                session: next.session,
                task: next.task,
                now: widget.clock.now(),
                onStart: _start,
              ),
            const SizedBox(height: 32),
            if (_open.length > 1) ...[
              Text('After that', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final task in _open.skip(1).take(4))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.circle_outlined, size: 16),
                  title: Text(task.title),
                  subtitle: task.deadline == null
                      ? null
                      : Text('due ${_shortDate(task.deadline!.toLocal())}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaptureField extends StatelessWidget {
  const _CaptureField({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: !busy,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: 'finish the assignment by friday, 2 hours',
        border: const OutlineInputBorder(),
        suffixIcon: busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.add),
                onPressed: onSubmit,
                tooltip: 'Capture',
              ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.session,
    required this.task,
    required this.now,
    required this.onStart,
  });

  final WorkSession session;
  final Task task;
  final DateTime now;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final late = session.minutesLate(now);
    final running = session.hasStarted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NEXT', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        Text(task.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          running
              ? 'In progress'
              : late > 0
              ? '${session.plannedMinutes} minutes  ·  $late min late'
              : '${session.plannedMinutes} minutes  ·  '
                    '${_shortTime(session.plannedStart.toLocal())}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: onStart,
            child: Text(running ? 'RESUME' : 'START'),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasTasks});

  final bool hasTasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          Icons.park_outlined,
          size: 56,
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 16),
        Text(
          hasTasks ? 'Nothing scheduled right now.' : 'Nothing to do yet.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Type what you need to do above.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _shortTime(DateTime local) {
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _shortDate(DateTime local) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${local.day} ${months[local.month - 1]}';
}
