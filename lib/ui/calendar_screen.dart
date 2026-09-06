import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/settings_screen.dart';
import 'package:van_core/van_core.dart';

/// How much of the plan is on screen at once.
///
/// Four rather than one because the question changes with the horizon. Day is
/// "what does this afternoon look like"; week is "where is there room";
/// month is "am I about to walk into a bad fortnight"; schedule is the list a
/// person would read aloud. A calendar with a single view answers whichever
/// of those its author happened to have in mind.
enum CalendarView {
  /// One day, on a clock.
  day,

  /// Seven days side by side, on a clock.
  week,

  /// A month grid, with each day summarised.
  month,

  /// Everything ahead, in order, as a list.
  schedule
  ;

  /// What the menu calls it.
  String get label => switch (this) {
    CalendarView.day => 'Day',
    CalendarView.week => 'Week',
    CalendarView.month => 'Month',
    CalendarView.schedule => 'Schedule',
  };
}

/// The plan on a calendar: Van's blocks and the user's real events together.
///
/// The Now screen answers "what next"; the task list answers "what is
/// outstanding". Neither answers "where does this actually fit", which is the
/// question a calendar is for - and Van cannot answer it alone, because half
/// of what fills a day was never Van's to schedule.
///
/// **Event titles are drawn here and recorded nowhere.** They come off the
/// device calendar for display and never reach the event log, a notification
/// or the week report; planning turns them into nameless commitments before
/// anything is written down. See `docs/DECISIONS_PENDING.md` D71.
class CalendarScreen extends StatefulWidget {
  /// Creates the screen.
  const CalendarScreen({
    required this.service,
    required this.clock,
    required this.calendars,
    required this.calendarPreferences,
    this.initialView = CalendarView.day,
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

  /// Which view to open on.
  final CalendarView initialView;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  late CalendarView _view = widget.initialView;
  late DateTime _day = _today;
  List<_Item> _items = const [];
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
    // block, a nudge is answered, someone accepts a meeting - so a stale
    // calendar is the default rather than the exception.
    if (state == AppLifecycleState.resumed) inBackground(_load());
  }

  /// The window the current view needs loaded.
  (DateTime, DateTime) get _window => switch (_view) {
    CalendarView.day => (_day, _day.add(const Duration(days: 1))),
    CalendarView.week => (_weekStart, _weekStart.add(const Duration(days: 7))),
    CalendarView.month => (
      _monthGridStart,
      _monthGridStart.add(const Duration(days: 42)),
    ),
    CalendarView.schedule => (_day, _day.add(const Duration(days: 28))),
  };

  DateTime get _weekStart => _day.subtract(Duration(days: _day.weekday - 1));

  /// The Monday the month grid begins on, usually in the previous month.
  DateTime get _monthGridStart {
    final first = DateTime(_day.year, _day.month);
    return first.subtract(Duration(days: first.weekday - 1));
  }

  Future<void> _load() async {
    final (from, to) = _window;
    // A day earlier than the view asks for, so something that began yesterday
    // and runs into the window is not silently missing from it.
    final plan = await widget.service.planBetween(
      from: from.subtract(const Duration(days: 1)).toUtc(),
      to: to.toUtc(),
    );
    if (!mounted) return;
    setState(() {
      _items = _Item.from(plan);
      _loading = false;
    });
  }

  Future<void> _show(DateTime day, {CalendarView? as}) async {
    setState(() {
      _day = DateTime(day.year, day.month, day.day);
      if (as != null) _view = as;
      _loading = true;
    });
    await _load();
  }

  Future<void> _shift(int step) => _show(switch (_view) {
    CalendarView.day => _day.add(Duration(days: step)),
    CalendarView.week => _day.add(Duration(days: 7 * step)),
    CalendarView.month => DateTime(_day.year, _day.month + step),
    CalendarView.schedule => _day.add(Duration(days: 28 * step)),
  });

  Future<void> _switchTo(CalendarView view) async {
    setState(() {
      _view = view;
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
    final now = widget.clock.now().toLocal();

    return Scaffold(
      appBar: AppBar(
        title: Text('${_monthName(_day.month)} ${_day.year}'),
        actions: [
          if (_day != today)
            TextButton(
              onPressed: () => _show(today),
              child: const Text('Today'),
            ),
          PopupMenuButton<CalendarView>(
            initialValue: _view,
            tooltip: 'View',
            icon: const Icon(Icons.calendar_view_day_outlined),
            onSelected: _switchTo,
            itemBuilder: (_) => [
              for (final view in CalendarView.values)
                PopupMenuItem(value: view, child: Text(view.label)),
            ],
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
          _Pager(
            label: _pagerLabel(),
            onBack: () => _shift(-1),
            onForward: () => _shift(1),
          ),
          if (_view == CalendarView.day)
            _WeekStrip(
              start: _weekStart,
              selected: _day,
              today: today,
              onSelect: _show,
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(onRefresh: _load, child: _body(today, now)),
          ),
        ],
      ),
    );
  }

  Widget _body(DateTime today, DateTime now) => switch (_view) {
    CalendarView.day => _Timeline(
      days: [_day],
      items: _items,
      now: _day == today ? now : null,
      onDayTap: _show,
    ),
    CalendarView.week => _Timeline(
      days: [for (var i = 0; i < 7; i++) _weekStart.add(Duration(days: i))],
      items: _items,
      now: now,
      onDayTap: (day) => _show(day, as: CalendarView.day),
      compact: true,
    ),
    CalendarView.month => _MonthGrid(
      start: _monthGridStart,
      month: _day.month,
      today: today,
      selected: _day,
      items: _items,
      onSelect: _show,
      onOpenDay: (day) => _show(day, as: CalendarView.day),
    ),
    CalendarView.schedule => _Schedule(
      from: _day,
      days: 28,
      items: _items,
      today: today,
      onDayTap: (day) => _show(day, as: CalendarView.day),
    ),
  };

  String _pagerLabel() => switch (_view) {
    CalendarView.day => _longDate(_day),
    CalendarView.week =>
      '${_shortDate(_weekStart)} – '
          '${_shortDate(_weekStart.add(const Duration(days: 6)))}',
    CalendarView.month => _monthName(_day.month),
    CalendarView.schedule => 'From ${_shortDate(_day)}',
  };
}

/// Anything that takes up time on the calendar.
///
/// One type for two very different things, because every view has to lay them
/// out together and a screen that reasoned about them separately would drift
/// apart view by view. Which one it is lives on [session]: Van's own blocks
/// have one, calendar events do not.
class _Item {
  const _Item({
    required this.start,
    required this.end,
    required this.title,
    required this.isAllDay,
    required this.blocks,
    this.session,
    this.attendance,
  });

  /// Local start, because every view is a wall clock.
  final DateTime start;

  /// Local end.
  final DateTime end;

  /// What to draw.
  final String title;

  /// Whether the provider marks it all-day.
  final bool isAllDay;

  /// Whether this is time Van will not plan into.
  final bool blocks;

  /// Van's own session, when this is Van's own block.
  final WorkSession? session;

  /// The user's answer to an invitation, for calendar events.
  final Attendance? attendance;

  /// Whether Van planned this rather than merely reading it.
  bool get isVan => session != null;

  /// Everything on [plan], earliest first, with duplicate events collapsed.
  ///
  /// **The duplicates are real and there are a lot of them.** A phone with
  /// several Google accounts on it carries several holiday calendars, so one
  /// public holiday arrives as eight identical all-day entries and fills the
  /// screen with the same word. Two entries with the same name over the same
  /// minutes are one event as far as a person reading a day is concerned.
  ///
  /// Collapsed here rather than in the planner because the planner already
  /// does not care: `FreeSlotFinder` merges overlapping commitments, so eight
  /// copies of a holiday have always cost exactly what one copy costs. This is
  /// a reading problem, and it is fixed where the reading happens.
  ///
  /// Van's own blocks are never collapsed. Two identical sessions are two
  /// pieces of work, and hiding one would hide half an hour of it.
  static List<_Item> from(DayPlan plan) {
    final seen = <String>{};
    return [
      for (final item in _all(plan))
        if (item.isVan ||
            seen.add(
              '${item.title}|${item.start.toIso8601String()}'
              '|${item.end.toIso8601String()}',
            ))
          item,
    ];
  }

  static List<_Item> _all(DayPlan plan) => [
    for (final block in plan.blocks)
      _Item(
        start: block.session.plannedStart.toLocal(),
        end: block.session.plannedEnd.toLocal(),
        title: block.task.title,
        isAllDay: false,
        blocks: true,
        session: block.session,
      ),
    for (final event in plan.events)
      _Item(
        start: event.start.toLocal(),
        end: event.end.toLocal(),
        // Untitled events are ordinary. The placeholder is Van's, not a
        // string invented on the platform side.
        title: event.title.isEmpty ? '(no title)' : event.title,
        isAllDay: event.isAllDay,
        blocks: event.blocks,
        attendance: event.attendance,
      ),
  ]..sort((a, b) => a.start.compareTo(b.start));

  /// Whether any part of this falls on the local day beginning at [day].
  bool isOn(DateTime day) {
    final dayEnd = day.add(const Duration(days: 1));
    return start.isBefore(dayEnd) && day.isBefore(end);
  }
}

/// Back, forward, and what is currently being shown.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.label,
    required this.onBack,
    required this.onForward,
  });

  final String label;
  final Future<void> Function() onBack;
  final Future<void> Function() onForward;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        icon: const Icon(Icons.chevron_left),
        onPressed: onBack,
        tooltip: 'Back',
      ),
      Expanded(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        onPressed: onForward,
        tooltip: 'Forward',
      ),
    ],
  );
}

