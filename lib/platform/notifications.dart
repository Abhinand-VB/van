import 'package:flutter/services.dart';
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

/// Notification ids for one session's escalation ladder.
///
/// Derived from the session id rather than remembered, and that is the whole
/// point. Van pre-schedules a ladder and cancels the rest of it the moment the
/// user responds - but the response routinely arrives in a *later process*
/// than the arming did, hours later, after the phone has been idle. Anything
/// that has to be looked up in memory is empty by then, and the cancel
/// silently does nothing.
///
/// Each session owns a block of [perSession] consecutive ids. Cancelling
/// simply cancels the whole block: cancelling an id that was never scheduled
/// is a no-op, so this can never miss a rung, and it cannot drift if the
/// ladder ever grows or shrinks.
abstract final class LadderIds {
  /// Ids reserved per session. The ladder is three rungs today; the block is
  /// deliberately larger so growing it needs no thought here.
  static const perSession = 8;

  /// The id for rung [rung] of [sessionId].
  static int forRung(String sessionId, int rung) {
    assert(rung >= 0 && rung < perSession, 'rung must fit the reserved block');
    return (sessionId.hashCode & 0x3FFFFF) * perSession + rung;
  }

  /// Every id [sessionId] could possibly have used.
  static List<int> forSession(String sessionId) => [
    for (var rung = 0; rung < perSession; rung++) forRung(sessionId, rung),
  ];
}

/// Which of the two grants Van needs the OS has actually given.
///
/// They are separate permissions and they fail differently, so a single
/// boolean cannot say anything useful to the user. Without [canPost] Van is a
/// task list. With [canPost] but not [canScheduleExactly] it still works, but
/// a nudge lands somewhere inside the following hour rather than on the
/// minute - degraded, not broken, and worth saying so rather than nagging.
class NudgePermissions {
  /// Creates a permission snapshot.
  const NudgePermissions({
    required this.canPost,
    required this.canScheduleExactly,
  });

  /// Nothing is granted. The state a fresh install starts in.
  const NudgePermissions.none() : canPost = false, canScheduleExactly = false;

  /// Whether Van may post notifications at all.
  final bool canPost;

  /// Whether Van may schedule an alarm for an exact minute.
  final bool canScheduleExactly;

  /// Whether Van can do its job properly.
  bool get complete => canPost && canScheduleExactly;

  /// Whether nudges will arrive, even if not punctually.
  bool get workable => canPost;

  @override
  String toString() =>
      'NudgePermissions(post: $canPost, exact: $canScheduleExactly)';
}

/// Delivers nudges, and reports what the user did about them.
abstract interface class Notifications {
  /// Prepares channels and restores the timezone database.
  Future<void> init(
    void Function(String sessionId, NudgeAction action) onAction,
  );

  /// Which grants the OS has given Van, read fresh every time.
  Future<NudgePermissions> permissions();

  /// Asks for permission. Returns whether it was granted.
  Future<bool> requestPermission();

  /// The action that launched Van, if a notification did.
  ///
  /// Must be read at startup. When Van is not running, pressing an action
  /// button does not reach the callback passed to [init] - that callback only
  /// exists while a Flutter engine does. Android launches the app instead and
  /// hands the response over here, once.
  Future<({String sessionId, NudgeAction action})?> consumeLaunchAction();

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
  Future<NudgePermissions> permissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return const NudgePermissions.none();

    // Notifications alone are not enough, and the two are asked for
    // separately. Reading only the first is what hid the missing exact-alarm
    // grant for two days: on a phone where notifications were already allowed,
    // Van never asked for the other one and every zonedSchedule threw.
    return NudgePermissions(
      canPost: await android.areNotificationsEnabled() ?? false,
      canScheduleExactly:
          await android.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<({String sessionId, NudgeAction action})?>
  consumeLaunchAction() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;

    final sessionId = details.notificationResponse?.payload;
    if (sessionId == null || sessionId.isEmpty) return null;

    return (
      sessionId: sessionId,
      action: _actionFrom(details.notificationResponse?.actionId),
    );
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
    try {
      await _zonedSchedule(nudge, AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      // Exact alarms are a permission the user can take away at any time from
      // system settings, and on API 33+ they do not have it until they grant
      // it. A rung that fires a few minutes late is worth enormously more than
      // a rung that never fires, so drop to inexact rather than lose it - and
      // never let a failed alarm take the capture down with it.
      if (!_isExactAlarmRefusal(e)) rethrow;
      await _zonedSchedule(nudge, AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> _zonedSchedule(PendingNudge nudge, AndroidScheduleMode mode) =>
      _plugin.zonedSchedule(
        id: nudge.id,
        title: nudge.title,
        body: nudge.body,
        scheduledDate: tz.TZDateTime.from(nudge.at.toLocal(), tz.local),
        notificationDetails: _details(nudge),
        androidScheduleMode: mode,
        payload: nudge.sessionId,
      );

  /// Whether [e] is the platform refusing an exact alarm, as opposed to a real
  /// fault worth surfacing.
  static bool _isExactAlarmRefusal(PlatformException e) =>
      e.code == 'exact_alarms_not_permitted';

  @override
  Future<void> showNow(PendingNudge nudge) async {
    await _plugin.show(
      id: nudge.id,
      title: nudge.title,
      body: nudge.body,
      notificationDetails: _details(nudge),
      payload: nudge.sessionId,
    );
  }

  /// The buttons on a nudge.
  ///
  /// **Every one is `showsUserInterface`, and that is load-bearing.** An
  /// action without it never launches the app, so with Van not running it
  /// reaches `notificationTapBackground` - an isolate with no Flutter engine,
  /// which cannot touch the database. The action is then lost, and because
  /// `cancelNotification` defaults to true, the notification disappears while
  /// it happens. The user presses "Snooze 10", watches it vanish, and gets
  /// nudged again ten minutes later about a block that never moved. That is
  /// not a button doing nothing; that is a button lying.
  ///
  /// Opening the app to snooze something is intrusive, and it is the lesser
  /// problem. The better fix is a background isolate with its own database
  /// connection - see STATUS issue 15 - and until that exists, honest and
  /// intrusive beats silent and broken.
  static const nudgeActions = <AndroidNotificationAction>[
    AndroidNotificationAction('start', 'Start', showsUserInterface: true),
    AndroidNotificationAction('snooze', 'Snooze 10', showsUserInterface: true),
    AndroidNotificationAction(
      'not_today',
      'Not today',
      showsUserInterface: true,
    ),
  ];

  NotificationDetails _details(PendingNudge nudge) {
    // A conceded nudge is Van telling you it has moved the work. Offering
    // START on it would be incoherent.
    final actions = nudge.level == InterventionLevel.l5Concede
        ? const <AndroidNotificationAction>[]
        : nudgeActions;

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
  Future<void> cancel(int id) async => _plugin.cancel(id: id);

  @override
  Future<void> cancelForSession(String sessionId) async {
    for (final id in LadderIds.forSession(sessionId)) {
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
///
/// Deliberately empty, and it should stay unreachable. This runs in a separate
/// isolate with no Flutter engine, so it cannot reach `VanService` or the
/// database without opening a second connection to both - anything that
/// arrives here is therefore lost.
///
/// Nothing routes here today: every action in
/// [AndroidNotifications.nudgeActions] is `showsUserInterface`, so Android
/// launches the app and hands the response to
/// `getNotificationAppLaunchDetails`, which `main.dart` collects at startup
/// through [Notifications.consumeLaunchAction].
///
/// Drop `showsUserInterface` from an action and it starts arriving here
/// instead, silently. There is a test asserting none of them has.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {}
