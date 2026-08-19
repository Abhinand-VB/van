import 'package:meta/meta.dart';

/// Everything Nova records about what happened.
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
}

/// One immutable fact, timestamped.
///
/// The events table is append-only: there is no update and no delete anywhere
/// in the stack. A correction is a new event. This is what makes the log
/// trustworthy as the app's memory.
@immutable
class NovaEvent {
  /// Creates an event. [timestamp] must be UTC.
  NovaEvent({
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
      other is NovaEvent &&
          id == other.id &&
          timestamp == other.timestamp &&
          type == other.type &&
          _mapEquals(payload, other.payload);

  @override
  int get hashCode => Object.hash(id, timestamp, type, payload.length);

  @override
  String toString() =>
      'NovaEvent(${type.name} @ ${timestamp.toIso8601String()}, $payload)';

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