/// The seven days of the week the shown day belongs to.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.start,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final DateTime start;
  final DateTime selected;
  final DateTime today;
  final Future<void> Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _DayChip(
              day: start.add(Duration(days: i)),
              isSelected: start.add(Duration(days: i)) == selected,
              isToday: start.add(Duration(days: i)) == today,
              onTap: onSelect,
            ),
          ),
      ],
    ),
  );
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
        padding: const EdgeInsets.symmetric(vertical: 4),
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

/// One or seven days, on a clock.
///
/// The same widget for both views because the only difference is how many
/// columns the hours are divided into, and two implementations of a timeline
/// would eventually place the same block at two different heights.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.days,
    required this.items,
    required this.onDayTap,
    this.now,
    this.compact = false,
  });

  /// Local midnights, left to right.
  final List<DateTime> days;

  /// Everything loaded. Filtered per column here rather than by the caller.
  final List<_Item> items;

  /// Local now, drawn as a line when it falls inside a column.
  final DateTime? now;

  /// Opens one day.
  final Future<void> Function(DateTime) onDayTap;

  /// Whether this is the seven-column form, which has no room for detail.
  final bool compact;

  static const _gutter = 46.0;

  double get _hourHeight => compact ? 52 : 76;

  @override
  Widget build(BuildContext context) {
    final onDays = [
      for (final item in items)
        if (days.any(item.isOn)) item,
    ];

    if (onDays.isEmpty) return const _Empty();

    final allDay = [
      for (final item in onDays)
        if (item.isAllDay) item,
    ];
    final timed = [
      for (final item in onDays)
        if (!item.isAllDay) item,
    ];
    final (first, last) = _bounds(timed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (days.length > 1) _ColumnHeadings(days: days, onTap: onDayTap),
        if (allDay.isNotEmpty)
          _AllDayStrip(days: days, items: allDay, gutter: _gutter),
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: LayoutBuilder(
              builder: (context, box) {
                final width = (box.maxWidth - _gutter - 6) / days.length;
                return SizedBox(
                  height: (last - first) * _hourHeight + 20,
                  child: Stack(
                    children: [
                      for (var hour = first; hour < last; hour++)
                        Positioned(
                          top: (hour - first) * _hourHeight,
                          left: 0,
                          right: 0,
                          child: _HourLine(
                            hour: hour,
                            height: _hourHeight,
                            gutter: _gutter,
                          ),
                        ),
                      for (var column = 0; column < days.length; column++)
                        ..._column(
                          day: days[column],
                          left: _gutter + column * width,
                          width: width,
                          firstHour: first,
                          timed: timed,
                        ),
                      ?_nowLine(first, last, width),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _column({
    required DateTime day,
    required double left,
    required double width,
    required int firstHour,
    required List<_Item> timed,
  }) {
    final onThisDay = [
      for (final item in timed)
        if (item.isOn(day)) item,
    ];

    // Events first, then Van's blocks on top. A block drawn over an event it
    // overlaps is a planning mistake, and it should look like one rather than
    // hide underneath.
    final ordered = [
      for (final item in onThisDay)
        if (!item.isVan) item,
      for (final item in onThisDay)
        if (item.isVan) item,
    ];

    return [
      for (final item in ordered)
        if (_place(item, day, firstHour) case final box?)
          Positioned(
            top: box.top,
            height: box.height,
            left: left + (item.isVan ? 6 : 2),
            width: width - 8,
            child: _ItemCard(item: item, compact: compact),
          ),
    ];
  }

  Widget? _nowLine(int firstHour, int lastHour, double width) {
    final at = now;
    if (at == null) return null;
    final column = days.indexWhere(
      (day) => at.isAfter(day) && at.isBefore(day.add(const Duration(days: 1))),
    );
    if (column < 0) return null;
    if (at.hour < firstHour || at.hour >= lastHour) return null;

    return Positioned(
      top: (_minutes(at) - firstHour * 60) / 60 * _hourHeight,
      left: _gutter + column * width - 4,
      width: width + 4,
      child: const _NowLine(),
    );
  }

  /// The first and last hour to draw.
  ///
  /// Starts from the waking window rather than midnight - eight empty hours
  /// of scrolling before the day begins is what makes calendars unreadable -
  /// but always widens far enough to contain everything shown, so nothing can
  /// be scheduled somewhere this screen cannot show it.
  (int, int) _bounds(List<_Item> timed) {
    var first = 7;
    var last = 23;
    for (final item in timed) {
      for (final day in days) {
        if (!item.isOn(day)) continue;
        final dayEnd = day.add(const Duration(days: 1));
        final from = item.start.isBefore(day) ? day : item.start;
        final to = item.end.isAfter(dayEnd) ? dayEnd : item.end;

        if (from.hour < first) first = from.hour;
        final endHour = !to.isBefore(dayEnd)
            ? 24
            : to.hour + (to.minute > 0 ? 1 : 0);
        if (endHour > last) last = endHour;
      }
    }
    return (first, last > 24 ? 24 : last);
  }

  /// Where an item sits in [day]'s column, or null when none of it is there.
  ({double top, double height})? _place(
    _Item item,
    DateTime day,
    int firstHour,
  ) {
    final dayEnd = day.add(const Duration(days: 1));
    final from = item.start.isBefore(day) ? day : item.start;
    final to = item.end.isAfter(dayEnd) ? dayEnd : item.end;
    if (!from.isBefore(to)) return null;

    final top = (_minutes(from) - firstHour * 60) / 60 * _hourHeight;
    final height = to.difference(from).inMinutes / 60 * _hourHeight;
    // A ten-minute block still has to be readable.
    return (top: top, height: height < 24 ? 24 : height);
  }

  static int _minutes(DateTime local) => local.hour * 60 + local.minute;
}

/// The day names above a week's columns.
class _ColumnHeadings extends StatelessWidget {
  const _ColumnHeadings({required this.days, required this.onTap});

  final List<DateTime> days;
  final Future<void> Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: _Timeline._gutter),
        for (final day in days)
          Expanded(
            child: InkWell(
              onTap: () => onTap(day),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_weekdayLetter(day)}${day.day}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// All-day entries, above the clock rather than on it.
///
/// A birthday does not happen at a time, and stretching one down the whole
/// timeline would say it occupies the day - which for most all-day entries is
/// exactly wrong, and is why Van does not block them out either.
class _AllDayStrip extends StatelessWidget {
  const _AllDayStrip({
    required this.days,
    required this.items,
    required this.gutter,
  });

  final List<DateTime> days;
  final List<_Item> items;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutter,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, top: 4),
              child: Text(
                'all day',
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final day in days)
            Expanded(
              child: Column(
                children: [
                  for (final item in items)
                    if (item.isOn(day))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2, right: 4),
                        child: SizedBox(
                          height: 22,
                          child: _ItemCard(item: item, compact: true),
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HourLine extends StatelessWidget {
  const _HourLine({
    required this.hour,
    required this.height,
    required this.gutter,
  });

  final int hour;
  final double height;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutter,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, top: 2),
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

/// One block or event, wherever it is drawn.
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.compact = false});

  final _Item item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;
    final session = item.session;

    // Van's blocks are coloured by what happened to them; a day of identical
    // boxes says nothing about whether it went well. Calendar events are
    // deliberately quieter - they are context for the plan, not the plan.
    final (background, foreground, outline) = switch (session?.status) {
      SessionStatus.started => (colours.primary, colours.onPrimary, null),
      SessionStatus.completed || SessionStatus.partial => (
        colours.tertiaryContainer,
        colours.onTertiaryContainer,
        null,
      ),
      SessionStatus.skipped || SessionStatus.rescheduled => (
        colours.surfaceContainerHigh,
        colours.onSurfaceVariant,
        null,
      ),
      SessionStatus.planned => (
        colours.primaryContainer,
        colours.onPrimaryContainer,
        null,
      ),
      // Not one of Van's. A blocking event is filled; one marked free or
      // declined is outlined instead, because it is on the calendar without
      // taking the time - which is exactly what the planner concluded about
      // it, and the two must not appear to disagree.
      null =>
        item.blocks
            ? (colours.surfaceContainerHighest, colours.onSurface, null)
            : (Colors.transparent, colours.onSurfaceVariant, colours.outline),
    };

    final struck =
        session?.status == SessionStatus.skipped ||
        session?.status == SessionStatus.rescheduled ||
        item.attendance == Attendance.declined;

    final title = Text(
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelLarge)
          ?.copyWith(
            color: foreground,
            decoration: struck ? TextDecoration.lineThrough : null,
          ),
    );

    final detail = Text(
      item.isAllDay
          ? 'all day'
          : '${_time(item.start)}'
                '${session == null ? '' : '  ·  ${session.plannedMinutes}m'}'
                '${_suffix(item)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(color: foreground),
    );

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: outline == null ? null : Border.all(color: outline),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 10, vertical: 3),
      // A card has room for the title, or for the title and the detail, and
      // which one depends on how long the thing it represents is. Drawing
      // both regardless is how a twenty-minute block overflows its own box.
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, box) => box.maxHeight < 40 || compact
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

  static String _suffix(_Item item) => switch (item.session?.status) {
    SessionStatus.started => '  ·  in progress',
    SessionStatus.completed => '  ·  done',
    SessionStatus.partial => '  ·  part done',
    SessionStatus.skipped => '  ·  skipped',
    SessionStatus.rescheduled => '  ·  moved',
    SessionStatus.planned => '',
    null => item.blocks ? '' : '  ·  free',
  };
}

/// A month at a glance, with one day read out underneath it.
///
/// The grid alone was the first version and it was unreadable: thirty cells
/// of identical grey bars say a day is busy without saying with what, which
/// is the one thing worth knowing. There is no room in a seventh of a phone
/// screen for a name, so the grid answers "which days are full" in dots and
/// the day you tap is listed in full below it.
///
/// Tapping a day therefore stays in the month rather than jumping to the day
/// view - the whole point is comparing a day against the month around it. The
/// heading above the list opens the day properly.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.start,
    required this.month,
    required this.today,
    required this.selected,
    required this.items,
    required this.onSelect,
    required this.onOpenDay,
  });

  /// The Monday the grid begins on, usually in the previous month.
  final DateTime start;

  /// The month being shown, so days either side can be dimmed.
  final int month;

  /// Local today, for the highlight.
  final DateTime today;

  /// The day listed underneath.
  final DateTime selected;

  /// Everything loaded across the grid.
  final List<_Item> items;

  /// Selects a day without leaving the month.
  final Future<void> Function(DateTime) onSelect;

  /// Opens a day in the day view.
  final Future<void> Function(DateTime) onOpenDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSelected = [
      for (final item in items)
        if (item.isOn(selected)) item,
    ];

    return Column(
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  _weekdayLetter(start.add(Duration(days: i))),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        // Six rows of cells and then the day itself. The split is deliberate:
        // the grid only has to be scannable, and the list is where the reading
        // actually happens.
        Expanded(
          flex: 5,
          child: Column(
            children: [
              for (var week = 0; week < 6; week++)
                Expanded(
                  child: Row(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Expanded(
                          child: _MonthCell(
                            day: start.add(Duration(days: week * 7 + d)),
                            month: month,
                            today: today,
                            selected: selected,
                            items: items,
                            onTap: onSelect,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 4,
          child: _DayList(
            day: selected,
            items: onSelected,
            isToday: selected == today,
            onOpen: onOpenDay,
          ),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.month,
    required this.today,
    required this.selected,
    required this.items,
    required this.onTap,
  });

  final DateTime day;
  final int month;
  final DateTime today;
  final DateTime selected;
  final List<_Item> items;
  final Future<void> Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;
    final onThisDay = [
      for (final item in items)
        if (item.isOn(day)) item,
    ];
    final isToday = day == today;
    final isSelected = day == selected;
    final outside = day.month != month;

    // Van's own work counted separately from everyone else's claims on the
    // day, because "three of my blocks" and "three of their meetings" are
    // opposite kinds of full.
    final mine = onThisDay.where((item) => item.isVan).length;
    final theirs = onThisDay.length - mine;

    return InkWell(
      onTap: () => onTap(day),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? colours.primary : null,
          border: isToday && !isSelected
              ? Border.all(color: colours.primary)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? colours.onPrimary
                    : outside
                    ? colours.onSurfaceVariant.withValues(alpha: 0.45)
                    : null,
                fontWeight: isToday || isSelected ? FontWeight.bold : null,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < (mine > 3 ? 3 : mine); i++)
                    _Dot(
                      colour: isSelected ? colours.onPrimary : colours.primary,
                    ),
                  for (var i = 0; i < (theirs > 3 ? 3 : theirs); i++)
                    _Dot(
                      colour: isSelected
                          ? colours.onPrimary.withValues(alpha: 0.55)
                          : colours.onSurfaceVariant.withValues(alpha: 0.55),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 5,
    height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
  );
}

/// One day, read out in full under the month grid.
class _DayList extends StatelessWidget {
  const _DayList({
    required this.day,
    required this.items,
    required this.isToday,
    required this.onOpen,
  });

  final DateTime day;
  final List<_Item> items;
  final bool isToday;
  final Future<void> Function(DateTime) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => onOpen(day),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isToday ? 'Today · ${_longDate(day)}' : _longDate(day),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isToday ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Nothing on this day.',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final item in items) _ItemRow(item: item),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A time down the left and the thing itself beside it.
///
/// Shared by the schedule view and the month's day list so the two cannot
/// drift into showing the same day differently.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              item.isAllDay ? 'all day' : _time(item.start),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: _ItemCard(item: item)),
        ],
      ),
    );
  }
}

/// Everything ahead, in the order it will happen.
///
/// The view a person would read aloud, and the only one that needs no sense
/// of scale to be understood. Days with nothing on them are skipped rather
/// than drawn empty: a list of blank days is scrolling, not information.
class _Schedule extends StatelessWidget {
  const _Schedule({
    required this.from,
    required this.days,
    required this.items,
    required this.today,
    required this.onDayTap,
  });

  final DateTime from;
  final int days;
  final List<_Item> items;
  final DateTime today;
  final Future<void> Function(DateTime) onDayTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];

    for (var i = 0; i < days; i++) {
      final day = from.add(Duration(days: i));
      final onThisDay = [
        for (final item in items)
          if (item.isOn(day)) item,
      ];
      if (onThisDay.isEmpty) continue;

      rows
        ..add(
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: InkWell(
              onTap: () => onDayTap(day),
              child: Text(
                day == today ? 'Today · ${_longDate(day)}' : _longDate(day),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: day == today ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ),
        )
        ..addAll([for (final item in onThisDay) _ItemRow(item: item)]);
    }

    if (rows.isEmpty) return const _Empty();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: rows,
    );
  }
}

/// Nothing on the stretch being shown.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 32),
      children: [
        Icon(
          Icons.event_available_outlined,
          size: 48,
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'Nothing here.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Blocks Van plans appear here, alongside whatever is already on '
          'your calendars.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Where the day has got to.
class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.error;
    return Row(
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
}

String _time(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}';

String _weekdayLetter(DateTime day) =>
    const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1];

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _monthNames = [
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

String _monthName(int month) => _monthNames[month - 1];

String _shortDate(DateTime day) =>
    '${day.day} ${_monthName(day.month).substring(0, 3)}';

String _longDate(DateTime day) =>
    '${_weekdayNames[day.weekday - 1]} ${day.day} '
    '${_monthName(day.month).substring(0, 3)}';
