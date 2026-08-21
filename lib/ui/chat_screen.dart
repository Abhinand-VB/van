import 'dart:async';

import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van_core/van_core.dart';

/// One line in the conversation.
///
/// A sealed pair rather than a single type with a nullable plan, so the
/// builder cannot forget a case and render an approval card with nothing in
/// it.
sealed class ChatEntry {
  const ChatEntry();
}

/// Something the user typed.
class UserLine extends ChatEntry {
  /// Creates a line.
  const UserLine(this.text);

  /// What they wrote, verbatim.
  final String text;
}

/// Van's answer: a plan, awaiting approval.
class PlanCard extends ChatEntry {
  /// Creates a card.
  PlanCard(this.result) : undone = false;

  /// Creates the same card after the user rejected it.
  PlanCard.undone(this.result) : undone = true;

  /// What capture produced.
  final CaptureResult result;

  /// Whether the user has taken it back.
  final bool undone;
}

/// Capture as a conversation, with the plan shown for approval.
///
/// The quick-add field on the Now screen answers "get this out of my head".
/// This answers the other half: seeing what Van decided your sentence meant,
/// while you still remember what you meant. A parser that silently mishears
/// "friday" is far more expensive than one that shows its working.
class ChatScreen extends StatefulWidget {
  /// Creates the screen.
  const ChatScreen({required this.service, required this.clock, super.key});

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _entries = <ChatEntry>[];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _entries.add(UserLine(text));
      _busy = true;
    });
    _input.clear();
    _toBottom();

    final result = await widget.service.capture(text);
    if (!mounted) return;

    setState(() {
      _entries.add(PlanCard(result));
      _busy = false;
    });
    _toBottom();
  }

  Future<void> _undo(int index, CaptureResult result) async {
    await widget.service.undoCapture(result.task.id);
    if (!mounted) return;
    setState(() => _entries[index] = PlanCard.undone(result));
  }

  /// Scrolls after the frame that added the entry, not before it.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? const _ChatEmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) => switch (_entries[i]) {
                      UserLine(:final text) => _UserBubble(text: text),
                      PlanCard(:final result, :final undone) => _PlanBubble(
                        result: result,
                        undone: undone,
                        clock: widget.clock,
                        onUndo: () => _undo(i, result),
                      ),
                    },
                  ),
          ),
          _Composer(controller: _input, busy: _busy, onSend: _send),
        ],
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Say what needs doing.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Van will show you the plan before it commits to it.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// The approval card: what Van heard, and what it has scheduled.
class _PlanBubble extends StatelessWidget {
  const _PlanBubble({
    required this.result,
    required this.undone,
    required this.clock,
    required this.onUndo,
  });

  final CaptureResult result;
  final bool undone;
  final Clock clock;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = result.task;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 32),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              task.title,
              style: theme.textTheme.titleMedium?.copyWith(
                decoration: undone ? TextDecoration.lineThrough : null,
              ),
            ),
            if (task.deadline != null) ...[
              const SizedBox(height: 4),
              Text(
                'due ${_when(task.deadline!.toLocal())}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),

            if (undone)
              Text('Removed.', style: theme.textTheme.bodySmall)
            else if (result.sessions.isEmpty)
              Text(
                'Nowhere to put this in the next week.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              for (final session in result.sessions.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        '${_when(session.plannedStart.toLocal())} · '
                        '${session.plannedMinutes} min',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              if (result.sessions.length > 5)
                Text(
                  '+${result.sessions.length - 5} more',
                  style: theme.textTheme.bodySmall,
                ),
              if (result.isPartial) ...[
                const SizedBox(height: 6),
                Text(
                  '${result.shortfallMinutes} min would not fit before the '
                  'deadline.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],

            if (!undone) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Undo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Day and time, or just time when it is today.
  String _when(DateTime local) {
    final now = clock.now().toLocal();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    if (sameDay) return time;
    return '${_weekday(local.weekday)} $time';
  }

  static String _weekday(int day) => const [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ][day - 1];
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'finish the assignment by friday, 2 hours',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: busy ? null : onSend,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
