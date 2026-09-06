import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/data/repositories/event_repo.dart';
import 'package:van/data/repositories/nudge_repo.dart';
import 'package:van/data/repositories/session_repo.dart';
import 'package:van/data/repositories/settings_repo.dart';
import 'package:van/data/repositories/task_repo.dart';
import 'package:van/inference/backends/gemma_backend.dart';
import 'package:van/inference/backends/null_backend.dart';
import 'package:van/inference/capabilities/compose_nudge.dart';
import 'package:van/inference/config.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/platform/local_llm.dart';
import 'package:van/platform/model_file.dart';
import 'package:van/platform/notifications.dart';
import 'package:van/platform/speech.dart';
import 'package:van/platform/system_clock.dart';
import 'package:van/platform/timezone_watcher.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/model_probe.dart';
import 'package:van/ui/model_screen.dart';
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
  final calendarPreferences = CalendarPreferences(settings);

  final notifications = AndroidNotifications(FlutterLocalNotificationsPlugin());
  // Read at plan time and never copied into Van's database: the OS owns the
  // calendar and is the source of truth for it. See VanService._freeSlots.
  const calendars = MethodChannelCalendars();
  const speech = MethodChannelSpeech();
  const modelFile = MethodChannelModelFile();

  final templates = NudgeTemplates.fromJson(
    await rootBundle.loadString('assets/nudge_templates/templates.json'),
  );
  final prompts = await Prompts.load(rootBundle.loadString);

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

  // Read once here, then re-read on every resume by the watcher below. The
  // offset moving under a running process - DST, a flight - used to leave the
  // parser and the planner disagreeing about what day it was until restart.
  final waking = WakingHours(utcOffset: const SystemClock().utcOffset());

  final service = VanService(
    tasks: tasks,
    sessions: sessions,
    events: events,
    nudges: nudges,
    router: router,
    notifications: notifications,
    calendars: calendars,
    calendarPreferences: calendarPreferences,
    templates: templates,
    prompts: prompts,
    clock: clock,
    ids: ids,
    waking: waking,
  );

  // Deliberately after `service` exists: the watcher's whole job is to hand
  // it a new offset, and wiring it before there is anything to hand it to is
  // how this ends up silently doing nothing.
  TimezoneWatcher((offset) {
    if (service.refreshTimezone(offset)) {
      inBackground(
        events.append(EventType.timezoneChanged, {
          'offsetMinutes': offset.inMinutes,
        }),
      );
    }
  }).start();

  await notifications.init(
    (sessionId, action) async => handleNudgeAction(service, sessionId, action),
  );

  // A notification pressed while Van was not running never reaches the
  // callback above - there was no Flutter engine to receive it. Android
  // launches the app and leaves the response here instead, so it has to be
  // collected once, at startup, or pressing START on a nudge simply opens Van
  // and does nothing.
  final launched = await notifications.consumeLaunchAction();
  if (launched != null) {
    await handleNudgeAction(service, launched.sessionId, launched.action);
  }

  await service.noteAppOpened();

  runApp(
    VanApp(
      service: service,
      clock: clock,
      notifications: notifications,
      settings: settings,
      calendars: calendars,
      calendarPreferences: calendarPreferences,
      speech: speech,
      modelFile: modelFile,
      usesModel: config.usesModel,
      // Handed in only so the probe can ask the engine a question by hand.
      // Nothing here routes a capability to it - that is the config asset's
      // job and it still says "none".
      localLlm: const MethodChannelLocalLlm(),
      prompts: prompts,
    ),
  );
}

/// Routes a notification action to the service.
///
/// Top-level and public so that both routes into it - the live callback and
/// the launch-details read - are the same code, and so it can be tested. It
/// used to be a closure inside `main`, which meant the single most important
/// interaction Van has was unreachable by any test.
Future<void> handleNudgeAction(
  VanService service,
  String sessionId,
  NudgeAction action,
) async {
  switch (action) {
    case NudgeAction.start:
      await service.startSession(sessionId);
    case NudgeAction.snooze:
      await service.snooze(sessionId);
    case NudgeAction.notToday:
      await service.notToday(sessionId);
    case NudgeAction.opened:
      // Opening the notification body is not an answer. Van shows the Now
      // screen and waits; whatever the user does there is recorded by the
      // method they choose.
      break;
  }
}

