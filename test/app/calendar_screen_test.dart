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

  void busy(DateTime from, DateTime to) {
    calendars
      ..granted = true
      ..entries.add(
        CalendarEntry(
          calendarId: 'work',
          start: from.toUtc(),
          end: to.toUtc(),
        ),
      );
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          service: service,
          clock: clock,
          calendars: calendars,
          calendarPreferences: preferences,
        ),
      ),
    );
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

      expect(find.text('Nothing on this day.'), findsOneWidget);
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

  group('the calendar underneath', () {
    testWidgets('a meeting is drawn as a shape with no name', (tester) async {
      busy(localAt(10), localAt(11));

      await show(tester);

      // All Van knows. It never reads a title, so "Busy" is not a placeholder
      // for one that failed to load - see D70.
      expect(find.text('Busy'), findsOneWidget);
    });

    testWidgets('nothing is drawn without the grant', (tester) async {
      calendars
        ..granted = false
        ..entries.add(
          CalendarEntry(
            calendarId: 'work',
            start: localAt(10).toUtc(),
            end: localAt(11).toUtc(),
          ),
        );

      await show(tester);

      expect(find.text('Busy'), findsNothing);
    });

    testWidgets('a free entry is not drawn, matching what planning does', (
      tester,
    ) async {
      calendars
        ..granted = true
        ..entries.add(
          CalendarEntry(
            calendarId: 'birthdays',
            start: localAt(0).toUtc(),
            end: localAt(0).add(const Duration(days: 1)).toUtc(),
            isAllDay: true,
            isBusy: false,
          ),
        );

      await show(tester);

      expect(find.text('Busy'), findsNothing);
      expect(find.text('Nothing on this day.'), findsOneWidget);
    });

    testWidgets('an excluded calendar is not drawn either', (tester) async {
      busy(localAt(10), localAt(11));
      await preferences.setIncluded('work', included: false);

      await show(tester);

      expect(find.text('Busy'), findsNothing);
    });

    testWidgets('a broken calendar costs the bands, not the screen', (
      tester,
    ) async {
      await plan(title: 'Write the report', start: localAt(14));
      calendars
        ..granted = true
        ..failure = Exception('the provider is not responding');

      await show(tester);

      // The blocks still draw. A calendar view missing its shading is a
      // lesser thing than a screen that will not paint.
      expect(find.text('Write the report'), findsOneWidget);
      expect(find.text('Busy'), findsNothing);
    });

    testWidgets('drawing the day writes nothing to the log', (tester) async {
      busy(localAt(10), localAt(11));

      await show(tester);

      // Looking at your week is not a planning decision. A calendarRead row
      // per scroll would drown the log it exists to make readable.
      final events = EventRepo(db, clock);
      expect(await events.ofType(EventType.calendarRead), isEmpty);
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
    testWidgets('the next week can be reached and comes back', (tester) async {
      await plan(
        title: 'Next week thing',
        start: localAt(10).add(
          const Duration(days: 7),
        ),
      );

      await show(tester);
      expect(find.text('Next week thing'), findsNothing);

      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();

      expect(find.text('Next week thing'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('Today returns to today', (tester) async {
      await plan(title: 'Today thing', start: localAt(10));

      await show(tester);
      await tester.tap(find.byTooltip('Next week'));
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
