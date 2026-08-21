import 'package:van/platform/notifications.dart';

/// Records what would have been shown, so the loop can be driven without a
/// phone. Everything it stands in for is the same code the device runs.
class FakeNotifications implements Notifications {
  /// Nudges handed to the OS and not yet cancelled.
  final scheduled = <PendingNudge>[];

  /// Notification ids that were cancelled.
  final cancelled = <int>[];

  /// Whether Van may post notifications at all.
  bool canPost = true;

  /// Whether Van may schedule to an exact minute.
  bool canScheduleExactly = true;

  /// How many times permission has been asked for. The number that matters
  /// for first-run behaviour: asking twice is the bug.
  int requests = 0;

  /// What [requestPermission] should grant. Null leaves the state alone,
  /// which is what happens when the user walks away from the settings screen.
  bool? grantOnRequest;

  @override
  Future<void> init(
    void Function(String sessionId, NudgeAction action) onAction,
  ) async {}

  @override
  Future<NudgePermissions> permissions() async => NudgePermissions(
    canPost: canPost,
    canScheduleExactly: canScheduleExactly,
  );

  @override
  Future<bool> requestPermission() async {
    requests++;
    final granted = grantOnRequest;
    if (granted != null) {
      canPost = granted;
      canScheduleExactly = granted;
    }
    return canPost;
  }

  @override
  Future<void> schedule(PendingNudge nudge) async => scheduled.add(nudge);

  @override
  Future<void> showNow(PendingNudge nudge) async => scheduled.add(nudge);

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> cancelForSession(String sessionId) async {
    final ids = scheduled
        .where((n) => n.sessionId == sessionId)
        .map((n) => n.id)
        .toList();
    for (final id in ids) {
      await cancel(id);
    }
  }

  @override
  Future<List<int>> pending() async => scheduled.map((n) => n.id).toList();
}
