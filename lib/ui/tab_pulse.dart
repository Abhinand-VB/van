import 'package:flutter/foundation.dart';

/// A nudge to a tab that it has just become the visible one.
///
/// The shell keeps every tab alive in an `IndexedStack`, which is deliberate —
/// switching tabs must not throw away a half-typed sentence in Chat, and
/// rebuilding the Now screen on every tap would re-run its sweep. The cost is
/// that a screen you return to is showing whatever it loaded the last time it
/// was looked at, and Van's data changes underneath all of them: a capture on
/// Now changes Tasks, finishing a task on Tasks changes Now, a sweep changes
/// both.
///
/// So the shell pokes the tab being shown, and the tab reloads. A [Listenable]
/// rather than an index each screen has to compare against itself, because a
/// screen should not have to know its own position in a navigation bar to know
/// it is on screen.
class TabPulse extends ChangeNotifier {
  /// Tells whoever is listening that they are now visible.
  void pulse() => notifyListeners();
}
