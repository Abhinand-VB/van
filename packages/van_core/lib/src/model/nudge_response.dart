import 'package:meta/meta.dart';

/// What the user did about a nudge.
enum ResponseType {
  /// Pressed START. The outcome Van exists to produce.
  started,

  /// Asked for more time.
  snoozed,

  /// Swiped it away without engaging.
  dismissed,

  /// Replied with an explanation.
  reason,

  /// Never acknowledged at all. Recorded by a later sweep, not by the user.
  ignored,
}

/// One reply to one nudge.
///
/// [latencySeconds] is the interesting field: the gap between being asked and
/// answering says more about whether a nudge landed than the answer does.
@immutable
class NudgeResponse {
  /// Creates a response record. [respondedAt] must be UTC.
  NudgeResponse({
    required this.id,
    required this.nudgeId,
    required this.response,
    required this.respondedAt,
    required this.latencySeconds,
    this.reasonText,
  }) : assert(respondedAt.isUtc, 'respondedAt must be UTC'),
       assert(latencySeconds >= 0, 'latencySeconds must not be negative'),
       assert(
         response != ResponseType.reason || reasonText != null,
         'a reason response must carry the reason text',
       );

  /// Stable identifier.
  final String id;

  /// The nudge being answered.
  final String nudgeId;

  /// What the user did.
  final ResponseType response;

  /// What they said, when they said anything.
  final String? reasonText;

  /// When they answered. UTC.
  final DateTime respondedAt;

  /// Seconds between delivery and this response.
  final int latencySeconds;

  /// Whether this response means work actually began.
  bool get ledToStart => response == ResponseType.started;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NudgeResponse &&
          id == other.id &&
          nudgeId == other.nudgeId &&
          response == other.response &&
          reasonText == other.reasonText &&
          respondedAt == other.respondedAt &&
          latencySeconds == other.latencySeconds;

  @override
  int get hashCode => Object.hash(
    id,
    nudgeId,
    response,
    reasonText,
    respondedAt,
    latencySeconds,
  );

  @override
  String toString() =>
      'NudgeResponse($id, ${response.name}, ${latencySeconds}s)';
}
