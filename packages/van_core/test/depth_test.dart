import 'package:test/test.dart';
import 'package:van_core/van_core.dart';

void main() {
  const reader = DepthReader();

  Task task({
    required String title,
    int? minutes,
    TaskDepth depth = TaskDepth.unknown,
  }) => Task(
    id: 't1',
    title: title,
    createdAt: DateTime.utc(2026, 9, 6, 8),
    estimatedMinutes: minutes,
    status: TaskStatus.active,
    depth: depth,
  );

  /// Two whole free days, so nothing below is about running out of room.
  ///
  /// Two rather than one because `maxSessionsPerDay` is 3: a four-hour deep
  /// task is three blocks without an opener and four with one, so a one-day
  /// fixture would fail on the daily cap and look like the opener had eaten
  /// thirty-five minutes of work. It has not - it has pushed the tail of it
  /// to tomorrow, which is a real consequence of this change and is what the
  /// totals below are asserting.
  List<FreeSlot> dayFrom(DateTime start) => [
    FreeSlot(start: start, end: start.add(const Duration(hours: 10))),
    FreeSlot(
      start: start.add(const Duration(days: 1)),
      end: start.add(const Duration(days: 1, hours: 10)),
    ),
  ];

  final now = DateTime.utc(2026, 9, 6, 9);

  List<WorkSession> plan(Task t) {
    final result = SessionPlanner(
      ids: SequentialIds('s'),
      waking: const WakingHours(utcOffset: Duration.zero),
    ).plan(task: t, slots: dayFrom(now), clock: FakeClock(now));
    return result.okOrNull ?? result.errOrNull!.scheduled;
  }

  group('reading depth off the wording', () {
    test('an errand is shallow', () {
      expect(reader.read('Email the landlord').depth, TaskDepth.shallow);
      expect(reader.read('Pay the gas bill').depth, TaskDepth.shallow);
      expect(reader.read('Book the dentist').depth, TaskDepth.shallow);
    });

    test('work that starts with deciding what to do is deep', () {
      expect(reader.read('Research the market').depth, TaskDepth.deep);
      expect(reader.read('Design the poster').depth, TaskDepth.deep);
      expect(reader.read('Write the dissertation').depth, TaskDepth.deep);
    });

    test('a piece of work is deep even with no verb on it', () {
      expect(reader.read('The assignment').depth, TaskDepth.deep);
      expect(reader.read('Chapter 3').depth, TaskDepth.deep);
    });

    test('nothing recognisable is unknown, and says so', () {
      final reading = reader.read('Bins');

      expect(reading.depth, TaskDepth.unknown);
      expect(reading.confidence, lessThan(0.2));
    });

    test('two kinds of verb at once is barely a reading at all', () {
      // "Email the design brief" is an errand about deep work, and a verb
      // list has no business being sure which. The confidence is the point of
      // the case, not the answer.
      final reading = reader.read('Email the design brief');

      expect(reading.depth, TaskDepth.shallow);
      expect(reading.confidence, lessThan(0.4));
    });

    test('an errand quoted at half a day is not called an errand', () {
      final reading = reader.read('Clean the flat', statedMinutes: 300);

      expect(reading.depth, TaskDepth.unknown);
    });

    test('a stated length nudges, it does not decide', () {
      // Two hours of emailing is still emailing. A length that outranked the
      // wording would call every long errand deep.
      expect(
        reader.read('Email the whole list', statedMinutes: 120).depth,
        TaskDepth.shallow,
      );
    });
  });

  group('what the planner does about depth', () {
    test('a deep task opens with a short block, not a slab', () {
      final blocks = plan(
        task(
          title: 'Write the dissertation',
          minutes: 240,
          depth: TaskDepth.deep,
        ),
      );

      // The behaviour, named rather than the heuristic: the first thing on
      // the calendar is twenty-five minutes for working out where to start,
      // because a four-hour task nobody has begun is not short of time, it is
      // short of a first step.
      expect(blocks.first.plannedMinutes, 25);
      expect(blocks.first.isOpener, isTrue);
      expect(blocks.skip(1).every((b) => b.isOpener), isFalse);
      expect(
        blocks.map((b) => b.plannedMinutes).reduce((a, b) => a + b),
        240,
        reason: 'the opener is part of the work, not extra to it',
      );
    });

    test('the opener can push the tail of the work to the next day', () {
      // Three blocks a day is the cap, and a four-hour deep task needs four
      // blocks once one of them is an opener. Nothing is lost; the last
      // thirty-five minutes land tomorrow. Worth a test because it is the
      // price of the opener and it is invisible from the first block alone.
      final blocks = plan(
        task(
          title: 'Write the dissertation',
          minutes: 240,
          depth: TaskDepth.deep,
        ),
      );

      expect(blocks, hasLength(4));
      expect(
        blocks.last.plannedStart.day,
        greaterThan(blocks.first.plannedStart.day),
      );
    });

    test('the blocks after the opener are ordinary blocks', () {
      final blocks = plan(
        task(
          title: 'Write the dissertation',
          minutes: 240,
          depth: TaskDepth.deep,
        ),
      );

      expect(
        blocks.skip(1).take(2).map((b) => b.plannedMinutes),
        everyElement(90),
      );
    });

    test('a shallow task is left alone however long it is', () {
      final blocks = plan(
        task(
          title: 'Email the whole list',
          minutes: 240,
          depth: TaskDepth.shallow,
        ),
      );

      expect(blocks.first.plannedMinutes, 90);
      expect(blocks.every((b) => !b.isOpener), isTrue);
    });

    test('deep work that already fits in one block is left alone', () {
      // Nobody bounces off a forty-minute block, and chopping one in two
      // would fragment a plan the user already agreed the length of.
      final blocks = plan(
        task(title: 'Draft the email', minutes: 40, depth: TaskDepth.deep),
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.plannedMinutes, 40);
      expect(blocks.single.isOpener, isFalse);
    });

    test('an unread task behaves exactly as it did before', () {
      final blocks = plan(task(title: 'Something', minutes: 240));

      expect(blocks.first.plannedMinutes, 90);
      expect(blocks.every((b) => !b.isOpener), isTrue);
    });
  });
}
