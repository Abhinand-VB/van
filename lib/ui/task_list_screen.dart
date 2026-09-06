import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/tab_pulse.dart';
import 'package:van/ui/wording.dart';
import 'package:van_core/van_core.dart';

/// Everything open, and what was finished lately.
///
/// No folders, no labels, no projects, no priorities to sort by. Those are the
/// features that turn a task list into a system you maintain instead of a list
/// you act on, and the person using Van is short of motivation, not of
/// structure. Deadline order, and one section underneath for what is done.
///
/// **The finished section is not decoration and it is not a trophy shelf.** It
/// is the only place in Van where an estimate meets what actually happened, so
/// it shows both, and it invites the missing half of that comparison on every
/// row that lacks it. Without it, `actualMinutes` would be a field nothing
/// ever filled in.
class TaskListScreen extends StatefulWidget {
  /// Creates the screen.
  const TaskListScreen({
    required this.service,
    required this.clock,
    this.refreshOn,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Ticks when this tab becomes the visible one. See [TabPulse].
  final Listenable? refreshOn;

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen>
    with WidgetsBindingObserver {
  List<Task> _open = const [];
  List<Task> _done = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.refreshOn?.addListener(_onShown);
    inBackground(_refresh());
  }

  /// Reloads when the tab is opened. Finishing something on Now changes this
  /// list, and an IndexedStack would otherwise show yesterday's answer.
  void _onShown() => inBackground(_refresh());

  @override
  void dispose() {
    widget.refreshOn?.removeListener(_onShown);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) inBackground(_refresh());
  }

  Future<void> _refresh() async {
    final open = await widget.service.openTasks();
    final done = await widget.service.finishedTasks();
    if (!mounted) return;
    setState(() {
      _open = open;
      _done = done;
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
    await _refresh();
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
    setState(() => _open = [..._open]..removeWhere((t) => t.id == task.id));
    await _refresh();
  }

  Future<void> _reopen(Task task) async {
    await widget.service.reopenTask(task.id);
    await _refresh();
    _say('Put "${task.title}" back and replanned it.');
  }

  /// Opens the estimate editor and applies what comes back.
  Future<void> _editEstimate(Task task) async {
    final minutes = await _askMinutes(
      title: task.title,
      subtitle: task.estimatedMinutes == null
          ? 'Nobody said how long, so Van assumed this.'
          : 'How long you said it would take.',
      initial: task.estimatedMinutes ?? widget.service.defaultEstimateMinutes,
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

  /// Asks how long the work actually took, and records it.
  ///
  /// Pre-filled with what Van *watched* happen, when it watched any of it: the
  /// time between START and Done on blocks for this task. That is a different
  /// thing from how long the work took - it excludes everything done outside
  /// the app - so it seeds the question rather than answering it, and the
  /// subtitle says which it is.
  Future<void> _recordTime(Task task) async {
    final measured = await widget.service.measuredMinutes(task.id);
    if (!mounted) return;

    final minutes = await _askMinutes(
      title: task.title,
      subtitle: measured > 0
          ? 'Van watched $measured minutes of this in a block. Adjust it for '
                'anything done outside the app.'
          : 'How long it actually took, all in.',
      initial: measured > 0
          ? measured
          : task.actualMinutes ??
                task.estimatedMinutes ??
                widget.service.defaultEstimateMinutes,
    );
    if (minutes == null || !mounted) return;

    await widget.service.recordActualMinutes(task.id, minutes);
    await _refresh();
    _say('Noted: "${task.title}" took ${estimateLabel(minutes, minutes)}.');
  }

  Future<int?> _askMinutes({
    required String title,
    required String subtitle,
    required int initial,
  }) => showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => EstimateSheet(
      title: title,
      subtitle: subtitle,
      initialMinutes: initial,
    ),
  );

  Future<void> _confirmDelete(Task task) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${task.title}"?'),
        // Says what it is *not*, because the alternative to deleting is
        // finishing and the two mean opposite things to a log that is trying
        // to learn what this person follows through on.
        content: const Text(
          'It goes off the list entirely, along with any blocks planned for '
          'it. Use Done instead if you actually did it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(yes ?? false)) return;

    await widget.service.deleteTask(task.id);
    await _refresh();
    _say('Deleted "${task.title}".');
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

  void _onMenu(Task task, _RowAction action) => inBackground(switch (action) {
    _RowAction.estimate => _editEstimate(task),
    _RowAction.timeTaken => _recordTime(task),
    _RowAction.delete => _confirmDelete(task),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: !_loaded
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (_open.isEmpty)
                    _EmptyList(theme: theme, hasHistory: _done.isNotEmpty)
                  else
                    for (final task in _open)
                      Dismissible(
                        key: ValueKey(task.id),
                        direction: DismissDirection.startToEnd,
                        background: const _CompleteBackground(),
                        confirmDismiss: (_) =>
                            _complete(task, from: 'task_list_swipe'),
                        onDismissed: (_) {
                          // Only reached once _complete has confirmed, so this
                          // is the success path: drop the row, then reconcile
                          // with the database. A failed reload leaves a stale
                          // list and nothing worse, but `unawaited` catches
                          // nothing on its own, so it still gets a handler.
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
                          onEditEstimate: () =>
                              inBackground(_editEstimate(task)),
                          onMenu: (action) => _onMenu(task, action),
                        ),
                      ),
                  if (_done.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        'Finished',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        // The reason this section exists, said once.
                        'Tap a time to say how long it really took. It is the '
                        'only way Van can find out whether its estimates are '
                        'any good.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final task in _done)
                      _DoneRow(
                        task: task,
                        onRecordTime: () => inBackground(_recordTime(task)),
                        onMenu: (action) => _onMenu(task, action),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// What a row's overflow menu offers.
enum _RowAction {
  /// Change how long Van thinks it will take, and replan.
  estimate,

  /// Say how long it actually took.
  timeTaken,

  /// Remove it entirely.
  delete,
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.theme, required this.hasHistory});

  final ThemeData theme;
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.check_circle_outline,
          size: 40,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          hasHistory ? 'Nothing open.' : 'Nothing here yet.',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          hasHistory
              ? 'Everything you captured is done.'
              : 'Say what needs doing on the Now screen.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
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

class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.onSelected, required this.forDone});

  final ValueChanged<_RowAction> onSelected;

  /// A finished task cannot usefully be re-estimated - the estimate is now
  /// history to compare against, and replanning something that is done would
  /// put blocks on the calendar for work that has stopped.
  final bool forDone;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_RowAction>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert, size: 20),
    onSelected: onSelected,
    itemBuilder: (_) => [
      const PopupMenuItem(
        value: _RowAction.timeTaken,
        child: Text('Time taken…'),
      ),
      if (!forDone)
        const PopupMenuItem(
          value: _RowAction.estimate,
          child: Text('Estimate…'),
        ),
      const PopupMenuItem(value: _RowAction.delete, child: Text('Delete')),
    ],
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.now,
    required this.estimate,
    required this.onTick,
    required this.onEditEstimate,
    required this.onMenu,
  });

  final Task task;
  final DateTime now;

  /// Already-formatted, and never empty - an unstated estimate shows Van's
  /// assumption rather than nothing, because a blank invites no correction.
  final String estimate;
  final VoidCallback onTick;
  final VoidCallback onEditEstimate;
  final ValueChanged<_RowAction> onMenu;

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
      // The estimate is a control rather than read-only text. It was a
      // subtitle that vanished entirely when nobody had stated one, which is
      // the worst of both: no number to correct, and no sign Van had picked
      // one anyway.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onEditEstimate, child: Text(estimate)),
          _RowMenu(onSelected: onMenu, forDone: false),
        ],
      ),
    );
  }
}

