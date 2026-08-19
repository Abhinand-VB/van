import 'package:drift/drift.dart';
import 'package:nova_core/nova_core.dart';

/// Enums are stored by *name*, not index.
///
/// `intEnum` would silently corrupt every existing row the first time someone
/// reorders an enum or inserts a case in the middle. Storing the name costs a
/// few bytes and makes the database readable when debugging.
@TableIndex(name: 'idx_tasks_deadline', columns: {#deadlineUtc})
@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get deadlineUtc => integer().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  TextColumn get priority => textEnum<Priority>()();
  TextColumn get status => textEnum<TaskStatus>()();
  IntColumn get createdUtc => integer()();
  TextColumn get source => textEnum<TaskSource>()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The blocks Nova actually nudges about.
///
/// Indexed on planned start because the nudge engine's hot query is always
/// "what is due between now and the next tick".
@TableIndex(name: 'idx_sessions_planned_start', columns: {#plannedStartUtc})
@TableIndex(name: 'idx_sessions_task', columns: {#taskId})
@DataClassName('WorkSessionRow')
class WorkSessions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  IntColumn get plannedStartUtc => integer()();
  IntColumn get plannedMinutes => integer()();
  IntColumn get actualStartUtc => integer().nullable()();
  IntColumn get actualEndUtc => integer().nullable()();
  TextColumn get status => textEnum<SessionStatus>()();
  IntColumn get rescheduleCount => integer().withDefault(const Constant(0))();
  TextColumn get parentSessionId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Every interruption Nova considered, including the ones it decided against.
@TableIndex(name: 'idx_nudges_scheduled', columns: {#scheduledUtc})
@TableIndex(name: 'idx_nudges_session', columns: {#sessionId})
@DataClassName('NudgeRow')
class Nudges extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get type => textEnum<NudgeType>()();
  IntColumn get importance => integer()();
  TextColumn get level => textEnum<InterventionLevel>()();
  IntColumn get scheduledUtc => integer()();
  IntColumn get deliveredUtc => integer().nullable()();
  TextColumn get copy => text()();
  TextColumn get templateId => text().nullable()();
  TextColumn get backendId => text().nullable()();
  BoolColumn get wasSuppressed =>
      boolean().withDefault(const Constant(false))();
  TextColumn get suppressionReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What the user did about each nudge.
@TableIndex(name: 'idx_responses_nudge', columns: {#nudgeId})
@DataClassName('NudgeResponseRow')
class NudgeResponses extends Table {
  TextColumn get id => text()();
  TextColumn get nudgeId => text().references(Nudges, #id)();
  TextColumn get response => textEnum<ResponseType>()();
  TextColumn get reasonText => text().nullable()();
  IntColumn get respondedUtc => integer()();
  IntColumn get latencySeconds => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The append-only firehose.
///
/// There is deliberately no update or delete path to this table anywhere in
/// the stack - see `EventRepo`. A correction is a new row. This is the only
/// reason the log can be trusted later as the app's memory.
@TableIndex(name: 'idx_events_ts', columns: {#tsUtc})
@TableIndex(name: 'idx_events_type', columns: {#type})
@DataClassName('EventRow')
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tsUtc => integer()();
  TextColumn get type => textEnum<EventType>()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
}

/// Small key/value store for things that are not worth a table.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
