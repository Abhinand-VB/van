import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/settings_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van/ui/calendar_screen.dart';
import 'package:van/ui/shell.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_calendars.dart';
import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeCalendars calendars;
  late FakeNotifications notifications;
  late CalendarPreferences preferences;
  late SessionRepo sessions;
  late TaskRepo tasks;
  late VanService service;
  late FakeClock clock;

  /// Local noon on the device running the test, expressed in UTC.
  ///
  /// The screen draws in local time because that is what a person reads a
  /// calendar in, so the fixture has to be built the same way or the assertion
  /// only holds in the timezone it was written in.
  final today = DateTime(2026, 8, 19, 12);

  DateTime localAt(int hour, [int minute = 0]) =>
      DateTime(2026, 8, 19, hour, minute);

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(today.toUtc());
    calendars = FakeCalendars();
    notifications = FakeNotifications();
    preferences = CalendarPreferences(SettingsRepo(db));
    sessions = SessionRepo(db);
    tasks = TaskRepo(db);

    final events = EventRepo(db, clock);
    service = VanService(
      tasks: tasks,
      sessions: sessions,
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
      notifications: notifications,
      calendars: calendars,
      calendarPreferences: preferences,
      templates: NudgeTemplates.fromJson(
        File('assets/nudge_templates/templates.json').readAsStringSync(),
      ),
      prompts: testPrompts(),
      clock: clock,
      ids: SequentialIds('x'),
    );
  });

  tearDown(() async => db.close());

  Future<void> plan({
    required String title,
    required DateTime start,
    int minutes = 60,
    SessionStatus status = SessionStatus.planned,
  }) async {
    final task = Task(
      id: 't-$title',
      title: title,
      createdAt: today.toUtc(),
      estimatedMinutes: minutes,
      status: TaskStatus.active,
      source: TaskSource.quickAdd,
    );
    await tasks.save(task);
    await sessions.save(
      WorkSession(
        id: 's-$title',
        taskId: task.id,
        plannedStart: start.toUtc(),
        plannedMinutes: minutes,
        status: status,
      ),
    );
  }

  void event(
    DateTime from,
    DateTime to, {
    String title = 'Standup with Priya',
    bool isBusy = true,
    bool isAllDay = false,
    String calendarId = 'work',
    Attendance attendance = Attendance.none,
  }) {
    calendars
      ..granted = true
      ..entries.add(
        CalendarEntry(
          calendarId: calendarId,
          start: from.toUtc(),
          end: to.toUtc(),
          title: title,
          isBusy: isBusy,
          isAllDay: isAllDay,
          attendance: attendance,
        ),
      );
  }

  Future<void> show(
    WidgetTester tester, {
    CalendarView view = CalendarView.day,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          service: service,
          clock: clock,
          calendars: calendars,
          calendarPreferences: preferences,
          initialView: view,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Switches view through the app bar menu, the way a user does.
  Future<void> switchTo(WidgetTester tester, CalendarView view) async {
    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(view.label).last);
    await tester.pumpAndSettle();
  }

  group('the day', () {
    testWidgets('opens on today', (tester) async {
      await show(tester);

      expect(find.text('August 2026'), findsOneWidget);
      // Already on today, so there is nothing to go back to.
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('an empty day says so rather than showing a bare grid', (
      tester,
    ) async {
      await show(tester);

      expect(find.text('Nothing here.'), findsOneWidget);
    });

    testWidgets('a planned block appears with its time', (tester) async {
      await plan(title: 'Write the report', start: localAt(14));

      await show(tester);

      expect(find.text('Write the report'), findsOneWidget);
      expect(find.textContaining('14:00'), findsWidgets);
    });

    testWidgets('several blocks all appear', (tester) async {
      await plan(title: 'Write the report', start: localAt(9));
      await plan(title: 'Read the brief', start: localAt(11), minutes: 30);
      await plan(title: 'Email the landlord', start: localAt(16));

      await show(tester);

      expect(find.text('Write the report'), findsOneWidget);
      expect(find.text('Read the brief'), findsOneWidget);
      expect(find.text('Email the landlord'), findsOneWidget);
    });

    testWidgets('status is on the block, so a day can be read at a glance', (
      tester,
    ) async {
      await plan(
        title: 'Finished thing',
        start: localAt(9),
        status: SessionStatus.completed,
      );
      await plan(
        title: 'Skipped thing',
        start: localAt(11),
        status: SessionStatus.skipped,
      );

      await show(tester);

      expect(find.textContaining('done'), findsOneWidget);
      expect(find.textContaining('skipped'), findsOneWidget);
    });

    testWidgets('a block outside the usual hours still gets drawn', (
      tester,
    ) async {
      // The window starts at 07:00. Something at 05:00 must widen it rather
      // than be scheduled somewhere the screen cannot show.
      await plan(title: 'Very early thing', start: localAt(5));

      await show(tester);

      expect(find.text('Very early thing'), findsOneWidget);
      expect(find.text('05:00'), findsWidgets);
    });
  });

  group('the calendar itself', () {
    testWidgets('an event is drawn with its own name', (tester) async {
      event(localAt(10), localAt(11));

      await show(tester);

      // The whole point of reading the title. A grey band saying "Busy" is
      // honest and unreadable; this is the trade D71 records.
      expect(find.text('Standup with Priya'), findsOneWidget);
    });

    testWidgets('an untitled event still gets something to draw', (
      tester,
    ) async {
      event(localAt(10), localAt(11), title: '');

      await show(tester);

      expect(find.text('(no title)'), findsOneWidget);
    });

    testWidgets('nothing is drawn without the grant', (tester) async {
      event(localAt(10), localAt(11));
      calendars.granted = false;

      await show(tester);

      expect(find.text('Standup with Priya'), findsNothing);
      expect(find.text('Nothing here.'), findsOneWidget);
    });

    testWidgets('an entry marked free is shown but marked free', (
      tester,
    ) async {
      // A view is not a planner. The user put it on the calendar and expects
      // to see it; Van simply will not plan around it, and says so.
      event(localAt(10), localAt(11), title: 'Optional talk', isBusy: false);

      await show(tester);

      expect(find.text('Optional talk'), findsOneWidget);
      expect(find.textContaining('free'), findsOneWidget);
    });

    testWidgets('an all-day entry is drawn above the clock, not down it', (
      tester,
    ) async {
      event(
        localAt(0),
        localAt(0).add(const Duration(days: 1)),
        title: "Sarah's birthday",
        isBusy: false,
        isAllDay: true,
      );

      await show(tester);

      expect(find.text("Sarah's birthday"), findsOneWidget);
      expect(find.text('all day'), findsWidgets);
    });

    testWidgets('the same holiday on eight calendars is drawn once', (
      tester,
    ) async {
      // Not hypothetical. A phone with several Google accounts carries
      // several holiday calendars, and one public holiday arrives eight
      // times over.
      for (var i = 0; i < 8; i++) {
        event(
          localAt(0),
          localAt(0).add(const Duration(days: 1)),
          title: 'Labor Day',
          isBusy: false,
          isAllDay: true,
          calendarId: 'account-$i',
        );
      }

      await show(tester);

      expect(find.text('Labor Day'), findsOneWidget);
    });

    testWidgets('two different events at the same time are both drawn', (
      tester,
    ) async {
      event(localAt(10), localAt(11), title: 'Standup');
      event(localAt(10), localAt(11), title: 'Dentist', calendarId: 'personal');

      await show(tester);

      expect(find.text('Standup'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
    });

    testWidgets('two identical blocks of Van work are both kept', (
      tester,
    ) async {
      // A duplicate event is one thing seen twice. Two identical sessions are
      // two pieces of work, and collapsing them would hide an hour.
      await plan(title: 'Revise', start: localAt(9));
      await sessions.save(
        WorkSession(
          id: 's-revise-2',
          taskId: 't-Revise',
          plannedStart: localAt(9).toUtc(),
          plannedMinutes: 60,
          status: SessionStatus.planned,
        ),
      );

      await show(tester);

      expect(find.text('Revise'), findsNWidgets(2));
    });

    testWidgets('an excluded calendar is not drawn', (tester) async {
      event(localAt(10), localAt(11), calendarId: 'work');
      await preferences.setIncluded('work', included: false);

      await show(tester);

      expect(find.text('Standup with Priya'), findsNothing);
    });

    testWidgets('a broken calendar costs the events, not the screen', (
      tester,
    ) async {
      await plan(title: 'Write the report', start: localAt(14));
      calendars
        ..granted = true
        ..failure = Exception('the provider is not responding');

      await show(tester);

      expect(find.text('Write the report'), findsOneWidget);
    });

    testWidgets('drawing the day writes nothing to the log', (tester) async {
      event(localAt(10), localAt(11));

      await show(tester);

      // Looking at your week is not a planning decision. A calendarRead row
      // per scroll would drown the log it exists to make readable.
      final events = EventRepo(db, clock);
      expect(await events.ofType(EventType.calendarRead), isEmpty);
    });

    testWidgets('no event title reaches the log, even now one is read', (
      tester,
    ) async {
      event(localAt(10), localAt(11), title: 'Divorce mediation');

      await show(tester);
      // And through a real planning pass, which does write rows.
      await service.capture('write the report 60 minutes');

      final serialised = jsonEncode([
        for (final e in await EventRepo(db, clock).all())
          {'type': e.type.name, 'payload': e.payload},
      ]);
      expect(serialised, isNot(contains('Divorce mediation')));
    });

    testWidgets('a failed redraw does not claim the plan was degraded', (
      tester,
    ) async {
      calendars
        ..granted = true
        ..failure = Exception('the provider is not responding');

      await show(tester);

      // That flag is a statement about the plan on screen, and no planning
      // happened here.
      expect(service.calendarIsUnreadable, isFalse);
    });
  });

  group('moving between days', () {
    testWidgets('forward moves one day in the day view', (tester) async {
      final tomorrow = localAt(10).add(const Duration(days: 1));
      await plan(title: 'Tomorrow thing', start: tomorrow);

      await show(tester);
      expect(find.text('Tomorrow thing'), findsNothing);

      await tester.tap(find.byTooltip('Forward'));
      await tester.pumpAndSettle();

      expect(find.text('Tomorrow thing'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('forward moves one week in the week view', (tester) async {
      await plan(
        title: 'Next week thing',
        start: localAt(10).add(const Duration(days: 7)),
      );

      await show(tester, view: CalendarView.week);
      expect(find.text('Next week thing'), findsNothing);

      await tester.tap(find.byTooltip('Forward'));
      await tester.pumpAndSettle();

      // The step follows the view, because a week view that advanced one day
      // at a time would take a week to reach next week.
      expect(find.text('Next week thing'), findsOneWidget);
    });

    testWidgets('Today returns to today', (tester) async {
      await plan(title: 'Today thing', start: localAt(10));

      await show(tester);
      await tester.tap(find.byTooltip('Forward'));
      await tester.pumpAndSettle();
      expect(find.text('Today thing'), findsNothing);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      expect(find.text('Today thing'), findsOneWidget);
    });

    testWidgets('another day in the same week can be tapped', (tester) async {
      final tomorrow = localAt(10).add(const Duration(days: 1));
      await plan(title: 'Tomorrow thing', start: tomorrow);

      await show(tester);
      await tester.tap(find.text('${tomorrow.day}'));
      await tester.pumpAndSettle();

      expect(find.text('Tomorrow thing'), findsOneWidget);
    });
  });

  group('the four views', () {
    testWidgets('the week shows seven days at once', (tester) async {
      final monday = localAt(9).subtract(
        Duration(days: localAt(9).weekday - 1),
      );
      await plan(title: 'Monday thing', start: monday);
      await plan(
        title: 'Friday thing',
        start: monday.add(const Duration(days: 4)),
      );

      await show(tester, view: CalendarView.week);

      expect(find.text('Monday thing'), findsOneWidget);
      expect(find.text('Friday thing'), findsOneWidget);
    });

    testWidgets('the month grid marks the days that have something on', (
      tester,
    ) async {
      await plan(title: 'Write the report', start: localAt(14));

      await show(tester, view: CalendarView.month);

      // A month cell has no room for a name, so the assertion is that the
      // grid is drawn and the day is reachable rather than that it is legible.
      expect(find.text('${today.day}'), findsWidgets);
      expect(find.text('Write the report'), findsNothing);
    });

    testWidgets('tapping a day in the month opens that day', (tester) async {
      await plan(title: 'Write the report', start: localAt(14));

      await show(tester, view: CalendarView.month);
      await tester.tap(find.text('${today.day}').first);
      await tester.pumpAndSettle();

      expect(find.text('Write the report'), findsOneWidget);
    });

    testWidgets('the schedule lists what is ahead, in order', (tester) async {
      await plan(title: 'Today thing', start: localAt(14));
      await plan(
        title: 'Thing in three days',
        start: localAt(10).add(const Duration(days: 3)),
      );

      await show(tester, view: CalendarView.schedule);

      expect(find.textContaining('Today ·'), findsOneWidget);
      expect(find.text('Today thing'), findsOneWidget);
      expect(find.text('Thing in three days'), findsOneWidget);
    });

    testWidgets('the schedule skips days with nothing on them', (tester) async {
      await plan(title: 'Today thing', start: localAt(14));

      await show(tester, view: CalendarView.schedule);

      // Twenty-eight day headings for one block would be scrolling, not
      // information.
      expect(find.textContaining('Today ·'), findsOneWidget);
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('the view can be changed from the app bar', (tester) async {
      await plan(title: 'Today thing', start: localAt(14));

      await show(tester);
      await switchTo(tester, CalendarView.schedule);

      expect(find.textContaining('Today ·'), findsOneWidget);
    });

    testWidgets('a calendar event appears in every view that can name it', (
      tester,
    ) async {
      event(localAt(10), localAt(11));

      await show(tester, view: CalendarView.week);
      expect(find.text('Standup with Priya'), findsOneWidget);

      await switchTo(tester, CalendarView.schedule);
      expect(find.text('Standup with Priya'), findsOneWidget);
    });
  });

  group('the shell', () {
    testWidgets('Calendar is a tab, and it opens the timeline', (tester) async {
      await plan(title: 'Write the report', start: localAt(14));

      await tester.pumpWidget(
        MaterialApp(
          home: VanShell(
            service: service,
            clock: clock,
            notifications: notifications,
            calendars: calendars,
            calendarPreferences: preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(find.text('Write the report'), findsWidgets);
    });
  });
}
