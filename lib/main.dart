import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/settings_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/gemma_backend.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/capabilities/negotiate.dart';
import 'package:van/inference/config.dart';
import 'package:van/platform/local_llm.dart';
import 'package:van/platform/notifications.dart';
import 'package:van/platform/system_clock.dart';
import 'package:van/ui/shell.dart';
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
  final nudges = NudgeRepo(db);
  final settings = SettingsRepo(db);

  final notifications = AndroidNotifications(FlutterLocalNotificationsPlugin());

  final templates = NudgeTemplates.fromJson(
    await rootBundle.loadString('assets/nudge_templates/templates.json'),
  );
  final negotiatePrompt = PromptTemplate.parse(
    await rootBundle.loadString('assets/prompts/negotiate.v1.txt'),
  );

  // v1 ships with no model. Every capability has a deterministic fallback, so
  // this is a working configuration rather than a degraded one.
  //
  // Routing is read from the asset rather than written here, which is what
  // makes "adding a provider is a config change" true. Every backend Van can
  // construct is offered by name; the config decides which capability uses
  // which. Building them is wiring, so it stays in this file.
  final config = InferenceConfig.fromJson(
    await rootBundle.loadString('assets/inference_config.json'),
  );
  final warnings = <ConfigWarning>[];
  final router = config.router(
    available: {
      'none': const NullBackend(),
      'gemma_e2b': GemmaBackend(const MethodChannelLocalLlm()),
    },
    fallbackBackend: const NullBackend(),
    observer: EventLogInferenceObserver(events),
    warnings: warnings,
  );
  for (final warning in warnings) {
    // A bad route is survivable - it falls back to the deterministic path -
    // but it must not be silent, or a capability could quietly stop using the
    // model it was meant to.
    await events.append(EventType.inferenceFallback, {
      'capability': 'config',
      'backend': 'none',
      'reason': warning.message,
    });
  }

  final waking = WakingHours(utcOffset: DateTime.now().timeZoneOffset);

  final service = VanService(
    tasks: tasks,
    sessions: sessions,
    events: events,
    nudges: nudges,
    router: router,
    notifications: notifications,
    templates: templates,
    negotiatePrompt: negotiatePrompt,
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

  runApp(
    VanApp(
      service: service,
      clock: clock,
      notifications: notifications,
      settings: settings,
    ),
  );
}

/// Application shell.
class VanApp extends StatelessWidget {
  /// Creates the app.
  const VanApp({
    required this.service,
    required this.clock,
    required this.notifications,
    required this.settings,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Notification delivery, used for the first-run permission prompt.
  final Notifications notifications;

  /// Persists the one-time record that permission has been asked for.
  final SettingsRepo settings;

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
        settings: settings,
        child: VanShell(
          service: service,
          clock: clock,
          notifications: notifications,
        ),
      ),
    );
  }
}

/// Asks for notification permission once, on first paint, and then stops.
///
/// Van without permission to interrupt is a task list, so it has to ask. But
/// asking sends the user out to a system settings screen, and doing that on
/// every cold start until they comply is how an app gets uninstalled. The
/// latch is persisted rather than held in memory, because "first run" has to
/// survive being killed.
///
/// Declining is therefore *allowed*, and the consequence is not silence: the
/// Now screen carries a standing banner for as long as the grant is missing.
/// That is the whole trade - ask once, then inform, never nag.
class _FirstRun extends StatefulWidget {
  const _FirstRun({
    required this.notifications,
    required this.settings,
    required this.child,
  });

  final Notifications notifications;
  final SettingsRepo settings;
  final Widget child;

  @override
  State<_FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends State<_FirstRun> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askOnce());
  }

  Future<void> _askOnce() async {
    if (await widget.settings.flag(SettingKeys.askedForPermission)) return;
    if ((await widget.notifications.permissions()).complete) return;

    // Latched before the request rather than after: if the user is thrown out
    // to settings and never comes back, Van has still asked, and must not ask
    // again on the next launch.
    await widget.settings.setFlag(SettingKeys.askedForPermission);
    await widget.notifications.requestPermission();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
