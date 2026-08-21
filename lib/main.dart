import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/router.dart';
import 'package:van/platform/notifications.dart';
import 'package:van/platform/system_clock.dart';
import 'package:van/ui/now_screen.dart';
import 'package:van_core/van_core.dart';

/// Identifiers unique enough to survive a restart without a uuid dependency.
///
/// Single user, single device, so the timestamp plus a counter is sufficient
/// and keeps ids sortable when reading the database by hand.
class TimestampIds implements IdGenerator {
  int _n = 0;

  @override
  String next() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(++_n).toRadixString(36)}';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Composition root. This is the only place in Van where anything is wired
  // to anything else; every layer below takes its collaborators as arguments.
  const clock = SystemClock();
  final ids = TimestampIds();

  final db = VanDatabase();
  final tasks = TaskRepo(db);
  final sessions = SessionRepo(db);
  final events = EventRepo(db, clock);

  final notifications = AndroidNotifications(FlutterLocalNotificationsPlugin());

  final templates = NudgeTemplates.fromJson(
    await rootBundle.loadString('assets/nudge_templates/templates.json'),
  );

  // v1 ships with no model. Every capability has a deterministic fallback, so
  // this is a working configuration rather than a degraded one. Swapping in a
  // real backend is a change to assets/inference_config.json plus one class.
  final router = InferenceRouter(
    defaultBackend: const NullBackend(),
    observer: EventLogInferenceObserver(events),
  );

  final waking = WakingHours(utcOffset: DateTime.now().timeZoneOffset);

  final service = VanService(
    tasks: tasks,
    sessions: sessions,
    events: events,
    router: router,
    notifications: notifications,
    templates: templates,
    clock: clock,
    ids: ids,
    waking: waking,
  );

  await notifications.init((sessionId, action) async {
    switch (action) {
      case NudgeAction.start:
        await service.startSession(sessionId);
      case NudgeAction.snooze:
        await service.snooze(sessionId);
      case NudgeAction.notToday:
        await service.notToday(sessionId);
      case NudgeAction.opened:
        break;
    }
  });

  await service.noteAppOpened();

  runApp(VanApp(service: service, clock: clock, notifications: notifications));
}

/// Application shell.
class VanApp extends StatelessWidget {
  /// Creates the app.
  const VanApp({
    required this.service,
    required this.clock,
    required this.notifications,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Notification delivery, used for the first-run permission prompt.
  final Notifications notifications;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Van',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D5B)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D5B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _FirstRun(
        notifications: notifications,
        child: NowScreen(service: service, clock: clock),
      ),
    );
  }
}

/// Asks for notification permission once, on first paint.
///
/// Van without permission to interrupt is a task list, so this is not an
/// optional nicety - but it is asked once and never nagged about.
class _FirstRun extends StatefulWidget {
  const _FirstRun({required this.notifications, required this.child});

  final Notifications notifications;
  final Widget child;

  @override
  State<_FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends State<_FirstRun> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await widget.notifications.hasPermission()) {
        await widget.notifications.requestPermission();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
