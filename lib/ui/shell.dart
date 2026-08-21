import 'package:flutter/material.dart';
import 'package:van/app/van_service.dart';
import 'package:van/platform/notifications.dart';
import 'package:van/ui/chat_screen.dart';
import 'package:van/ui/now_screen.dart';
import 'package:van/ui/task_list_screen.dart';
import 'package:van_core/van_core.dart';

/// The three things Van does, one tap apart.
///
/// Now is first and is the default, because the whole product is one next
/// action. Chat and Tasks exist for the two moments Now cannot serve: getting
/// something out of your head while checking Van understood it, and seeing
/// everything you have not done. Three is the ceiling - a fourth tab would be
/// the beginning of a productivity system.
class VanShell extends StatefulWidget {
  /// Creates the shell.
  const VanShell({
    required this.service,
    required this.clock,
    required this.notifications,
    super.key,
  });

  /// The application service.
  final VanService service;

  /// Source of the current time.
  final Clock clock;

  /// Passed to the Now screen for its permission banner.
  final Notifications notifications;

  @override
  State<VanShell> createState() => _VanShellState();
}

class _VanShellState extends State<VanShell> {
  int _tab = 0;

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
          ),
          ChatScreen(service: widget.service, clock: widget.clock),
          TaskListScreen(service: widget.service, clock: widget.clock),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Now',
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
