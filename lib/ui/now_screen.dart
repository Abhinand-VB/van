import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/platform/notifications.dart';
import 'package:van/ui/focus_screen.dart';
import 'package:van_core/van_core.dart';

/// The home screen, and deliberately the only thing on it.
///
/// One next action, one button. No dashboard, no streaks, no folders. The
/// person using Van already has low motivation; making them navigate a
/// productivity system before they can start is the problem, not the product.
class NowScreen extends StatefulWidget {
  /// Creates the screen.
  const NowScreen({
    required this.service,
    required this.clock,
    required this.notifications,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Read to tell the user when the OS will not let Van reach them.
  final Notifications notifications;

  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  ({WorkSession session, Task task})? _next;
  List<Task> _open = const [];
  bool _busy = false;
  String? _message;
  NudgePermissions _permissions = const NudgePermissions(
    canPost: true,
    canScheduleExactly: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is Van's cheapest reliable trigger. It is also
    // the moment the user is most likely to accept being told that this
    // morning's block has been moved to this afternoon.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final swept = await widget.service.sweepStaleSessions();
    final next = await widget.service.next();
    final open = await widget.service.openTasks();
    // Read every refresh rather than cached: the user can revoke either grant
    // from system settings at any moment, and Van finding out on the next
    // restart is exactly the silent failure this banner exists to prevent.
    final permissions = await widget.notifications.permissions();
    if (!mounted) return;
    setState(() {
      _next = next;
      _open = open;
      _permissions = permissions;
      if (!swept.isEmpty) _message = _sweepMessage(swept);
    });
  }

  Future<void> _requestPermission() async {
    await widget.notifications.requestPermission();
    await _refresh();
  }

  /// Says plainly what happened to work nobody started.
  ///
  /// Silently reshuffling the plan would make Van feel arbitrary; the whole
  /// point is that the user can see the deal being renegotiated.
  static String _sweepMessage(SweepReport swept) {
    final moved = swept.moved.length;
    final dropped = swept.dropped.length;
    final parts = <String>[
      if (moved > 0) 'Moved $moved missed ${_blocks(moved)} to later',
      if (dropped > 0) 'Dropped $dropped that would not fit',
    ];
    return '${parts.join('. ')}.';
  }

  static String _blocks(int n) => n == 1 ? 'block' : 'blocks';

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

    // Everything except whatever the card above is already showing. Matched by
    // task id rather than by dropping the first entry: the card comes from the
    // next *session* and this list is ordered by deadline, so the two disagree
    // whenever the next block belongs to a task that is not the most urgent.
    // Skipping by position then hides an unrelated task and repeats the one
    // already on screen.
    final rest = _open
        .where((task) => task.id != next?.task.id)
        .take(4)
        .toList();

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
            if (!_permissions.complete) ...[
              _PermissionBanner(
                permissions: _permissions,
                onFix: _requestPermission,
              ),
              const SizedBox(height: 20),
            ],
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
            if (rest.isNotEmpty) ...[
              Text(
                // "After that" only means anything when there is a card above
                // for it to come after.
                next == null ? 'Open' : 'After that',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final task in rest)
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

/// Says so when the OS will not let Van do its job.
///
/// Van asks for permission once and then stops asking, so this is the only
/// thing standing between a declined prompt and an app that silently never
/// nudges anyone. It is deliberately a row on the Now screen rather than a
/// dialog: present every time you look, impossible to be trapped by.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.permissions, required this.onFix});

  final NudgePermissions permissions;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Two different problems. One makes Van a task list; the other only makes
    // it imprecise, and overstating that would train the user to ignore this.
    final blocked = !permissions.canPost;
    final colours = theme.colorScheme;

    return Material(
      color: blocked ? colours.errorContainer : colours.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onFix,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                blocked ? Icons.notifications_off : Icons.schedule,
                size: 20,
                color: blocked ? colours.onErrorContainer : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  blocked
                      ? 'Van cannot send notifications, so it cannot nudge '
                            'you. Tap to fix.'
                      : 'Nudges may arrive up to an hour late. Allow alarms '
                            'and reminders to fix.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: blocked ? colours.onErrorContainer : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
