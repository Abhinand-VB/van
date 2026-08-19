/// Supplies identifiers for newly created domain objects.
///
/// The core cannot generate UUIDs itself without taking a dependency, and more
/// importantly a scheduler that invents random ids is not reproducible in a
/// test. Callers inject the strategy; the app uses UUIDs, tests use counters.
abstract interface class IdGenerator {
  /// Returns a fresh identifier, never previously returned by this instance.
  String next();
}

/// A deterministic [IdGenerator] for tests and the simulation harness.
class SequentialIds implements IdGenerator {
  /// Creates a generator producing `prefix1`, `prefix2`, and so on.
  SequentialIds([this.prefix = 'id']);

  /// Prepended to every generated id.
  final String prefix;

  int _n = 0;

  @override
  String next() => '$prefix${++_n}';
}
