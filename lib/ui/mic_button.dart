import 'package:flutter/material.dart';
import 'package:van/platform/speech.dart';
import 'package:van/ui/background.dart';

/// Says the thing instead of typing it.
///
/// Push-to-talk, one utterance a press. There is no wake word and nothing is
/// held open between presses - see `docs/WP_VOICE.md` 2.1, which argues that
/// an always-listening app buys nothing here, because Van's whole interaction
/// model already has the phone in your hand at the moment voice is wanted.
///
/// **What comes back is a draft.** This hands the transcript to [onHeard] and
/// nothing else happens: no capture, no send. Recognition is wrong often
/// enough that committing straight from speech would put tasks nobody said
/// into a log that never deletes, and filling the field the user was about to
/// type in costs one tap and makes the mistake visible instead of permanent.
///
/// One widget for both composers, because the degradation rules are the
/// interesting part and two copies of them would eventually disagree about
/// what happens when a phone cannot listen offline.
class MicButton extends StatefulWidget {
  /// Creates a microphone button.
  const MicButton({
    required this.speech,
    required this.onHeard,
    this.enabled = true,
    super.key,
  });

  /// The recogniser.
  final Speech speech;

  /// Receives the transcript. Called only when something was actually heard.
  final ValueChanged<String> onHeard;

  /// Whether the surrounding composer is accepting input at all.
  final bool enabled;

  @override
  State<MicButton> createState() => _MicButtonState();
}

/// What the button is currently able to do.
enum _Mic {
  /// Still asking the platform what it can do.
  checking,

  /// Ready.
  idle,

  /// Listening to one utterance.
  listening,

  /// This device has no offline recogniser. Shown, disabled, and explained -
  /// **not** quietly switched to a networked one.
  unavailable,

  /// The user refused the microphone. The button goes away.
  refused,
}

class _MicButtonState extends State<MicButton> {
  _Mic _state = _Mic.checking;

  @override
  void initState() {
    super.initState();
    inBackground(_check());
  }

  Future<void> _check() async {
    final available = await widget.speech.isAvailableOnDevice();
    if (!mounted) return;
    setState(() => _state = available ? _Mic.idle : _Mic.unavailable);
  }

  Future<void> _press() async {
    if (!await _ensurePermission()) return;

    setState(() => _state = _Mic.listening);
    final result = await widget.speech.listen();
    if (!mounted) return;

    setState(() {
      _state = switch (result.outcome) {
        // A refusal or a missing recogniser discovered mid-press changes what
        // the button *is*, not just what this press did. Both can happen
        // between one press and the next: permissions are revocable from
        // system settings, and the recogniser is a service that can go away.
        SpeechOutcome.denied => _Mic.refused,
        SpeechOutcome.unavailable => _Mic.unavailable,
        _ => _Mic.idle,
      };
    });

    switch (result.outcome) {
      case SpeechOutcome.heard:
        widget.onHeard(result.transcript!);
      case SpeechOutcome.nothingHeard:
        _say('Did not catch that.');
      case SpeechOutcome.denied:
        _say('Van needs the microphone to listen.');
      case SpeechOutcome.unavailable:
        _say(_offlineOnly);
      case SpeechOutcome.failed:
        _say('The microphone did not work that time.');
    }
  }

  /// Gets the microphone, asking once if it has not been granted.
  ///
  /// A refusal hides the button rather than leaving something that fails
  /// every time it is pressed - the same shape as the calendar, where not
  /// having the grant is an absence rather than a degradation.
  Future<bool> _ensurePermission() async {
    if (await widget.speech.hasPermission()) return true;
    final granted = await widget.speech.requestPermission();
    if (!mounted) return false;
    if (!granted) {
      setState(() => _state = _Mic.refused);
      _say('Van needs the microphone to listen.');
    }
    return granted;
  }

  static const _offlineOnly =
      'This phone has no offline speech recognition, and Van will not send '
      'your voice anywhere.';

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Checking and refused both draw nothing, for opposite reasons: one is
    // "not yet known" and would flicker, the other is "asked and answered".
    if (_state == _Mic.checking || _state == _Mic.refused) {
      return const SizedBox.shrink();
    }

    final colours = Theme.of(context).colorScheme;
    final unavailable = _state == _Mic.unavailable;
    final listening = _state == _Mic.listening;

    return IconButton(
      icon: Icon(
        listening ? Icons.stop_circle_outlined : Icons.mic_none,
        color: listening ? colours.primary : null,
      ),
      // Disabled but present, and it explains itself when pressed. A button
      // that vanished on a phone with no offline recogniser would leave the
      // user thinking Van has no voice input; one that silently used the
      // networked recogniser would be worse than either.
      tooltip: unavailable
          ? _offlineOnly
          : listening
          ? 'Listening - tap to stop'
          : 'Say it instead',
      onPressed: switch (_state) {
        _Mic.unavailable => () => _say(_offlineOnly),
        _Mic.listening => () => inBackground(widget.speech.cancel()),
        _Mic.idle => widget.enabled ? () => inBackground(_press()) : null,
        _ => null,
      },
    );
  }
}
