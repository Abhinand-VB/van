import 'package:flutter/services.dart';

/// Why a spell of listening ended.
///
/// Five outcomes rather than a nullable string, because four of them need
/// different things said to the user and a null cannot tell them apart.
/// "Nothing was said" is a shrug; "this phone cannot do it offline" is a
/// sentence about privacy; "you said no" means the button should go away.
enum SpeechOutcome {
  /// Something was recognised. The transcript is on the result.
  heard,

  /// The recogniser ran and came back with nothing - silence, or noise.
  nothingHeard,

  /// This device has no on-device recogniser. **Van does not fall back to a
  /// networked one**, so this is a dead end rather than a slower path.
  unavailable,

  /// The microphone permission is not granted.
  denied,

  /// The recogniser errored. Nothing was heard and nothing is known.
  failed,
}

/// What one press of the microphone produced.
class SpeechResult {
  /// Creates a result.
  const SpeechResult(this.outcome, {this.transcript});

  /// Nothing was recognised.
  static const nothing = SpeechResult(SpeechOutcome.nothingHeard);

  /// This device cannot recognise speech without a network.
  static const unavailable = SpeechResult(SpeechOutcome.unavailable);

  /// The microphone was refused.
  static const denied = SpeechResult(SpeechOutcome.denied);

  /// The recogniser failed.
  static const failed = SpeechResult(SpeechOutcome.failed);

  /// How it ended.
  final SpeechOutcome outcome;

  /// What was heard, when [outcome] is [SpeechOutcome.heard]. Null otherwise.
  ///
  /// **A draft, never a command.** Recognition is wrong often enough that
  /// capturing straight from it would put tasks nobody said into a log that
  /// never deletes. Every caller puts this in the field the user was about to
  /// type in, and lets them look at it first.
  final String? transcript;

  @override
  String toString() => 'SpeechResult(${outcome.name})';
}

/// Turns speech into text, on the device and nowhere else.
///
/// **Audio never leaves the phone and never touches disk.** Those are the two
/// hard rules of `docs/WP_VOICE.md` 2.2 and they are the reason this interface
/// exists at all rather than a speech package being dropped in: the ordinary
/// Android `SpeechRecognizer` streams audio to Google's servers on most
/// devices, and Van is offline-first. An implementation that quietly uploaded
/// a user's voice would break the central promise of the product to save a
/// button press.
///
/// So [isAvailableOnDevice] is not a nicety. When it answers false the
/// microphone button is disabled and says why, and there is deliberately no
/// second path for it to take.
///
/// Shaped like `Calendars`: an interface the app depends on, an Android
/// implementation over a method channel, a fake in `test/support`, and an
/// unsupported implementation that is the correct one everywhere the plugin
/// does not exist.
abstract interface class Speech {
  /// Whether the microphone permission is granted.
  ///
  /// Read fresh every time. It can be revoked from system settings between
  /// one press and the next.
  Future<bool> hasPermission();

  /// Asks for the microphone. Returns whether it was granted.
  Future<bool> requestPermission();

  /// Whether this device can recognise speech with no network at all.
  Future<bool> isAvailableOnDevice();

  /// Listens once, and returns what was said.
  ///
  /// One utterance per press: this is push-to-talk, not an open microphone.
  /// See `docs/WP_VOICE.md` 2.1 for why there is no wake word - an
  /// always-listening app makes a promise about a household's conversation
  /// that Van cannot honestly keep, and buys nothing, because Van's whole
  /// interaction model already has the phone in your hand.
  Future<SpeechResult> listen();

  /// Stops a listen already in progress, discarding whatever it had.
  Future<void> cancel();
}

/// The Android implementation, over a method channel.
class MethodChannelSpeech implements Speech {
  /// Creates a client for the platform channel.
  const MethodChannelSpeech();

  /// The channel name, matching `SpeechPlugin.CHANNEL` in Kotlin.
  static const channel = MethodChannel('dev.van.app/speech');

  @override
  Future<bool> hasPermission() async =>
      await channel.invokeMethod<bool>('hasPermission') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<bool> isAvailableOnDevice() async =>
      await channel.invokeMethod<bool>('isAvailableOnDevice') ?? false;

  @override
  Future<SpeechResult> listen() async {
    try {
      final heard = await channel.invokeMethod<String>('listen');
      // The platform answers null for "the recogniser ran and matched
      // nothing", which is an ordinary outcome and not an error. An empty
      // string is the same thing arriving by a different route.
      final text = heard?.trim() ?? '';
      return text.isEmpty
          ? SpeechResult.nothing
          : SpeechResult(SpeechOutcome.heard, transcript: text);
    } on PlatformException catch (error) {
      // The platform's own vocabulary, mapped once here so no screen has to
      // know what an Android speech error code looks like.
      return switch (error.code) {
        'denied' => SpeechResult.denied,
        'unavailable' => SpeechResult.unavailable,
        _ => SpeechResult.failed,
      };
    } on MissingPluginException catch (_) {
      // No plugin registered at all - a desktop or test binary. Not having
      // speech is not a failure of speech.
      return SpeechResult.unavailable;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } on PlatformException catch (_) {
      // Cancelling is best-effort by nature: the only reason to call it is
      // that the caller has already stopped caring about the answer.
    } on MissingPluginException catch (_) {}
  }
}

/// A device Van cannot listen on.
///
/// Not a stub and not a failure mode: this is the correct implementation
/// everywhere the plugin does not exist, and it is what keeps voice from
/// becoming a hard dependency of the capture field.
class UnsupportedSpeech implements Speech {
  /// Creates the empty implementation.
  const UnsupportedSpeech();

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> isAvailableOnDevice() async => false;

  @override
  Future<SpeechResult> listen() async => SpeechResult.unavailable;

  @override
  Future<void> cancel() async {}
}
