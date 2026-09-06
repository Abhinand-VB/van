import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/settings_screen.dart';
import 'package:van_core/van_core.dart';

/// One day of the plan, drawn on a clock rather than listed.
///
/// The Now screen answers "what next"; the task list answers "what is
/// outstanding". Neither answers "where does this actually fit", which is the
/// question a timeline is for - and it is the question the device calendar
/// made worth asking, because Van's blocks are now placed around commitments
/// the user cannot see anywhere in this app.
///
/// **The shaded bands have no names and cannot be given any.** Van never reads
/// an event title, so all this can honestly draw for a meeting is its shape.
/// That is a deliberate trade recorded in `docs/DECISIONS_PENDING.md` D70:
/// what is never read cannot leak into an append-only log.
class CalendarScreen extends StatefulWidget {
  /// Creates the screen.
  const CalendarScreen({
    required this.service,
    required this.clock,
    required this.calendars,
    required this.calendarPreferences,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Handed to the calendar settings page, reached from this screen's app bar.
  final Calendars calendars;

  /// Which calendars planning and this screen may see.
  final CalendarPreferences calendarPreferences;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  late DateTime _day = _today;
  DayPlan _plan = const DayPlan();
  bool _loading = true;

  /// The local date the device is on, taken from the injected clock rather
  /// than from ambient time so this screen is testable at any instant.
  DateTime get _today {
    final now = widget.clock.now().toLocal();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inBackground(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The plan changes while this screen is not looking - a sweep moves a
    // block, a nudge is answered - so a stale timeline is the default rather
    // than the exception.
    if (state == AppLifecycleState.resumed) inBackground(_load());
  }

  Future<void> _load() async {
    final from = _day.toUtc();
    final to = _day.add(const Duration(days: 1)).toUtc();
    final plan = await widget.service.day(from: from, to: to);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  Future<void> _show(DateTime day) async {
    setState(() {
      _day = day;
      _loading = true;
    });
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          calendars: widget.calendars,
          preferences: widget.calendarPreferences,
        ),
      ),
    );
    // Excluding a calendar changes what is drawn here as well as what is
    // planned around.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final isToday = _day == today;

    return Scaffold(
      appBar: AppBar(
        title: Text(_monthAndDay(_day)),
        actions: [
          if (!isToday)
            TextButton(
              onPressed: () => _show(today),
              child: const Text('Today'),
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _openSettings,
            tooltip: 'Calendars',
          ),
        ],
      ),
      body: Column(
        children: [
          _WeekStrip(
            selected: _day,
            today: today,
            onSelect: _show,
            onShiftWeek: (weeks) => _show(_day.add(Duration(days: 7 * weeks))),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _DayTimeline(
                      day: _day,
                      plan: _plan,
                      now: isToday ? widget.clock.now().toLocal() : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The seven days around the one being shown.
///
/// A week rather than a month grid on purpose. Van plans a week ahead and no
/// further - `_freeSlots` looks seven days out - so a month view would be
/// mostly empty squares promising a planning horizon that does not exist.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.today,
    required this.onSelect,
    required this.onShiftWeek,
  });

  final DateTime selected;
  final DateTime today;
  final Future<void> Function(DateTime) onSelect;
  final Future<void> Function(int) onShiftWeek;

  @override
  Widget build(BuildContext context) {
    // Monday-first, so the week reads the way a diary does.
    final start = selected.subtract(Duration(days: selected.weekday - 1));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onShiftWeek(-1),
            tooltip: 'Previous week',
          ),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayChip(
                day: start.add(Duration(days: i)),
                isSelected: start.add(Duration(days: i)) == selected,
                isToday: start.add(Duration(days: i)) == today,
                onTap: onSelect,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onShiftWeek(1),
            tooltip: 'Next week',
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final Future<void> Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;

    return InkWell(
      onTap: () => onTap(day),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(
              _weekdayLetter(day),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colours.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? colours.primary : Colors.transparent,
                border: isToday && !isSelected
                    ? Border.all(color: colours.primary)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isSelected ? colours.onPrimary : null,
                  fontWeight: isToday ? FontWeight.bold : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The day itself, on a clock.
class _DayTimeline extends StatelessWidget {
  const _DayTimeline({required this.day, required this.plan, this.now});

  /// Local midnight of the day being drawn.
  final DateTime day;

  /// What is on it.
  final DayPlan plan;

  /// Local now, when the day being drawn is today. Null otherwise.
  final DateTime? now;

  /// One hour of the day, in logical pixels. Wide enough that a 25-minute
  /// block still has room for a title.
  static const _hourHeight = 76.0;

  /// The width given to the hour labels down the left.
  static const _gutter = 52.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (first, last) = _bounds();
    final height = (last - first) * _hourHeight;

    if (plan.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing on this day.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Blocks Van plans will appear here, around whatever your '
            'calendar already claims.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    return SingleChildScrollView(
      // Always scrollable so pull-to-refresh works on a short day.
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: height + 24,
        child: Stack(
          children: [
            for (var hour = first; hour < last; hour++)
              Positioned(
                top: (hour - first) * _hourHeight,
                left: 0,
                right: 0,
                child: _HourLine(hour: hour, height: _hourHeight),
              ),

            // Painted before the blocks: a session drawn on top of a band it
            // overlaps is a planning mistake, and it should look like one.
            for (final busy in plan.busy)
              if (_place(busy.start.toLocal(), busy.end.toLocal(), first)
                  case final box?)
                Positioned(
                  top: box.top,
                  height: box.height,
                  left: _gutter,
                  right: 8,
                  child: const _BusyBand(),
                ),

            for (final block in plan.blocks)
              if (_place(
                    block.session.plannedStart.toLocal(),
                    block.session.plannedEnd.toLocal(),
                    first,
                  )
                  case final box?)
                Positioned(
                  top: box.top,
                  height: box.height,
                  left: _gutter + 10,
                  right: 16,
                  child: _BlockCard(
                    session: block.session,
                    task: block.task,
                  ),
                ),

            if (now case final at?)
              if (at.hour >= first && at.hour < last)
                Positioned(
                  top: (_minutes(at) - first * 60) / 60 * _hourHeight,
                  left: _gutter - 6,
                  right: 0,
                  child: _NowLine(colour: theme.colorScheme.error),
                ),
          ],
        ),
      ),
    );
  }

  /// The first and last hour to draw.
  ///
  /// Starts from the waking window rather than midnight - eight empty hours
  /// of scrolling before the day begins is what makes calendar apps
  /// unreadable - but always widens far enough to contain everything on the
  /// day, so nothing can be scheduled somewhere this screen cannot show it.
  (int, int) _bounds() {
    var first = 7;
    var last = 23;
    for (final at in [
      for (final block in plan.blocks) ...[
        block.session.plannedStart.toLocal(),
        block.session.plannedEnd.toLocal(),
      ],
      for (final busy in plan.busy) ...[
        busy.start.toLocal(),
        busy.end.toLocal(),
      ],
    ]) {
      if (!at.isAfter(day)) {
        first = 0;
        continue;
      }
      if (at.difference(day) >= const Duration(days: 1)) {
        last = 24;
        continue;
      }
      if (at.hour < first) first = at.hour;
      if (at.hour >= last) last = at.hour + 1;
    }
    return (first, last > 24 ? 24 : last);
  }

  /// Where a span sits on the timeline, or null when none of it is on this
  /// day.
  ({double top, double height})? _place(
    DateTime start,
    DateTime end,
    int firstHour,
  ) {
    final dayEnd = day.add(const Duration(days: 1));
    final from = start.isBefore(day) ? day : start;
    final to = end.isAfter(dayEnd) ? dayEnd : end;
    if (!from.isBefore(to)) return null;

    final top = (_minutes(from) - firstHour * 60) / 60 * _hourHeight;
    final height = to.difference(from).inMinutes / 60 * _hourHeight;
    // A ten-minute block still has to be tappable and readable.
    return (top: top, height: height < 26 ? 26 : height);
  }

  static int _minutes(DateTime local) => local.hour * 60 + local.minute;
}

class _HourLine extends StatelessWidget {
  const _HourLine({required this.hour, required this.height});

  final int hour;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _DayTimeline._gutter,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Divider(height: 1, color: theme.dividerColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Time the device calendar has already claimed.
///
/// Says "Busy" and nothing else, because that is genuinely all Van knows. It
/// is not a placeholder for a title that failed to load.
class _BusyBand extends StatelessWidget {
  const _BusyBand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      alignment: Alignment.topLeft,
      child: Text(
        'Busy',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One of Van's own blocks.
class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.session, required this.task});

  final WorkSession session;
  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;

    // Status is the only thing worth colouring: a day of grey boxes says
    // nothing about whether it went well.
    final (background, foreground) = switch (session.status) {
      SessionStatus.started => (colours.primary, colours.onPrimary),
      SessionStatus.completed || SessionStatus.partial => (
        colours.tertiaryContainer,
        colours.onTertiaryContainer,
      ),
      SessionStatus.skipped || SessionStatus.rescheduled => (
        colours.surfaceContainerHigh,
        colours.onSurfaceVariant,
      ),
      SessionStatus.planned => (
        colours.primaryContainer,
        colours.onPrimaryContainer,
      ),
    };

    final spent =
        session.status == SessionStatus.skipped ||
        session.status == SessionStatus.rescheduled;

    final title = Text(
      task.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelLarge?.copyWith(
        color: foreground,
        decoration: spent ? TextDecoration.lineThrough : null,
      ),
    );
    final detail = Text(
      '${_time(session.plannedStart.toLocal())}'
      '  ·  ${session.plannedMinutes}m'
      '${_suffix(session.status)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(color: foreground),
    );

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      // A short block has room for the title or for the title and the time,
      // and which one it is depends on the block's own length. Drawing both
      // regardless is how a twenty-minute block ends up overflowing its own
      // box - the card has to fit the time it represents, not the other way
      // round.
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, box) => box.maxHeight < 44
              ? Align(alignment: Alignment.centerLeft, child: title)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [title, detail],
                ),
        ),
      ),
    );
  }

  static String _suffix(SessionStatus status) => switch (status) {
    SessionStatus.started => '  ·  in progress',
    SessionStatus.completed => '  ·  done',
    SessionStatus.partial => '  ·  part done',
    SessionStatus.skipped => '  ·  skipped',
    SessionStatus.rescheduled => '  ·  moved',
    SessionStatus.planned => '',
  };
}

/// Where the day has got to.
class _NowLine extends StatelessWidget {
  const _NowLine({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      ),
      Expanded(child: Container(height: 1.5, color: colour)),
    ],
  );
}

String _time(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}';

String _weekdayLetter(DateTime day) =>
    const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1];

String _monthAndDay(DateTime day) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[day.month - 1]} ${day.year}';
}
