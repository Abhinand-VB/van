import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/platform/notifications.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/focus_screen.dart';
import 'package:van/ui/settings_screen.dart';
import 'package:van/ui/wording.dart';
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
    required this.calendars,
    required this.calendarPreferences,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Read to tell the user when the OS will not let Van reach them.
  final Notifications notifications;

  /// Handed to the settings page, which is reached from this screen's app bar
  /// rather than from a fourth tab.
  final Calendars calendars;

  /// Which calendars planning is allowed to see.
  final CalendarPreferences calendarPreferences;

  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  ({WorkSession session, Task task})? _next;
  List<Task> _open = const [];
  bool _busy = false;
  String? _message;

  /// The one question Van is waiting on, or null when it is not asking.
  _Asking? _asking;
  NudgePermissions _permissions = const NudgePermissions(
    canPost: true,
    canScheduleExactly: true,
  );
  bool _calendarUnreadable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inBackground(_refresh());
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
    if (state == AppLifecycleState.resumed) inBackground(_refresh());
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
      // Set by the plan that just ran, so this says whether the schedule on
      // screen was made with the calendar or without it.
      _calendarUnreadable = widget.service.calendarIsUnreadable;
      if (!swept.isEmpty) _message = _sweepMessage(swept);
    });
  }

  Future<void> _requestPermission() async {
    await widget.notifications.requestPermission();
    await _refresh();
  }

  /// Opens the calendar settings page, for the banner below to tap through
  /// to.
  ///
  /// The Calendar tab's app bar is where this normally lives. It is reachable
  /// from here as well because the banner has to lead somewhere: being told
  /// the calendar could not be read is only useful next to the screen that
  /// says which calendars there are.
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          calendars: widget.calendars,
          preferences: widget.calendarPreferences,
        ),
      ),
    );
    // The excluded set may have changed, and the plan on screen was made
    // against the old one.
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

  /// Submitting either captures a new task or answers Van's question about
  /// the last one. The bar above the field says which, and there is no third
  /// state to get lost in.
  Future<void> _submit() =>
      _asking == null ? _capture() : _answer(_asking!.taskId);

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
      // A new capture replaces any question still standing about the last
      // one. Two questions queued behind a composer is the form this was
      // written to avoid.
      _asking = result.clarification == null
          ? null
          : _Asking(
              taskId: result.task.id,
              about: result.task.title,
              clarification: result.clarification!,
              assumed: result.assumedMinutes,
            );
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

  Future<void> _answer(String taskId) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);

    final result = await widget.service.answerDuration(taskId, text);
    if (result.outcome != AnswerOutcome.notUnderstood) _input.clear();
    await _refresh();
    if (!mounted) return;

    setState(() {
      _busy = false;
      // Only a re-plan closes the question. "I did not follow that" has to
      // leave it open or the user has answered into a void, and a question
      // that vanishes on a typo is worse than one that was never asked.
      if (result.outcome != AnswerOutcome.notUnderstood) _asking = null;
      _message = switch (result.outcome) {
        AnswerOutcome.replanned =>
          'Replanned into ${result.sessions.length} '
              '${result.sessions.length == 1 ? "block" : "blocks"}.',
        AnswerOutcome.notUnderstood =>
          'I did not get a length out of that - try "45 minutes".',
        AnswerOutcome.tooLate => 'That one has already started; leaving it.',
      };
    });
  }

  /// Finishes [task], with a way back.
  ///
  /// The undo is not decoration. Finishing used to be a swipe on another
  /// screen, which nobody does by accident; it is now a tap on the main one,
  /// next to the thing you are reading. A one-tap irreversible action in that
  /// position needs an exit, and `reopenTask` is it.
  Future<void> _finish(Task task, {required String from}) async {
    setState(() => _busy = true);
    try {
      await widget.service.completeTask(task.id, source: from);
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Could not finish "${task.title}" - still on your list.';
      });
      return;
    }
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = null;
    });

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Finished "${task.title}".'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => inBackground(_reopen(task)),
          ),
        ),
      );
  }

  Future<void> _reopen(Task task) async {
    await widget.service.reopenTask(task.id);
    await _refresh();
    if (!mounted) return;
    // Said plainly, because it is not a true undo: the task is planned again
    // from now, so its blocks are not the ones it had a moment ago.
    setState(() => _message = 'Put "${task.title}" back and replanned it.');
  }

  /// Opens the estimate editor for [task] and applies whatever comes back.
  Future<void> _editEstimate(Task task) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => EstimateSheet(
        title: task.title,
        // Pre-filled with the number the planner already used, so this is a
        // correction rather than an invention. That is the whole difference
        // between an editable field and an empty one.
        initialMinutes:
            task.estimatedMinutes ?? widget.service.defaultEstimateMinutes,
        isAssumed: task.estimatedMinutes == null,
      ),
    );
    if (minutes == null || !mounted) return;

    setState(() => _busy = true);
    // The same call the typed answer to Van's question goes through, so both
    // routes replan identically and write one kind of row.
    final result = await widget.service.answerDuration(task.id, '$minutes');
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Editing an estimate is answering the question, so a standing question
      // about this task is now answered and must not keep asking.
      if (result.outcome == AnswerOutcome.replanned &&
          _asking?.taskId == task.id) {
        _asking = null;
      }
      _message = switch (result.outcome) {
        AnswerOutcome.replanned =>
          'Replanned into ${result.sessions.length} '
              '${result.sessions.length == 1 ? "block" : "blocks"}.',
        AnswerOutcome.notUnderstood => 'That did not look like a length.',
        AnswerOutcome.tooLate => 'That one has already started; leaving it.',
      };
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
            if (_calendarUnreadable) ...[
              _CalendarBanner(onOpen: _openSettings),
              const SizedBox(height: 20),
            ],
            _CaptureField(
              controller: _input,
              busy: _busy,
              onSubmit: _submit,
              hint: _asking == null
                  ? 'finish the assignment by friday, 2 hours'
                  : questionFor(_asking!.clarification),
            ),
            if (_asking case final asking?) ...[
              const SizedBox(height: 8),
              ClarifyBar(
                clarification: asking.clarification,
                about: asking.about,
                assumed: asking.assumed,
                onDismiss: () => setState(() => _asking = null),
              ),
            ],
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
                defaultEstimateMinutes: widget.service.defaultEstimateMinutes,
                onStart: _start,
                onEditEstimate: () => _editEstimate(next.task),
                onFinish: () => _finish(next.task, from: 'now_card'),
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
              // The circle used to be an `Icon`. It looked exactly like a
              // checkbox, sat where a checkbox sits, and did nothing at all -
              // which is most of why finishing a task felt impossible, since
              // the only real way to do it was an undiscoverable swipe on
              // another tab. It is now the thing it always looked like.
              for (final task in rest)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: IconButton(
                    icon: const Icon(Icons.circle_outlined, size: 20),
                    tooltip: 'Finish "${task.title}"',
                    onPressed: _busy
                        ? null
                        : () => inBackground(_finish(task, from: 'now_list')),
                  ),
                  title: Text(task.title),
                  subtitle: task.deadline == null
                      ? null
                      : Text('due ${_shortDate(task.deadline!.toLocal())}'),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _editEstimate(task),
                    child: Text(
                      estimateLabel(
                        task.estimatedMinutes,
                        widget.service.defaultEstimateMinutes,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A question Van is waiting on, and the task it belongs to.
class _Asking {
  const _Asking({
    required this.taskId,
    required this.about,
    required this.clarification,
    this.assumed,
  });

  final String taskId;
  final String about;
  final Clarification clarification;
  final int? assumed;
}

class _CaptureField extends StatelessWidget {
  const _CaptureField({
    required this.controller,
    required this.busy,
    required this.onSubmit,
    required this.hint,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  /// What the empty field invites. Changes to the question while one is
  /// standing, so the field says what typing into it will do.
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: !busy,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: hint,
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
    required this.defaultEstimateMinutes,
    required this.onStart,
    required this.onEditEstimate,
    required this.onFinish,
  });

  final WorkSession session;
  final Task task;
  final DateTime now;

  /// What the planner assumes when nobody has said. Shown, marked as an
  /// assumption, rather than left blank.
  final int defaultEstimateMinutes;
  final VoidCallback onStart;
  final VoidCallback onEditEstimate;
  final VoidCallback onFinish;

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
        if (session.isOpener) ...[
          const SizedBox(height: 4),
          Text(
            openerLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
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
        const SizedBox(height: 12),
        // The estimate, editable, and always carrying a number. This is the
        // one figure the whole plan is built from and until now there was no
        // way to correct it after capture - so a task Van had guessed an hour
        // for stayed an hour for ever, and nothing about the card said a guess
        // had been made.
        ActionChip(
          avatar: const Icon(Icons.timer_outlined, size: 18),
          label: Text(
            estimateLabel(task.estimatedMinutes, defaultEstimateMinutes),
          ),
          onPressed: onEditEstimate,
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Mark done'),
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

/// Says so when a plan was made without the calendar it was meant to use.
///
/// Deliberately separate from the permission banner and deliberately quieter.
/// Not having the grant is a choice and produces nothing here; this appears
/// only when Van had permission, tried to read and could not - the case that
/// is otherwise invisible, because the resulting plan looks entirely normal
/// and is quietly wrong. It is the same lesson as the exact-alarm banner: a
/// degradation the user cannot see is one they cannot act on.
class _CalendarBanner extends StatelessWidget {
  const _CalendarBanner({required this.onOpen});

  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.event_busy, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Van could not read your calendar, so this plan ignores '
                  'anything already on it. Tap to check.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
