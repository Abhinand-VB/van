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
import 'package:van/platform/calendars.dart';
import 'package:van/ui/shell.dart';
import 'package:van_core/van_core.dart';

import '../support/fake_notifications.dart';
import '../support/prompts.dart';

void main() {
  late VanDatabase db;
  late FakeNotifications notifications;
  late VanService service;
  late FakeClock clock;

  setUp(() {
    db = VanDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 8, 19, 9));
    notifications = FakeNotifications();
    final events = EventRepo(db, clock);

    service = VanService(
      tasks: TaskRepo(db),
      sessions: SessionRepo(db),
      events: events,
      nudges: NudgeRepo(db),
      router: InferenceRouter(defaultBackend: const NullBackend()),
      notifications: notifications,
      templates: NudgeTemplates.fromJson(
        File('assets/nudge_templates/templates.json').readAsStringSync(),
      ),
      prompts: testPrompts(),
      clock: clock,
      ids: SequentialIds('s'),
      waking: const WakingHours(utcOffset: Duration.zero),
    );
  });

  tearDown(() async => db.close());

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VanShell(
          service: service,
          clock: clock,
          notifications: notifications,
          calendars: const UnsupportedCalendars(),
          calendarPreferences: CalendarPreferences(SettingsRepo(db)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps a destination in the navigation bar.
  ///
  /// Scoped to the bar, because once you are on a tab its label and the
  /// screen's own title are both on screen and `find.text` cannot tell them
  /// apart.
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('switching tabs reloads what is behind them', () {
    testWidgets('a task captured on Now appears on Tasks', (tester) async {
      await show(tester);
      await tapTab(tester, 'Tasks');
      expect(find.text('Nothing here yet.'), findsOneWidget);

      // Captured while Tasks is alive but off screen. An IndexedStack keeps
      // it alive, which is what saves a half-typed sentence in Chat and is
      // also why it would otherwise never notice this.
      await service.capture('call the bank 30 minutes');
      await tapTab(tester, 'Now');
      await tapTab(tester, 'Tasks');

      expect(find.text('Call the bank'), findsOneWidget);
    });

    testWidgets('finishing on Tasks is reflected back on Now', (tester) async {
      await service.capture('call the bank 30 minutes');

      await show(tester);
      expect(find.text('Call the bank'), findsWidgets);

      await tapTab(tester, 'Tasks');
      await tester.tap(find.byTooltip('Finish "Call the bank"'));
      await tester.pumpAndSettle();

      await tapTab(tester, 'Now');

      // The Now card was built when the task was open and would still be
      // showing it without the pulse.
      expect(find.text('START'), findsNothing);
    });

    testWidgets('the calendar picks up a block captured elsewhere', (
      tester,
    ) async {
      await show(tester);
      await tapTab(tester, 'Calendar');
      await tapTab(tester, 'Now');

      await service.capture('write the report 45 minutes');
      await tapTab(tester, 'Calendar');

      expect(find.text('Write the report'), findsWidgets);
    });

    testWidgets('returning to a tab you are already on still reloads', (
      tester,
    ) async {
      // Tapping the tab you are on is how people ask for a refresh now that
      // the button is gone, so it has to do something.
      await show(tester);
      await tapTab(tester, 'Tasks');

      await service.capture('call the bank 30 minutes');
      await tapTab(tester, 'Tasks');

      expect(find.text('Call the bank'), findsOneWidget);
    });
  });
}
