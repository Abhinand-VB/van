import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/platform/model_file.dart';
import 'package:van/platform/notifications.dart';
import 'package:van/platform/speech.dart';
import 'package:van/ui/calendar_screen.dart';
import 'package:van/ui/chat_screen.dart';
import 'package:van/ui/now_screen.dart';
import 'package:van/ui/tab_pulse.dart';
import 'package:van/ui/task_list_screen.dart';
import 'package:van_core/van_core.dart';

/// The four things Van does, one tap apart.
///
/// Now is first and is the default, because the whole product is one next
/// action. Chat and Tasks exist for the two moments Now cannot serve: getting
/// something out of your head while checking Van understood it, and seeing
/// everything you have not done.
///
/// **Calendar is the fourth, added at the owner's request**, and this comment
/// used to say three was the ceiling. What changed is that Van now plans
/// around commitments it will not name: a block moves to the afternoon and
/// the reason is a meeting the app can show as a shape but never describe.
/// Without a timeline, that reason is invisible everywhere in Van. The
/// original objection still stands as a warning rather than a rule - the
/// danger of a fourth tab is that it invites a fifth.
class VanShell extends StatefulWidget {
  /// Creates the shell.
  const VanShell({
    required this.service,
    required this.clock,
    required this.notifications,
    required this.calendars,
    required this.calendarPreferences,
    this.speech = const UnsupportedSpeech(),
    this.modelFile = const UnsupportedModelFile(),
    this.onTryModel,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Passed to the Now screen for its permission banner.
  final Notifications notifications;

  /// Passed through to the calendar settings page.
  final Calendars calendars;

  /// Passed through to the calendar settings page.
  final CalendarPreferences calendarPreferences;

  /// Passed to both composers for their microphone button.
  final Speech speech;

  /// Passed to the Now screen for the on-device model page.
  final ModelFile modelFile;

  /// Opens the model probe, when this build can reach the engine.
  final VoidCallback? onTryModel;

  @override
  State<VanShell> createState() => _VanShellState();
}

class _VanShellState extends State<VanShell> {
  int _tab = 0;

  /// One per tab. Poked when that tab becomes visible, so the screen behind
  /// it reloads - an `IndexedStack` keeps every screen alive, which is what
  /// saves a half-typed sentence in Chat and is also why none of them would
  /// otherwise notice that the data changed while it was hidden.
  final List<TabPulse> _pulses = List.generate(
    4,
    (_) => TabPulse(),
    growable: false,
  );

  @override
  void dispose() {
    for (final pulse in _pulses) {
      pulse.dispose();
    }
    super.dispose();
  }

  void _select(int index) {
    setState(() => _tab = index);
    _pulses[index].pulse();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack rather than rebuilding: switching tabs must not throw
      // away a half-typed sentence in Chat, and re-running the Now screen's
      // sweep on every tab tap would be wasteful.
      body: IndexedStack(
        index: _tab,
        children: [
          NowScreen(
            service: widget.service,
            clock: widget.clock,
            notifications: widget.notifications,
            calendars: widget.calendars,
            calendarPreferences: widget.calendarPreferences,
            speech: widget.speech,
            modelFile: widget.modelFile,
            onTryModel: widget.onTryModel,
            refreshOn: _pulses[0],
          ),
          CalendarScreen(
            service: widget.service,
            clock: widget.clock,
            calendars: widget.calendars,
            calendarPreferences: widget.calendarPreferences,
            refreshOn: _pulses[1],
          ),
          ChatScreen(
            service: widget.service,
            clock: widget.clock,
            speech: widget.speech,
            refreshOn: _pulses[2],
          ),
          TaskListScreen(
            service: widget.service,
            clock: widget.clock,
            refreshOn: _pulses[3],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Now',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
        ],
      ),
    );
  }
}
