import 'dart:convert';

/// Shared salvage logic for turning model output into a JSON object.
///
/// Small local models wrap JSON in markdown fences, prepend "Sure, here is",
/// emit `"45"` where an int was asked for, and occasionally stop mid-object.
/// Cloud models with native structured output rarely do any of this - but the
/// path is shared deliberately so it stays exercised by every backend rather
/// than rotting until the day a local model needs it.
class JsonSalvage {
  const JsonSalvage._();

  /// Extracts the first JSON object in [raw], or null if there is none.
  ///
  /// Scans with brace depth rather than a regex so nested objects survive, and
  /// ignores braces inside string literals.
  static Map<String, Object?>? extractObject(String raw) {
    final text = _stripFences(raw);
    final start = text.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < text.length; i++) {
      final ch = text[i];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }

      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return _decode(text.substring(start, i + 1));
        }
      }
    }
    // Ran off the end: the object was truncated.
    return null;
  }

  static Map<String, Object?>? _decode(String candidate) {
    try {
      final decoded = jsonDecode(candidate);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _stripFences(String raw) {
    var text = raw.trim();
    if (!text.contains('```')) return text;
    text = text.replaceAll(RegExp('```(?:json)?', caseSensitive: false), '');
    return text.trim();
  }

  /// Reads a string field, tolerating a number where text was expected.
  static String? readString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    if (value is num || value is bool) return value.toString();
    return null;
  }

  /// Reads an int field, tolerating `"45"` and `45.0`.
  static int? readInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      return parsed?.round();
    }
    return null;
  }

  /// Reads a UTC instant from an ISO-8601 string.
  static DateTime? readUtcDateTime(Map<String, Object?> json, String key) {
    final value = readString(json, key);
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc();
  }

  /// Reads one of [allowed], case-insensitively. Null when absent or unknown.
  static String? readEnum(
    Map<String, Object?> json,
    String key,
    Iterable<String> allowed,
  ) {
    final value = readString(json, key)?.toLowerCase();
    if (value == null) return null;
    for (final option in allowed) {
      if (option.toLowerCase() == value) return option;
    }
    return null;
  }
}
