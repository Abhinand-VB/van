import 'package:meta/meta.dart';

/// The return type for anything in the core that can fail for an expected
/// reason.
///
/// Van's domain layer does not throw across boundaries. A scheduler that
/// cannot fit a task before its deadline has not encountered a bug; it has
/// produced a fact the caller must decide how to present. Exceptions are
/// reserved for programmer error. See AGENTS.md, "Conventions".
@immutable
sealed class Result<T, E> {
  const Result();

  /// Whether this holds a success value.
  bool get isOk => this is Ok<T, E>;

  /// Whether this holds a failure value.
  bool get isErr => this is Err<T, E>;

  /// The success value, or null.
  T? get okOrNull => switch (this) {
    Ok<T, E>(:final value) => value,
    Err<T, E>() => null,
  };

  /// The failure value, or null.
  E? get errOrNull => switch (this) {
    Ok<T, E>() => null,
    Err<T, E>(:final error) => error,
  };

  /// The success value, or [fallback] when this is an [Err].
  T unwrapOr(T fallback) => switch (this) {
    Ok<T, E>(:final value) => value,
    Err<T, E>() => fallback,
  };

  /// Transforms the success value, leaving a failure untouched.
  Result<U, E> map<U>(U Function(T value) transform) => switch (this) {
    Ok<T, E>(:final value) => Ok<U, E>(transform(value)),
    Err<T, E>(:final error) => Err<U, E>(error),
  };

  /// Transforms the failure value, leaving a success untouched.
  Result<T, F> mapErr<F>(F Function(E error) transform) => switch (this) {
    Ok<T, E>(:final value) => Ok<T, F>(value),
    Err<T, E>(:final error) => Err<T, F>(transform(error)),
  };

  /// Collapses both branches into a single value.
  R fold<R>(R Function(T value) onOk, R Function(E error) onErr) =>
      switch (this) {
        Ok<T, E>(:final value) => onOk(value),
        Err<T, E>(:final error) => onErr(error),
      };
}

/// A successful [Result].
@immutable
final class Ok<T, E> extends Result<T, E> {
  /// Wraps [value] as a success.
  const Ok(this.value);

  /// The success value.
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ok<T, E> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'Ok($value)';
}

/// A failed [Result].
@immutable
final class Err<T, E> extends Result<T, E> {
  /// Wraps [error] as a failure.
  const Err(this.error);

  /// The failure value.
  final E error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Err<T, E> &&
          runtimeType == other.runtimeType &&
          error == other.error;

  @override
  int get hashCode => Object.hash(runtimeType, error);

  @override
  String toString() => 'Err($error)';
}
