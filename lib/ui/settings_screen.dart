import 'package:flutter/material.dart';
import 'package:van/data/repositories/calendar_prefs.dart';
import 'package:van/platform/calendars.dart';
import 'package:van/platform/model_file.dart';
import 'package:van/ui/background.dart';
import 'package:van/ui/calendar_settings_screen.dart';
import 'package:van/ui/model_screen.dart';

/// Everything that is a setting, in one place.
///
/// It exists because the two things Van can be configured about had ended up
/// on opposite sides of the app: calendars behind a tune icon on the Calendar
/// tab, the on-device model behind an overflow menu on Now. Neither was
/// findable, and the second one was findable only if you already knew it was
/// there.
///
/// **A hub, not a control panel.** Each row states what is currently true and
/// opens the page that changes it - so the settings screen itself never owns
/// state, and there is exactly one place each setting is edited. That also
/// keeps `AGENTS.md`'s rule about there being no model picker honest: this
/// lists a model *file*, and routing stays in the config asset.
///
/// The Calendar tab's own tune icon still goes straight to calendars. Being
/// one tap from the thing you are looking at is worth more than symmetry.
class SettingsScreen extends StatefulWidget {
  /// Creates the settings hub.
  const SettingsScreen({
    required this.calendars,
    required this.preferences,
    required this.modelFile,
    this.onTryModel,
    super.key,
  });

  /// The device calendar, passed through to the calendars page.
  final Calendars calendars;

  /// Where the excluded set is stored.
  final CalendarPreferences preferences;

  /// The on-device model's weights.
  final ModelFile modelFile;

  /// Opens the probe from the model page, when this build can reach the
  /// engine.
  final VoidCallback? onTryModel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ModelFileStatus? _model;

  @override
  void initState() {
    super.initState();
    inBackground(_refresh());
  }

  Future<void> _refresh() async {
    final model = await widget.modelFile.status();
    if (!mounted) return;
    setState(() => _model = model);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    // The row's summary is a statement about what is true, so it has to be
    // re-read when you come back from the page that could have changed it.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = _model;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Calendars'),
            subtitle: const Text(
              'Which calendars Van plans around. It never writes to them.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => inBackground(
              _open(
                CalendarSettingsScreen(
                  calendars: widget.calendars,
                  preferences: widget.preferences,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('On-device model'),
            subtitle: Text(
              model == null
                  ? 'Optional. Van works fully without it.'
                  : model.present
                  ? 'Installed · ${model.size}'
                  : 'Not installed. Van works fully without it.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => inBackground(
              _open(
                ModelScreen(
                  modelFile: widget.modelFile,
                  onTryIt: widget.onTryModel,
                ),
              ),
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              // The one thing worth saying on a settings screen for an app
              // whose whole premise is that it runs offline.
              'Van keeps everything on this phone. It has no account, no '
              'server and no analytics, and the only thing it ever sends '
              'anywhere is a download you ask for.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
