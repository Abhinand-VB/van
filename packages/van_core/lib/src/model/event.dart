import 'package:meta/meta.dart';

/// Everything Van records about what happened.
///
/// If a fact might matter to the adaptive intervention policy later, it has to
/// become an event at the moment it occurs. Events cannot be recovered
/// retrospectively, which is why this list is deliberately generous.
enum EventType {
  /// A task was captured.
  taskCreated,

  /// A task changed status.
  taskUpdated,

  /// Sessions were derived from a task.
  sessionPlanned,

  /// START was pressed.
  sessionStarted,

  /// A session ran to the end.
  sessionCompleted,

  /// A session stopped early but did happen.
  sessionPartial,

  /// A session came due and nothing happened.
  sessionMissed,

  /// A nudge was queued.
  nudgeScheduled,

  /// A nudge was blocked before delivery. Records the reason.
  nudgeSuppressed,

  /// A nudge Van decided to send could not be handed to the platform.
  ///
  /// Distinct from [nudgeSuppressed], which is Van choosing silence. This is
  /// Android refusing, and the two must never be conflated: the whole value of
  /// the suppression record is telling a quiet day from a broken scheduler.
  nudgeScheduleFailed,

  /// A nudge reached the user.
  nudgeDelivered,

  /// The user answered a nudge.
  nudgeResponded,

  /// The escalation ladder picked a level.
  interventionSelected,

  /// Work was moved.
  rescheduleApplied,

  /// A model call succeeded and parsed.
  inferenceOk,

  /// A model call failed, or parsed to nothing, and the deterministic
  /// fallback ran instead. The reason is in the payload.
  inferenceFallback,

  /// The app came to the foreground.
  appOpened,

  /// The app went to the background.
  appBackgrounded,

  /// The device calendar was read while planning, and how much of the day it
  /// claimed.
  ///
  /// Records the *number* of commitments considered and nothing about what
  /// they were. Meeting titles are never read, never cross the platform
  /// channel and never reach this table, which is append-only and never
  /// deletes - a title written here would live on the phone permanently.
  ///
  /// Worth a row despite that thinness: without it, a day where Van scheduled
  /// almost nothing is indistinguishable from a day where it was working
  /// correctly around a full calendar.
  calendarRead,

  /// The device calendar could not be read, and planning fell back to Van's
  /// own sessions.
  ///
  /// Distinct from [calendarRead] with zero commitments, and the distinction
  /// is the point: an empty calendar and an unreadable one produce the same
  /// plan and mean opposite things. Permission revoked mid-session, a
  /// provider error, a read that timed out.
  calendarUnavailable,

  /// The device's UTC offset moved under a running process - a DST change or
  /// a flight - and Van rebuilt everything that derives from it.
  ///
  /// Worth recording because it retunes the parser, the planner's waking
  /// window and the suppression gate at once. A day where blocks look an hour
  /// out is otherwise indistinguishable from a scheduling bug, and this is
  /// the row that tells them apart.
  timezoneChanged,
}

/// One immutable fact, timestamped.
///
/// The events table is append-only: there is no update and no delete anywhere
/// in the stack. A correction is a new event. This is what makes the log
/// trustworthy as the app's memory.
@immutable
class VanEvent {
  /// Creates an event. [timestamp] must be UTC.
  VanEvent({
    required this.type,
    required this.timestamp,
    this.payload = const {},
    this.id = 0,
  }) : assert(timestamp.isUtc, 'timestamp must be UTC');

  /// Database row id. Zero until persisted.
  final int id;

  /// When it happened. UTC.
  final DateTime timestamp;

  /// What happened.
  final EventType type;

  /// Structured detail. Must be JSON-encodable.
  final Map<String, Object?> payload;

  /// Whether this event has been written to the log.
  bool get isPersisted => id != 0;

  /// Reads a payload field, or null when absent or the wrong type.
  T? field<T>(String key) {
    final value = payload[key];
    return value is T ? value : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VanEvent &&
          id == other.id &&
          timestamp == other.timestamp &&
          type == other.type &&
          _mapEquals(payload, other.payload);

  @override
  int get hashCode => Object.hash(id, timestamp, type, payload.length);

  @override
  String toString() =>
      'VanEvent(${type.name} @ ${timestamp.toIso8601String()}, $payload)';

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