/// A finished task, with the estimate next to what it really took.
class _DoneRow extends StatelessWidget {
  const _DoneRow({
    required this.task,
    required this.onRecordTime,
    required this.onMenu,
  });

  final Task task;
  final VoidCallback onRecordTime;
  final ValueChanged<_RowAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;
    final actual = task.actualMinutes;
    final ratio = task.estimateRatio;

    return ListTile(
      leading: Icon(Icons.check_circle, size: 22, color: colours.primary),
      title: Text(
        task.title,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colours.onSurfaceVariant,
        ),
      ),
      subtitle: actual == null
          ? null
          : Text(
              // Only shown once both numbers exist, because "took 3h" on its
              // own says nothing about whether the plan was wrong.
              ratio == null
                  ? 'took ${estimateLabel(actual, actual)}'
                  : 'took ${estimateLabel(actual, actual)}  ·  estimated '
                        '${estimateLabel(task.estimatedMinutes, actual)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ratio != null && ratio > 1.5
                    ? colours.error
                    : colours.onSurfaceVariant,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The invitation. A finished task with no recorded time is the
          // common case, and a button that says so is the only thing that
          // will ever get one filled in.
          TextButton(
            onPressed: onRecordTime,
            child: Text(
              actual == null ? 'Add time' : estimateLabel(actual, actual),
            ),
          ),
          _RowMenu(onSelected: onMenu, forDone: true),
        ],
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
