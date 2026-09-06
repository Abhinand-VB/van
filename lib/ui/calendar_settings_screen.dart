import 'package:flutter/material.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/ui/background.dart';

/// Which calendars Van plans around.
///
/// A page reached from the Now screen's app bar rather than a fourth tab. The
/// three-tab shell is deliberately minimal and a tab is the most expensive
/// thing Van has to spend; this is opened twice a year, once when the grant
/// is given and again if a calendar turns out to be noise.
///
/// Every calendar counts by default and the user removes what should not.
/// Someone who grants calendar access expects their calendar respected, and
/// a list that starts empty would silently do nothing and look broken.
class CalendarSettingsScreen extends StatefulWidget {
  /// Creates the screen.
  const CalendarSettingsScreen({
    required this.calendars,
    required this.preferences,
    super.key,
  });

  /// The device calendar, read for its list of sources.
  final Calendars calendars;

  /// Where the excluded set is stored.
  final CalendarPreferences preferences;

  @override
  State<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends State<CalendarSettingsScreen> {
  List<CalendarSource> _sources = const [];
  Set<String> _excluded = const {};
  bool _granted = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    inBackground(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final granted = await widget.calendars.hasPermission();
      // Asking for sources without the grant throws on a real device, and the
      // empty list it would produce reads as "you have no calendars" - which
      // is a different and much more confusing thing to be told.
      final sources = granted
          ? await widget.calendars.sources()
          : const <CalendarSource>[];
      final excluded = await widget.preferences.excluded();
      if (!mounted) return;
      setState(() {
        _granted = granted;
        _sources = sources;
        _excluded = excluded;
        _loading = false;
        _failed = false;
      });
    } on Object catch (_) {
      // Saying so beats an empty list: an unreadable calendar and no
      // calendars produce the same screen and mean opposite things.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _request() async {
    await widget.calendars.requestPermission();
    await _load();
  }

  Future<void> _setIncluded(String id, {required bool included}) async {
    await widget.preferences.setIncluded(id, included: included);
    final excluded = await widget.preferences.excluded();
    if (!mounted) return;
    setState(() => _excluded = excluded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendars')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Van plans around anything on these calendars, so it will '
                  'not schedule work during something you have already '
                  'agreed to.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Entries marked free, and all-day entries like birthdays, '
                  'do not take up time. Nothing is ever written to your '
                  'calendar.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Event names are shown on the calendar screen and are '
                  'never stored, logged, or put in a notification.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                if (_failed)
                  _Notice(
                    icon: Icons.error_outline,
                    text:
                        'Van could not read the calendar. Planning is using '
                        'its own sessions only.',
                    action: 'Try again',
                    onTap: _load,
                  )
                else if (!_granted)
                  _Notice(
                    icon: Icons.event_busy,
                    text:
                        'Van is planning your days as if nothing else is on '
                        'them. Allow it to read your calendar and it will '
                        'work around what is already there.',
                    action: 'Allow',
                    onTap: _request,
                  )
                else if (_sources.isEmpty)
                  Text(
                    'This phone has no calendars on it.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  for (final source in _sources)
                    CheckboxListTile(
                      value: !_excluded.contains(source.id),
                      // Awaited by the framework rather than fired and
                      // forgotten: this carries an intention of the user's,
                      // and `inBackground` would swallow a failed write and
                      // leave the box showing a preference Van did not store.
                      onChanged: (included) =>
                          _setIncluded(source.id, included: included ?? true),
                      title: Text(source.name),
                      subtitle: source.accountName.isEmpty
                          ? null
                          : Text(source.accountName),
                      secondary: source.colour == null
                          ? null
                          : _Swatch(colour: Color(source.colour!)),
                      contentPadding: EdgeInsets.zero,
                    ),
              ],
            ),
    );
  }
}

/// A dot in the calendar's own colour, so two calendars with the same name on
/// the same account can still be told apart.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
  );
}

/// A tappable row explaining why the list below it is empty.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String action;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: onTap, child: Text(action)),
            ),
          ],
        ),
      ),
    );
  }
}
