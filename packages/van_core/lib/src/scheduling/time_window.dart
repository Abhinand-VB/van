import 'package:meta/meta.dart';

/// A stretch of time that is already spoken for.
///
/// These come from two places and the planner cannot tell them apart, which
/// is the point: Van's own work sessions, and the device calendar through
/// `CalendarFilter`. Adding a third source costs the domain nothing.
@immutable
class Commitment {
  /// Creates a commitment. Both instants must be UTC and [start] must precede
  /// [end].
  Commitment({required this.start, required this.end, this.label = ''})
    : assert(start.isUtc && end.isUtc, 'commitments must be in UTC'),
      assert(start != end, 'a commitment must have a duration');

  /// When it begins. UTC.
  final DateTime start;

  /// When it ends. UTC.
  final DateTime end;

  /// Human-readable description, for debugging and the timeline dump.
  final String label;

  /// Whether this commitment overlaps [other] at all.
  bool overlaps(Commitment other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  @override
  String toString() =>
      'Commitment(${start.toIso8601String()}..${end.toIso8601String()}'
      '${label.isEmpty ? '' : ', $label'})';
}

/// A stretch of time available for work.
@immutable
class FreeSlot {
  /// Creates a slot. Both instants must be UTC.
  FreeSlot({required this.start, required this.end})
    : assert(start.isUtc && end.isUtc, 'slots must be in UTC'),
      assert(start != end, 'a slot must have a duration');

  /// When it begins. UTC.
  final DateTime start;

  /// When it ends. UTC.
  final DateTime end;

  /// How long the slot is.
  int get minutes => end.difference(start).inMinutes;

  /// Returns the part of this slot that starts at or after [from], or null if
  /// nothing is left.
  FreeSlot? clippedFrom(DateTime from) {
    if (!from.isAfter(start)) return this;
    if (!from.isBefore(end)) return null;
    return FreeSlot(start: from, end: end);
  }

  /// Returns the part of this slot that ends at or before [to], or null if
  /// nothing is left.
  FreeSlot? clippedTo(DateTime to) {
    if (!to.isBefore(end)) return this;
    if (!to.isAfter(start)) return null;
    return FreeSlot(start: start, end: to);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeSlot && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'FreeSlot(${start.toIso8601String()}..${end.toIso8601String()}, '
      '${minutes}m)';
}

/// The hours in a day the user is plausibly awake and willing to work.
///
/// Waking hours are inherently a *local* concept while every instant Van
/// stores is UTC. Rather than call `toLocal()` - which would make the
/// scheduler behave differently on the CI machine than on the phone - the
/// offset is passed in explicitly, keeping the core deterministic.
@immutable
class WakingHours {
  /// Creates a waking window. [startHour] is inclusive, [endHour] exclusive,
  /// both in local time on a 24-hour clock.
  const WakingHours({
    this.startHour = 8,
    this.endHour = 23,
    this.utcOffset = Duration.zero,
  }) : assert(startHour >= 0 && startHour < 24, 'startHour must be 0-23'),
       assert(endHour > 0 && endHour <= 24, 'endHour must be 1-24'),
       assert(startHour < endHour, 'startHour must precede endHour');

  /// First hour of the day work may be scheduled, local time, inclusive.
  final int startHour;

  /// Hour at which scheduling stops, local time, exclusive.
  final int endHour;

  /// Local time minus UTC. IST is `Duration(hours: 5, minutes: 30)`.
  final Duration utcOffset;

  /// The same window, read in a different timezone.
  ///
  /// The hours are the user's preference and do not move with them: someone
  /// who works 08:00-23:00 still works 08:00-23:00 after a flight, in the new
  /// local time. Only the offset those hours are resolved against changes.
  WakingHours withUtcOffset(Duration newOffset) =>
      WakingHours(startHour: startHour, endHour: endHour, utcOffset: newOffset);

  /// Converts a UTC instant to the wall-clock time the user would read.
  DateTime toLocalWall(DateTime utc) => utc.add(utcOffset);

  /// Converts a wall-clock instant back to UTC.
  DateTime toUtcInstant(DateTime localWall) => localWall.subtract(utcOffset);

  /// The waking window for the local day containing [utcInstant], as UTC
  /// bounds.
  FreeSlot windowForDayOf(DateTime utcInstant) {
    final wall = toLocalWall(utcInstant);
    final dayStart = DateTime.utc(wall.year, wall.month, wall.day);
    return FreeSlot(
      start: toUtcInstant(dayStart.add(Duration(hours: startHour))),
      end: toUtcInstant(dayStart.add(Duration(hours: endHour))),
    );
  }

  @override
  String toString() =>
      'WakingHours($startHour:00-$endHour:00, offset=$utcOffset)';
}
