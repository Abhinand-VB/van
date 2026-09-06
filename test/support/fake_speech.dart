import 'package:van/platform/speech.dart';

/// A microphone Van can be spoken to without.
///
/// Holds what the recogniser would have heard rather than pretending to be a
/// recogniser. Everything worth testing here is what Van does with an
/// outcome - fills a field, asks again, hides a button - and none of it needs
/// audio.
class FakeSpeech implements Speech {
  /// What the next [listen] answers with.
  SpeechResult next = SpeechResult.nothing;

  /// Whether the microphone permission is granted.
  bool granted = false;

  /// What [requestPermission] should answer. Null leaves the state alone,
  /// which is what happens when the user walks away from the dialog.
  bool? grantOnRequest;

  /// Whether this device can recognise speech offline.
  bool availableOnDevice = true;

  /// How many times the microphone has been asked for.
  int requests = 0;

  /// How many times listening was started.
  int listens = 0;

  /// How many times a listen in progress was cancelled.
  int cancels = 0;

  /// Says [text] the next time the button is pressed.
  void willHear(String text) =>
      next = SpeechResult(SpeechOutcome.heard, transcript: text);

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    final grant = grantOnRequest;
    if (grant != null) granted = grant;
    return granted;
  }

  @override
  Future<bool> isAvailableOnDevice() async => availableOnDevice;

  @override
  Future<SpeechResult> listen() async {
    listens++;
    // The two refusals the real plugin makes before it ever opens the
    // microphone, reproduced here so a test cannot pass by skipping them.
    if (!granted) return SpeechResult.denied;
    if (!availableOnDevice) return SpeechResult.unavailable;
    return next;
  }

  @override
  Future<void> cancel() async => cancels++;
}
