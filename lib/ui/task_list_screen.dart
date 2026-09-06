import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/wording.dart';
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
  Future<bool> _complete(Task task, {required String from}) async {
    try {
      await widget.service.completeTask(task.id, source: from);
    } on Object {
      _say('Could not finish "${task.title}" - still on your list.');
      return false;
    }
    _say('Finished "${task.title}".', undo: task);
    return true;
  }

  /// Finishes from the tick rather than the swipe.
  ///
  /// The swipe stays - it is faster once you know it exists - but it is a
  /// gesture with no affordance, and a list of tasks whose only completion
  /// route is invisible reads as a list you cannot complete anything from.
  Future<void> _tick(Task task) async {
    if (!await _complete(task, from: 'task_list_tick')) return;
    if (!mounted) return;
    setState(
      () => _open = [..._open]..removeWhere((t) => t.id == task.id),
    );
    await _refresh();
  }

  Future<void> _reopen(Task task) async {
    await widget.service.reopenTask(task.id);
    await _refresh();
    _say('Put "${task.title}" back and replanned it.');
  }

  /// Opens the estimate editor and applies what comes back.
  Future<void> _editEstimate(Task task) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      // Without this the sheet is capped at half the screen, and a raised
      // keyboard then has nowhere to push the Save button to.
      isScrollControlled: true,
      builder: (_) => EstimateSheet(
        title: task.title,
        initialMinutes:
            task.estimatedMinutes ?? widget.service.defaultEstimateMinutes,
        isAssumed: task.estimatedMinutes == null,
      ),
    );
    if (minutes == null || !mounted) return;

    final result = await widget.service.answerDuration(task.id, '$minutes');
    await _refresh();
    _say(switch (result.outcome) {
      AnswerOutcome.replanned => 'Replanned "${task.title}".',
      AnswerOutcome.notUnderstood => 'That did not look like a length.',
      AnswerOutcome.tooLate => 'That one has already started; leaving it.',
    });
  }

  void _say(String message, {Task? undo}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: undo == null ? 2 : 5),
          action: undo == null
              ? null
              : SnackBarAction(
                  label: 'Undo',
                  onPressed: () => inBackground(_reopen(undo)),
                ),
        ),
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
                    confirmDismiss: (_) =>
                        _complete(task, from: 'task_list_swipe'),
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
                    child: _TaskRow(
                      task: task,
                      now: widget.clock.now(),
                      estimate: estimateLabel(
                        task.estimatedMinutes,
                        widget.service.defaultEstimateMinutes,
                      ),
                      onTick: () => inBackground(_tick(task)),
                      onEditEstimate: () => inBackground(_editEstimate(task)),
                    ),
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
  const _TaskRow({
    required this.task,
    required this.now,
    required this.estimate,
    required this.onTick,
    required this.onEditEstimate,
  });

  final Task task;
  final DateTime now;

  /// Already-formatted, and never empty - an unstated estimate shows Van's
  /// assumption rather than nothing, because a blank invites no correction.
  final String estimate;
  final VoidCallback onTick;
  final VoidCallback onEditEstimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = task.isOverdue(now);

    return ListTile(
      leading: IconButton(
        icon: const Icon(Icons.circle_outlined, size: 20),
        tooltip: 'Finish "${task.title}"',
        onPressed: onTick,
      ),
      title: Text(task.title),
      subtitle: task.deadline == null
          ? null
          : Text(
              'due ${_shortDate(task.deadline!.toLocal())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: overdue ? theme.colorScheme.error : null,
              ),
            ),
      // The estimate moves out of the subtitle and becomes a control. It was
      // read-only text that vanished entirely when nobody had stated one,
      // which is the worst of both: no number to correct, and no sign that Van
      // had picked one anyway.
      trailing: TextButton(onPressed: onEditEstimate, child: Text(estimate)),
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
