import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/ui/background.dart';
import 'package:van_core/van_core.dart';

/// Everything still open, in one flat list.
///
/// No folders, no labels, no projects, no sections. Those are the features
/// that turn a task list into a system you maintain instead of a list you act
/// on, and the person using Van is short of motivation, not of structure.
/// Deadline order, swipe to finish, nothing else.
class TaskListScreen extends StatefulWidget {
  /// Creates the screen.
  const TaskListScreen({required this.service, required this.clock, super.key});

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen>
    with WidgetsBindingObserver {
  List<Task> _open = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inBackground(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) inBackground(_refresh());
  }

  Future<void> _refresh() async {
    final open = await widget.service.openTasks();
    if (!mounted) return;
    setState(() {
      _open = open;
      _loaded = true;
    });
  }

  /// Writes the completion, and reports whether it actually happened.
  ///
  /// Handed to `confirmDismiss` rather than done in `onDismissed`, and that is
  /// the whole fix. `onDismissed` fires after the row is already gone, so the
  /// old version removed it optimistically and had nowhere to put it back if
  /// the write failed - re-inserting the same key does not revive a dismissed
  /// `Dismissible`, so the list went on claiming a task was done that the
  /// database still had open. `confirmDismiss` gets to say no, and the row
  /// animates back on its own.
  ///
  /// It also means the framework awaits this. The old call site was
  /// `unawaited`, so a failed write landed on the zone as an unhandled error
  /// rather than on the user as a message. See STATUS 3s.
  Future<bool> _complete(Task task) async {
    try {
      await widget.service.completeTask(task.id);
    } on Object {
      _say('Could not finish "${task.title}" - still on your list.');
      return false;
    }
    _say('Finished "${task.title}".');
    return true;
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: !_loaded
            ? const SizedBox.shrink()
            : _open.isEmpty
            ? _EmptyList(theme: theme)
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _open.length,
                itemBuilder: (context, i) {
                  final task = _open[i];
                  return Dismissible(
                    key: ValueKey(task.id),
                    direction: DismissDirection.startToEnd,
                    background: const _CompleteBackground(),
                    confirmDismiss: (_) => _complete(task),
                    onDismissed: (_) {
                      // Only reached once _complete has confirmed, so this is
                      // the success path: drop the row, then reconcile with
                      // the database. A failed reload leaves a stale list and
                      // nothing worse, but `unawaited` catches nothing on its
                      // own, so it still gets a handler.
                      setState(
                        () =>
                            _open = [..._open]
                              ..removeWhere((t) => t.id == task.id),
                      );
                      inBackground(_refresh());
                    },
                    child: _TaskRow(task: task, now: widget.clock.now()),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // A ListView rather than a Center, so pull-to-refresh still works on an
    // empty list.
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.check_circle_outline,
          size: 40,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'Nothing open.',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CompleteBackground extends StatelessWidget {
  const _CompleteBackground();

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      color: colours.primaryContainer,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, color: colours.onPrimaryContainer),
          const SizedBox(width: 12),
          Text(
            'Done',
            style: TextStyle(
              color: colours.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = task.isOverdue(now);

    return ListTile(
      leading: const Icon(Icons.circle_outlined, size: 18),
      title: Text(task.title),
      subtitle: task.deadline == null && task.estimatedMinutes == null
          ? null
          : Text(
              [
                if (task.deadline != null)
                  'due ${_shortDate(task.deadline!.toLocal())}',
                if (task.estimatedMinutes != null)
                  '${task.estimatedMinutes} min',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: overdue ? theme.colorScheme.error : null,
              ),
            ),
    );
  }
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
