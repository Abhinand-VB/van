import 'package:drift/drift.dart';
import 'package:van/data/db/database.dart';
import 'package:van/data/repositories/mappers.dart';
import 'package:van_core/van_core.dart';

/// The append-only event log.
///
/// This class deliberately exposes no update and no delete. That is not an
/// oversight and it is not a TODO: the log is Van's memory, and the adaptive
/// intervention policy in phase 4 can only be trusted if nothing has been
/// rewritten behind it. A correction is a new event.
///
/// If you find yourself wanting to edit a row here, you want a new event type.
class EventRepo {
  /// Creates a repository over [_db].
  EventRepo(this._db, this._clock);

  final VanDatabase _db;
  final Clock _clock;

  /// Appends one event, stamped with the current time unless [at] is given.
  ///
  /// Returns the persisted event, including the assigned row id.
  Future<VanEvent> append(
    EventType type, [
    Map<String, Object?> payload = const {},
    DateTime? at,
  ]) async {
    final event = VanEvent(
      type: type,
      timestamp: at ?? _clock.now(),
      payload: payload,
    );
    final id = await _db.into(_db.events).insert(eventToRow(event));
    return VanEvent(
      id: id,
      type: event.type,
      timestamp: event.timestamp,
      payload: event.payload,
    );
  }

  /// Appends several events in one transaction.
  ///
  /// Used when a single user action produces a burst, so that a crash midway
  /// cannot leave a half-recorded story.
  Future<void> appendAll(Iterable<VanEvent> events) =>
      _db.batch((b) => b.insertAll(_db.events, events.map(eventToRow)));

  /// Every event at or after [from], oldest first.
  Future<List<VanEvent>> since(DateTime from) {
    final cutoff = from.toUtc().millisecondsSinceEpoch;
    final query = _db.select(_db.events)
      ..where((e) => e.tsUtc.isBiggerOrEqualValue(cutoff))
      ..orderBy([(e) => OrderingTerm.asc(e.tsUtc)]);
    return query.map(eventFromRow).get();
  }

  /// The most recent events of [type], newest first.
  Future<List<VanEvent>> ofType(EventType type, {int limit = 100}) {
    final query = _db.select(_db.events)
      ..where((e) => e.type.equalsValue(type))
      ..orderBy([(e) => OrderingTerm.desc(e.tsUtc)])
      ..limit(limit);
    return query.map(eventFromRow).get();
  }

  /// Every event whose payload names [sessionId], oldest first.
  ///
  /// The session id lives inside the JSON payload rather than a column, so
  /// this is a scan. That is acceptable at single-user volumes and keeps the
  /// log schema-free; revisit if the table ever grows past a few hundred
  /// thousand rows.
  Future<List<VanEvent>> forSession(String sessionId) async {
    final all = await (_db.select(
      _db.events,
    )..orderBy([(e) => OrderingTerm.asc(e.tsUtc)])).map(eventFromRow).get();
    return all.where((e) => e.field<String>('sessionId') == sessionId).toList();
  }

  /// Total number of recorded events.
  Future<int> count() async {
    final expr = _db.events.id.count();
    final row = await (_db.selectOnly(
      _db.events,
    )..addColumns([expr])).getSingle();
    return row.read(expr) ?? 0;
  }

  /// The whole log, oldest first. Intended for debugging and for the
  /// simulation harness, not for the UI.
  Future<List<VanEvent>> all() =>
      (_db.select(_db.events)..orderBy([
            (e) => OrderingTerm.asc(e.tsUtc),
            (e) => OrderingTerm.asc(e.id),
          ]))
          .map(eventFromRow)
          .get();
}