/// Application shell.
class VanApp extends StatelessWidget {
  /// Creates the app.
  const VanApp({
    required this.service,
    required this.clock,
    required this.notifications,
    required this.settings,
    required this.calendars,
    required this.calendarPreferences,
    this.speech = const UnsupportedSpeech(),
    this.modelFile = const UnsupportedModelFile(),
    this.usesModel = false,
    this.localLlm,
    this.prompts,
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

  /// The device calendar, for the settings page.
  final Calendars calendars;

  /// Which calendars planning may see.
  final CalendarPreferences calendarPreferences;

  /// On-device speech, for the microphone button on both composers.
  final Speech speech;

  /// The on-device model's weights, for Settings and the first-run offer.
  final ModelFile modelFile;

  /// Whether any capability is actually answered by a model, which decides
  /// what the first-run offer can honestly claim.
  final bool usesModel;

  /// The channel to the on-device engine, when this platform has one. Used
  /// only by the probe - nothing here routes anything to it.
  final LocalLlm? localLlm;

  /// The versioned prompt assets, so the probe asks what Van would ask.
  final Prompts? prompts;

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
        modelFile: modelFile,
        // Offering only matters when something would actually use it. With
        // every capability routed to "none" the offer is honest about that
        // rather than absent, because a 2.6 GB download is not something to
        // spring on someone with no explanation either way.
        usesModel: usesModel,
        child: Builder(
          builder: (context) => VanShell(
            service: service,
            clock: clock,
            notifications: notifications,
            calendars: calendars,
            calendarPreferences: calendarPreferences,
            speech: speech,
            modelFile: modelFile,
            // Only where there is a channel to reach. On a build without one
            // the button is absent rather than present and broken.
            onTryModel: localLlm == null || prompts == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ModelProbe(
                        llm: localLlm!,
                        prompts: prompts!,
                        clock: clock,
                      ),
                    ),
                  ),
          ),
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
    required this.modelFile,
    required this.usesModel,
    required this.child,
  });

  final Notifications notifications;
  final SettingsRepo settings;

  /// The on-device model, for the one-time offer to set it up.
  final ModelFile modelFile;

  /// Whether any capability is actually routed to a model.
  final bool usesModel;

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
    await _askForNotifications();
    await _offerTheModel();
  }

  Future<void> _askForNotifications() async {
    if (await widget.settings.flag(SettingKeys.askedForPermission)) return;
    if ((await widget.notifications.permissions()).complete) return;

    // Latched before the request rather than after: if the user is thrown out
    // to settings and never comes back, Van has still asked, and must not ask
    // again on the next launch.
    await widget.settings.setFlag(SettingKeys.askedForPermission);
    await widget.notifications.requestPermission();
  }

  /// Mentions the on-device model once, on first run, and then never again.
  ///
  /// **Second, not first.** Permission to interrupt is what makes Van work;
  /// the model is optional and currently changes nothing. Putting a
  /// two-and-a-half-gigabyte download in front of somebody before they have
  /// captured a single task would be selling the engine before the car.
  ///
  /// Latched like the permission, and for the same reason: an offer that
  /// reappears on every cold start is not an offer.
  Future<void> _offerTheModel() async {
    if (await widget.settings.flag(SettingKeys.offeredModel)) return;

    final status = await widget.modelFile.status();
    // Nothing to offer if it is already there - someone who has put the file
    // on themselves does not need to be sold it. And nothing to offer on a
    // build with nowhere to put one: an empty path is what
    // `UnsupportedModelFile` reports, and inviting someone to install a model
    // on a platform that cannot hold one is worse than saying nothing.
    if (status.present || status.path.isEmpty) {
      await widget.settings.setFlag(SettingKeys.offeredModel);
      return;
    }
    if (!mounted) return;

    await widget.settings.setFlag(SettingKeys.offeredModel);
    if (!mounted) return;
    // Captured before the dialog rather than reached for after it, so the
    // push does not have to reason about a context that may have gone away
    // while somebody was reading.
    final navigator = Navigator.of(context);
    final setUp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run a model on your phone?'),
        content: Text(
          widget.usesModel
              ? 'Van can word its nudges with a language model that runs '
                    'entirely on this phone — nothing you type or say leaves '
                    'it. It is ${ModelSource.description}, downloaded once.'
              // The honest version of today's state. Selling a download for a
              // capability that is switched off would be a lie the user finds
              // out about the moment they install it and nothing changes.
              : 'Van can run a language model entirely on this phone, with '
                    'nothing leaving it. It is optional and Van works fully '
                    'without it — nothing uses it yet, while its answers are '
                    'still being measured against the built-in ones. You can '
                    'set it up now or from Settings later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Set it up'),
          ),
        ],
      ),
    );

    if (!mounted || !(setUp ?? false)) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ModelScreen(modelFile: widget.modelFile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
