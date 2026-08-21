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

/// Van opening a conversation about a block that did not start.
class StallPrompt extends ChatEntry {
  /// Creates a prompt.
  const StallPrompt({required this.session, required this.task});

  /// The block in question.
  final WorkSession session;

  /// The work it belongs to.
  final Task task;
}

/// Van's answer to a reason: a way out, awaiting a yes.
class ProposalCard extends ChatEntry {
  /// Creates a card.
  const ProposalCard(this.outcome, {this.reason, this.settled});

  /// What Van proposes, and whether the domain would allow it.
  final NegotiationOutcome outcome;

  /// What the user said, which the level depended on.
  final String? reason;

  /// What happened once the user answered, or null while it is still open.
  final String? settled;

  /// A copy of this card, closed with [note].
  ProposalCard closed(String note) =>
      ProposalCard(outcome, reason: reason, settled: note);
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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _entries = <ChatEntry>[];
  bool _busy = false;

  /// The block the next typed line is about, or null when typing captures a
  /// new task instead. Chat has exactly two modes and the composer says which.
  String? _answering;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_askAboutStall());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_askAboutStall());
  }

  /// Opens the conversation if a block is sitting there unstarted.
  ///
  /// Only ever asks once per block. Van reopening the same question every time
  /// the app comes back would be the notification-fatigue problem wearing a
  /// different hat.
  Future<void> _askAboutStall() async {
    if (_answering != null) return;
    final stalled = await widget.service.stalled();
    if (stalled == null || !mounted) return;

    final alreadyAsked = _entries.whereType<StallPrompt>().any(
      (p) => p.session.id == stalled.session.id,
    );
    if (alreadyAsked) return;

    setState(() {
      _entries.add(
        StallPrompt(session: stalled.session, task: stalled.task),
      );
      _answering = stalled.session.id;
    });
    _toBottom();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    final answering = _answering;
    setState(() {
      _entries.add(UserLine(text));
      _busy = true;
    });
    _input.clear();
    _toBottom();

    final ChatEntry entry;
    try {
      entry = answering == null
          ? PlanCard(await widget.service.capture(text))
          : await _proposalFor(answering, text);
    } on Object {
      // The composer was cleared and `_busy` set before the await, so an
      // exception escaping here used to take the typed sentence with it and
      // leave the box disabled for good - the worst shape a failure can have
      // in an app whose promise is that telling it something is enough.
      //
      // Put the words back where the user can see them and let them try
      // again. The transcript line comes out too, so the same sentence is
      // never showing in two places at once.
      if (!mounted) return;
      setState(() {
        _entries.removeLast();
        _busy = false;
      });
      _input.text = text;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('That did not go through - try again')),
        );
      return;
    }
    if (!mounted) return;

    setState(() {
      _entries.add(entry);
      _busy = false;
    });
    _toBottom();
  }

  Future<ChatEntry> _proposalFor(String sessionId, String reason) async {
    final outcome = await widget.service.negotiate(sessionId, reason: reason);
    // The block was started or swept while they were typing. Say so rather
    // than proposing a change to something that has already moved on.
    if (outcome == null) {
      return ProposalCard(
        NegotiationOutcome(
          session: WorkSession(
            id: sessionId,
            taskId: '',
            plannedStart: widget.clock.now(),
            plannedMinutes: 1,
          ),
          task: Task(id: '', title: '', createdAt: widget.clock.now()),
          proposal: const NegotiationProposal(
            action: NegotiationAction.hold,
            message: 'That block has already moved on.',
          ),
          level: InterventionLevel.l0Gentle,
        ),
        settled: 'Nothing to do.',
      );
    }
    return ProposalCard(outcome, reason: reason);
  }

  Future<void> _accept(int index, ProposalCard card) async {
    final next = await widget.service.applyNegotiation(
      card.outcome.session.id,
      card.outcome.proposal,
      reason: card.reason,
    );
    if (!mounted) return;

    // Refusal is checked first, and has to be. The old shape asked about the
    // action before the outcome, so a release that the domain turned down -
    // because the block had been started while the card sat on screen - still
    // reported "Let go for today" over work that was running.
    final note = next == null
        ? 'That block has already moved on.'
        : switch (card.outcome.proposal.action) {
            NegotiationAction.hold => 'Left as it is.',
            NegotiationAction.release => 'Let go for today.',
            _ =>
              'Moved to ${_clockTime(next.plannedStart.toLocal())}, '
                  '${next.plannedMinutes} min.',
          };

    setState(() {
      _entries[index] = card.closed(note);
      _answering = null;
    });
    _toBottom();
  }

  void _declineProposal(int index, ProposalCard card) {
    setState(() {
      _entries[index] = card.closed('Left as it is.');
      _answering = null;
    });
  }

  static String _clockTime(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

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
                      StallPrompt(:final session, :final task) => _StallBubble(
                        session: session,
                        task: task,
                        now: widget.clock.now(),
                      ),
                      final ProposalCard card => _ProposalBubble(
                        card: card,
                        onAccept: () => _accept(i, card),
                        onDecline: () => _declineProposal(i, card),
                      ),
                    },
                  ),
          ),
          _Composer(
            controller: _input,
            busy: _busy,
            answering: _answering != null,
            onSend: _send,
          ),
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
    required this.answering,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;

  /// Whether what gets typed is an answer about a stalled block rather than a
  /// new task. The hint is the only thing telling the user which, so it is
  /// not decoration.
  final bool answering;
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
                decoration: InputDecoration(
                  hintText: answering
                      ? "what's in the way?"
                      : 'finish the assignment by friday, 2 hours',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
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

/// Van asking about a block that did not start.
class _StallBubble extends StatelessWidget {
  const _StallBubble({
    required this.session,
    required this.task,
    required this.now,
  });

  final WorkSession session;
  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final late = session.minutesLate(now);

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
            Text(task.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              late < 1
                  ? '${session.plannedMinutes} minutes, due now. Not started.'
                  : 'Due $late min ago. Not started.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text("What's in the way?", style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Van's proposed way out, awaiting a yes.
class _ProposalBubble extends StatelessWidget {
  const _ProposalBubble({
    required this.card,
    required this.onAccept,
    required this.onDecline,
  });

  final ProposalCard card;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposal = card.outcome.proposal;
    final settled = card.settled;

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
            Text(proposal.message, style: theme.textTheme.bodyMedium),
            if (settled != null) ...[
              const SizedBox(height: 8),
              Text(settled, style: theme.textTheme.bodySmall),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onDecline,
                    child: const Text('Leave it'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: onAccept,
                    child: Text(_acceptLabel(proposal)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Names what the button will actually do, rather than saying "OK".
  static String _acceptLabel(NegotiationProposal proposal) =>
      switch (proposal.action) {
        NegotiationAction.hold => 'Keep it',
        NegotiationAction.shrink => 'Shrink it',
        NegotiationAction.defer => 'Move it',
        NegotiationAction.release => 'Drop it',
      };
}
