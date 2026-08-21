// Prints what Van's event log says happened.
//
// Van's design principle is that the append-only log is the app's memory. It
// was write-only in practice: nothing could read it back without hand-written
// SQL against a pulled database file. This is the reader.
//
// Pull the database first (see docs/OVERNIGHT.md section 3a):
//
//   adb exec-out run-as dev.van.app cat \
//     /data/data/dev.van.app/app_flutter/van.sqlite > build/van.sqlite
//   dart run tool/week_report.dart build/van.sqlite
//
// Read-only: it opens the file, selects, and closes. It never writes, so a
// copy pulled off the phone stays exactly as the phone had it.

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:van_core/van_core.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/week_report.dart <van.sqlite>');
    exit(64);
  }

  final path = args.first;
  if (!File(path).existsSync()) {
    stderr.writeln('no such file: $path');
    exit(66);
  }

  final events = _read(path);
  if (events.isEmpty) {
    stdout.writeln('No events in $path. Nothing to report.');
    return;
  }
  stdout.write(render(WeekReview.from(events), events.length));
}

/// Reads every event row, skipping any this build does not recognise.
///
/// An unknown `type` means the file was written by a newer build. Skipping it
/// is right: the log is append-only and historical, and one unreadable row
/// must never make the rest of it unreadable - the same rule `eventFromRow`
/// follows for a malformed payload.
List<VanEvent> _read(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      'SELECT type, ts_utc, payload_json FROM events ORDER BY ts_utc',
    );
    final byName = {for (final t in EventType.values) t.name: t};

    final events = <VanEvent>[];
    for (final row in rows) {
      final type = byName[row['type'] as String?];
      if (type == null) continue;

      Map<String, Object?> payload;
      try {
        final decoded = jsonDecode(row['payload_json'] as String? ?? '{}');
        payload = decoded is Map<String, dynamic> ? decoded : const {};
      } on FormatException {
        payload = const {};
      }

      events.add(
        VanEvent(
          type: type,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            row['ts_utc'] as int,
            isUtc: true,
          ),
          payload: payload,
        ),
      );
    }
    return events;
  } finally {
    db.close();
  }
}

/// Formats [review] as plain text. Separate from [main] so it can be tested.
String render(WeekReview review, int rowCount) {
  final out = StringBuffer()
    ..writeln('Van — what the log says')
    ..writeln('=======================')
    ..writeln('$rowCount events, ${_day(review.from)} to ${_day(review.to)}')
    ..writeln();

  out
    ..writeln('Work')
    ..writeln('  tasks captured     ${review.tasksCaptured}')
    ..writeln('  blocks planned     ${review.blocksPlanned}')
    ..writeln(
      '  started            ${review.blocksStarted}'
      '${_rate(review.startRate)}',
    )
    ..writeln(
      '  ran to the end     ${review.blocksCompleted}'
      '${_rate(review.completionRate, of: 'of started')}',
    )
    ..writeln('  stopped early      ${review.blocksPartial}')
    ..writeln('  missed             ${review.blocksMissed}')
    ..writeln(_group('    ', review.missedByReason))
    ..writeln('Moves')
    ..writeln(_group('    ', review.reschedulesByReason))
    ..writeln(
      '    moved, then missed again  ${review.movedThenMissedAgain}'
      '   <- the one that matters',
    )
    ..writeln()
    ..writeln('Nudges')
    ..writeln('  scheduled          ${review.nudgesScheduled}')
    ..writeln('  answered           ${review.nudgesDelivered}')
    ..writeln('  held back          ${review.nudgesSuppressed}')
    ..writeln(_group('    ', review.suppressedByReason))
    ..writeln(
      '  (Van marks a nudge delivered only when a rung is answered, so',
    )
    ..writeln('   "answered" is not a delivery count - one that appeared')
    ..writeln('   and was ignored is invisible here. See STATUS 3p.)');

  if (review.nudgeScheduleFailures > 0) {
    out.writeln(
      '  REFUSED BY ANDROID ${review.nudgeScheduleFailures}'
      '   <- worth a look',
    );
  }

  out
    ..writeln()
    ..writeln('Answers')
    ..writeln(_group('    ', review.responsesByType))
    ..writeln('Negotiation')
    ..writeln(_group('    ', review.proposalsByAction))
    ..writeln('    from a model  ${review.proposalsFromModel}')
    ..writeln('    refused       ${review.proposalsRefused}');

  return out.toString();
}

String _day(DateTime? at) =>
    at == null ? '?' : at.toIso8601String().substring(0, 10);

String _rate(double? value, {String of = 'of planned'}) =>
    value == null ? '' : '   ${(value * 100).round()}% $of';

/// Renders a count map, or says plainly that there is nothing in it.
///
/// An empty group prints "none" rather than nothing at all: a heading with no
/// lines under it reads like a bug in the report, and the difference between
/// "no suppressions" and "the report broke" is exactly what someone tuning a
/// limit needs to be sure of.
String _group(String indent, Map<String, int> counts) {
  if (counts.isEmpty) return '${indent}none';
  final keys = counts.keys.toList()..sort();
  return keys.map((k) => '$indent${k.padRight(18)} ${counts[k]}').join('\n');
}
