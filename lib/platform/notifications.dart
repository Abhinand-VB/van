import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:van_core/van_core.dart' hide Priority;

/// One interruption ready to be delivered.
class PendingNudge {
  /// Creates a pending nudge.
  const PendingNudge({
    required this.id,
    required this.sessionId,
    required this.at,
    required this.title,
    required this.body,
    required this.level,
    this.urgent = false,
  });

  /// Stable integer id, so it can be cancelled.
  final int id;

  /// The session this is about.
  final String sessionId;

  /// When it should fire. UTC.
  final DateTime at;

  /// Heading line.
  final String title;

  /// The nudge copy.
  final String body;

  /// How hard it pushes, used to pick the actions offered.
  final InterventionLevel level;

  /// Whether it goes to the high-priority channel.
  final bool urgent;
}

/// What the user tapped.
enum NudgeAction {
  /// Opened the notification body.
  opened,

  /// Pressed START.
  start,

  /// Pressed Snooze.
  snooze,

  /// Pressed Not today.
  notToday,
}

/// Delivers nudges, and reports what the user did about them.
abstract interface class Notifications {
  /// Prepares channels and restores the timezone database.
  Future<void> init(
    void Function(String sessionId, NudgeAction action) onAction,
  );

  /// Whether the OS will let Van post notifications.
  Future<bool> hasPermission();

  /// Asks for permission. Returns whether it was granted.
  Future<bool> requestPermission();

  /// Schedules [nudge] to fire at its instant.
  Future<void> schedule(PendingNudge nudge);

  /// Shows something immediately.
  Future<void> showNow(PendingNudge nudge);

  /// Cancels one scheduled nudge.
  Future<void> cancel(int id);

  /// Cancels every nudge about [sessionId].
  Future<void> cancelForSession(String sessionId);

  /// Ids still waiting to fire.
  Future<List<int>> pending();
}

/// Android implementation over `flutter_local_notifications`.
///
/// Van pre-schedules the whole escalation ladder for a session - the prompt at
/// the start, the check at +10, the diagnose at +25 - and cancels the rest the
/// moment the user responds. That is less clever than waking up and deciding
/// live, but it is dramatically more reliable under Doze, needs no background
/// isolate, and is the only shape iOS would ever allow. See
/// docs/ARCHITECTURE.md 8.2.
class AndroidNotifications implements Notifications {
  /// Creates the Android implementation.
  AndroidNotifications(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  // Android caches channel settings permanently: once a channel exists, later
  // changes to its sound are ignored. Changing the sound therefore means
  // creating a NEW channel id and deleting the old one. Bump the suffix if the
  // sound ever changes again, or the drum will silently not play for anyone
  // who already installed Van.
  static const _normalChannel = 'van_nudges_v2';
  static const _urgentChannel = 'van_nudges_urgent_v2';
  static const _retiredChannels = ['van_nudges', 'van_nudges_urgent'];

  /// Maps a notification id back to the session it concerns, so a tap can be
  /// attributed without round-tripping through the database.
  final _sessionByNotificationId = <int, String>{};

  @override
  Future<void> init(
    void Function(String sessionId, NudgeAction action) onAction,
  ) async {
    tzdata.initializeTimeZones();
    final localName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localName.identifier));

    void handle(NotificationResponse response) {
      final sessionId = response.payload;
      if (sessionId == null || sessionId.isEmpty) return;
      onAction(sessionId, _actionFrom(response.actionId));
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: handle,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    for (final retired in _retiredChannels) {
      await android?.deleteNotificationChannel(channelId: retired);
    }

    // Two channels so the user can silence ordinary nudges in Android settings
    // without losing the ones that matter, and so the drum is set per channel
    // and stays user-changeable rather than baked into the app.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _normalChannel,
        'Nudges',
        description: 'Session prompts and check-ins.',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('nudge_drum'),
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _urgentChannel,
        'Urgent nudges',
        description: 'Deadlines and imminent commitments.',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('nudge_drum_urgent'),
      ),
    );
  }

  NudgeAction _actionFrom(String? actionId) => switch (actionId) {
    'start' => NudgeAction.start,
    'snooze' => NudgeAction.snooze,
    'not_today' => NudgeAction.notToday,
    _ => NudgeAction.opened,
  };

  @override
  Future<bool> hasPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    return granted ?? false;
  }

  @override
  Future<void> schedule(PendingNudge nudge) async {
    _sessionByNotificationId[nudge.id] = nudge.sessionId;
    await _plugin.zonedSchedule(
      id: nudge.id,
      title: nudge.title,
      body: nudge.body,
      scheduledDate: tz.TZDateTime.from(nudge.at.toLocal(), tz.local),
      notificationDetails: _details(nudge),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: nudge.sessionId,
    );
  }

  @override
  Future<void> showNow(PendingNudge nudge) async {
    _sessionByNotificationId[nudge.id] = nudge.sessionId;
    await _plugin.show(
      id: nudge.id,
      title: nudge.title,
      body: nudge.body,
      notificationDetails: _details(nudge),
      payload: nudge.sessionId,
    );
  }

  NotificationDetails _details(PendingNudge nudge) {
    // A conceded nudge is Van telling you it has moved the work. Offering
    // START on it would be incoherent.
    final actions = nudge.level == InterventionLevel.l5Concede
        ? const <AndroidNotificationAction>[]
        : const <AndroidNotificationAction>[
            AndroidNotificationAction(
              'start',
              'Start',
              showsUserInterface: true,
            ),
            AndroidNotificationAction('snooze', 'Snooze 10'),
            AndroidNotificationAction('not_today', 'Not today'),
          ];

    return NotificationDetails(
      android: AndroidNotificationDetails(
        nudge.urgent ? _urgentChannel : _normalChannel,
        nudge.urgent ? 'Urgent nudges' : 'Nudges',
        importance: nudge.urgent ? Importance.max : Importance.high,
        priority: nudge.urgent ? Priority.max : Priority.high,
        actions: actions,
        category: AndroidNotificationCategory.reminder,
        sound: RawResourceAndroidNotificationSound(
          nudge.urgent ? 'nudge_drum_urgent' : 'nudge_drum',
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    _sessionByNotificationId.remove(id);
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelForSession(String sessionId) async {
    final ids = _sessionByNotificationId.entries
        .where((e) => e.value == sessionId)
        .map((e) => e.key)
        .toList();
    for (final id in ids) {
      await cancel(id);
    }
  }

  @override
  Future<List<int>> pending() async {
    final requests = await _plugin.pendingNotificationRequests();
    return requests.map((r) => r.id).toList();
  }
}

/// Entry point for taps that arrive while Van is not running.
///
/// Must be a top-level function annotated for the AOT compiler, or the
/// callback is tree-shaken away in release builds and actions silently stop
/// working.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Intentionally empty: the action is re-read from the pending intent when
  // the app next opens. Doing database work here would need a second isolate
  // and a second database connection for no benefit at this stage.
}
