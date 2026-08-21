import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:van/data/db/database.dart';
import 'package:van_core/van_core.dart';

/// Row-to-domain translation lives here so that repositories stay readable and
/// no Drift type ever escapes the data layer.
///
/// Instants are stored as UTC epoch milliseconds. SQLite has no date type, and
/// storing local time would make every query wrong twice a year.
DateTime _utc(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

int _millis(DateTime time) => time.toUtc().millisecondsSinceEpoch;

/// Converts a persisted task row into the domain model.
Task taskFromRow(TaskRow row) => Task(
  id: row.id,
  title: row.title,
  createdAt: _utc(row.createdUtc),
  notes: row.notes,
  deadline: row.deadlineUtc == null ? null : _utc(row.deadlineUtc!),
  estimatedMinutes: row.estimatedMinutes,
  priority: row.priority,
  status: row.status,
  source: row.source,
);

/// Converts a domain task into a row for insert or replace.
TasksCompanion taskToRow(Task task) => TasksCompanion.insert(
  id: task.id,
  title: task.title,
  notes: Value(task.notes),
  deadlineUtc: Value(task.deadline == null ? null : _millis(task.deadline!)),
  estimatedMinutes: Value(task.estimatedMinutes),
  priority: task.priority,
  status: task.status,
  createdUtc: _millis(task.createdAt),
  source: task.source,
);

/// Converts a persisted session row into the domain model.
WorkSession sessionFromRow(WorkSessionRow row) => WorkSession(
  id: row.id,
  taskId: row.taskId,
  plannedStart: _utc(row.plannedStartUtc),
  plannedMinutes: row.plannedMinutes,
  actualStart: row.actualStartUtc == null ? null : _utc(row.actualStartUtc!),
  actualEnd: row.actualEndUtc == null ? null : _utc(row.actualEndUtc!),
  status: row.status,
  rescheduleCount: row.rescheduleCount,
  parentSessionId: row.parentSessionId,
);

/// Converts a domain session into a row for insert or replace.
WorkSessionsCompanion sessionToRow(WorkSession session) =>
    WorkSessionsCompanion.insert(
      id: session.id,
      taskId: session.taskId,
      plannedStartUtc: _millis(session.plannedStart),
      plannedMinutes: session.plannedMinutes,
      actualStartUtc: Value(
        session.actualStart == null ? null : _millis(session.actualStart!),
      ),
      actualEndUtc: Value(
        session.actualEnd == null ? null : _millis(session.actualEnd!),
      ),
      status: session.status,
      rescheduleCount: Value(session.rescheduleCount),
      parentSessionId: Value(session.parentSessionId),
    );

/// Converts a persisted nudge row into the domain model.
Nudge nudgeFromRow(NudgeRow row) => Nudge(
  id: row.id,
  type: row.type,
  importance: row.importance,
  level: row.level,
  scheduledAt: _utc(row.scheduledUtc),
  copy: row.copy,
  sessionId: row.sessionId,
  deliveredAt: row.deliveredUtc == null ? null : _utc(row.deliveredUtc!),
  templateId: row.templateId,
  backendId: row.backendId,
  wasSuppressed: row.wasSuppressed,
  suppressionReason: row.suppressionReason,
);

/// Converts a domain nudge into a row for insert or replace.
NudgesCompanion nudgeToRow(Nudge nudge) => NudgesCompanion.insert(
  id: nudge.id,
  sessionId: Value(nudge.sessionId),
  type: nudge.type,
  importance: nudge.importance,
  level: nudge.level,
  scheduledUtc: _millis(nudge.scheduledAt),
  deliveredUtc: Value(
    nudge.deliveredAt == null ? null : _millis(nudge.deliveredAt!),
  ),
  copy: nudge.copy,
  templateId: Value(nudge.templateId),
  backendId: Value(nudge.backendId),
  wasSuppressed: Value(nudge.wasSuppressed),
  suppressionReason: Value(nudge.suppressionReason),
);

/// Converts a persisted response row into the domain model.
NudgeResponse responseFromRow(NudgeResponseRow row) => NudgeResponse(
  id: row.id,
  nudgeId: row.nudgeId,
  response: row.response,
  respondedAt: _utc(row.respondedUtc),
  latencySeconds: row.latencySeconds,
  reasonText: row.reasonText,
);

/// Converts a domain response into a row for insert.
NudgeResponsesCompanion responseToRow(NudgeResponse response) =>
    NudgeResponsesCompanion.insert(
      id: response.id,
      nudgeId: response.nudgeId,
      response: response.response,
      reasonText: Value(response.reasonText),
      respondedUtc: _millis(response.respondedAt),
      latencySeconds: response.latencySeconds,
    );

/// Converts a persisted event row into the domain model.
///
/// A payload that fails to decode yields an empty map rather than throwing:
/// the log is append-only and historical, so one malformed row must never make
/// the rest of it unreadable.
VanEvent eventFromRow(EventRow row) {
  Map<String, Object?> payload;
  try {
    final decoded = jsonDecode(row.payloadJson);
    payload = decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    payload = const {};
  }
  return VanEvent(
    id: row.id,
    type: row.type,
    timestamp: _utc(row.tsUtc),
    payload: payload,
  );
}

/// Converts a domain event into a row for append.
///
/// The session id is copied out of the payload here, at write time, so it
/// can be indexed. The payload remains the record of what happened.
EventsCompanion eventToRow(VanEvent event) => EventsCompanion.insert(
  tsUtc: _millis(event.timestamp),
  type: event.type,
  payloadJson: Value(jsonEncode(event.payload)),
  sessionId: Value(event.field<String>('sessionId')),
);
