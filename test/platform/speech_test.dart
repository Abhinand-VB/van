import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/platform/speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannelSpeech.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('the channel', () {
    test('a transcript comes back as heard', () async {
      answer((_) => 'finish the assignment by friday, two hours');

      final result = await const MethodChannelSpeech().listen();

      expect(result.outcome, SpeechOutcome.heard);
      expect(result.transcript, 'finish the assignment by friday, two hours');
    });

    test('silence is an ordinary outcome, not an error', () async {
      answer((_) => null);

      // The user pressed the button and said nothing, or the room was loud.
      // Treating that as a failure would put an error message in front of
      // someone who simply changed their mind.
      expect(
        (await const MethodChannelSpeech().listen()).outcome,
        SpeechOutcome.nothingHeard,
      );
    });

    test('whitespace is silence too', () async {
      answer((_) => '   ');

      expect(
        (await const MethodChannelSpeech().listen()).outcome,
        SpeechOutcome.nothingHeard,
      );
    });

    test('a transcript is trimmed before anyone sees it', () async {
      answer((_) => '  call the bank  ');

      expect(
        (await const MethodChannelSpeech().listen()).transcript,
        'call the bank',
      );
    });

    test('the platform vocabulary is mapped once, here', () async {
      for (final (code, expected) in const [
        ('denied', SpeechOutcome.denied),
        ('unavailable', SpeechOutcome.unavailable),
        ('failed', SpeechOutcome.failed),
        ('busy', SpeechOutcome.failed),
        ('something new', SpeechOutcome.failed),
      ]) {
        answer((_) => throw PlatformException(code: code));

        expect(
          (await const MethodChannelSpeech().listen()).outcome,
          expected,
          reason: 'error code "$code"',
        );
      }
    });

    test('no plugin registered is unavailable, not a crash', () async {
      messenger.setMockMethodCallHandler(channel, null);

      // A desktop binary, or a test. Not having speech is not a failure of
      // speech.
      expect(
        (await const MethodChannelSpeech().listen()).outcome,
        SpeechOutcome.unavailable,
      );
    });

    test('cancelling never throws, however it goes', () async {
      answer((_) => throw PlatformException(code: 'failed'));

      // The only reason to cancel is that the caller has stopped caring about
      // the answer, so a failure to cancel cannot be worth surfacing.
      await expectLater(const MethodChannelSpeech().cancel(), completes);
    });

    test('permission and availability default to no on a null reply', () async {
      answer((_) => null);
      const speech = MethodChannelSpeech();

      expect(await speech.hasPermission(), isFalse);
      expect(await speech.isAvailableOnDevice(), isFalse);
      expect(await speech.requestPermission(), isFalse);
    });

    test('the channel name matches the Kotlin side', () {
      final kotlin = File(
        'android/app/src/main/kotlin/dev/van/app/SpeechPlugin.kt',
      ).readAsStringSync();

      expect(kotlin, contains('"${channel.name}"'));
    });
  });

  group('a device with no microphone at all', () {
    test('answers no to everything and unavailable to listening', () async {
      const speech = UnsupportedSpeech();

      expect(await speech.hasPermission(), isFalse);
      expect(await speech.requestPermission(), isFalse);
      expect(await speech.isAvailableOnDevice(), isFalse);
      expect((await speech.listen()).outcome, SpeechOutcome.unavailable);
      await expectLater(speech.cancel(), completes);
    });
  });

  // These two are promises rather than behaviour. No test that drives the app
  // can observe "the audio was never written down" or "the network recogniser
  // was never reached for" - the only place those live is the source, so the
  // source is what gets read. Same shape as the calendar test that greps a
  // serialised event log for a planted meeting title.
  group('the two promises in WP_VOICE 2.2', () {
    late String kotlin;
    late String dart;

    setUp(() {
      kotlin = File(
        'android/app/src/main/kotlin/dev/van/app/SpeechPlugin.kt',
      ).readAsStringSync();
      dart = File('lib/platform/speech.dart').readAsStringSync();
    });

    test('audio is never written anywhere', () {
      // Every route Android offers for putting bytes on disk. If a future
      // edit needs one of these, it needs this test changed first, and that
      // is exactly the conversation worth forcing.
      for (final writer in const [
        'FileOutputStream',
        'openFileOutput',
        'createTempFile',
        'File(',
        'cacheDir',
        'filesDir',
        'getExternalFilesDir',
        'MediaRecorder',
        'AudioRecord',
        'EXTRA_AUDIO_SOURCE',
        'EXTRA_ENABLE_FORMATTING',
      ]) {
        expect(
          kotlin,
          isNot(contains(writer)),
          reason: 'SpeechPlugin must not reach for $writer',
        );
      }
      expect(dart, isNot(contains('dart:io')));
    });

    test('the networked recogniser is never reached for', () {
      // `createSpeechRecognizer` is the one that streams audio to Google on
      // most devices. Van answers "unavailable" instead, and the absence of a
      // fallback is the feature.
      expect(kotlin, contains('createOnDeviceSpeechRecognizer'));
      expect(kotlin, isNot(contains('createSpeechRecognizer(')));
      expect(kotlin, contains('isOnDeviceRecognitionAvailable'));
    });

    test('the manifest asks for a microphone and not for a network', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.RECORD_AUDIO'));
      // A speech path that cannot reach the network cannot leak audio to it,
      // whatever a later edit does inside the plugin.
      expect(
        manifest,
        isNot(
          contains(
            '<uses-permission android:name="android.permission.INTERNET"',
          ),
        ),
      );
    });
  });
}
