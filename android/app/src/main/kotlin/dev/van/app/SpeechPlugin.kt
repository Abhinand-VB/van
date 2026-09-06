package dev.van.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Dart side's only route to the microphone.
 *
 * **This class uses `createOnDeviceSpeechRecognizer` and nothing else, and
 * that is the whole point of it.** The ordinary [SpeechRecognizer] streams
 * audio to Google's servers on most devices. Van is offline-first and
 * `AGENTS.md` forbids a network dependency in v1 outright, so an
 * implementation that quietly uploaded a user's voice to save a button press
 * would break the central promise of the product. When on-device recognition
 * is not available this answers `unavailable` and stops; there is deliberately
 * no fallback for a future edit to reach for.
 *
 * **No audio is ever written to disk.** Nothing in this file opens a file, a
 * stream or a cache entry, and no `EXTRA_` flag asking the recogniser to
 * retain audio is set. The recogniser streams, Van keeps the transcript, and
 * the audio is gone. `speech_test.dart` reads this source back and asserts
 * both of those properties, because they are promises rather than behaviour
 * and behaviour tests cannot see them.
 *
 * Push-to-talk: one utterance per call, no wake word, no foreground service,
 * nothing held open between presses.
 *
 * [SpeechRecognizer] is documented as main-thread only, so everything here
 * runs on the platform thread and there is no worker - unlike
 * [CalendarPlugin], whose queries are disk and IPC.
 */
class SpeechPlugin(
    private val context: Context,
    private val activity: () -> Activity?,
) {
    companion object {
        const val CHANNEL: String = "dev.van.app/speech"

        /** Arbitrary but stable, and matched in [onPermissionResult]. */
        const val PERMISSION_REQUEST: Int = 4712
    }

    private var channel: MethodChannel? = null
    private var recognizer: SpeechRecognizer? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingListen: MethodChannel.Result? = null

    /** Starts listening on [CHANNEL]. */
    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(::onCall)
        }
    }

    /** Stops listening and releases the recogniser. */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        // Anything left outstanding across a teardown would hang the Dart side
        // forever on a reply that can no longer arrive.
        pendingPermission?.success(hasPermission())
        pendingPermission = null
        finish { it.error("detached", "the speech channel is not attached", null) }
        release()
    }

    /**
     * Delivers the user's answer to the microphone dialog.
     *
     * Must be called from `MainActivity.onRequestPermissionsResult`, or the
     * dialog appears, the user taps Allow, and Dart waits on a future nobody
     * completes.
     */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = pendingPermission ?: return true
        pendingPermission = null
        result.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        return true
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "isAvailableOnDevice" -> result.success(isAvailableOnDevice())
            "listen" -> listen(result)
            "cancel" -> {
                cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        val host = activity()
        if (host == null || pendingPermission != null) {
            // No activity means no dialog is possible. Answering "not granted"
            // is the truth and leaves the button where it was; erroring would
            // surface as a fault in a flow the user did not start.
            result.success(false)
            return
        }
        pendingPermission = result
        host.requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST,
        )
    }

    /**
     * Whether this device can recognise speech with no network at all.
     *
     * `createOnDeviceSpeechRecognizer` arrived in API 31. Below that there is
     * no offline recogniser to ask for, and the answer is a plain no rather
     * than a quiet downgrade to the networked one.
     */
    private fun isAvailableOnDevice(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    private fun listen(result: MethodChannel.Result) {
        if (!hasPermission()) {
            result.error("denied", "the microphone is not granted", null)
            return
        }
        if (!isAvailableOnDevice()) {
            result.error(
                "unavailable",
                "this device has no on-device speech recognition",
                null,
            )
            return
        }
        if (pendingListen != null) {
            result.error("busy", "already listening", null)
            return
        }

        pendingListen = result
        val engine = recognizer ?: SpeechRecognizer
            .createOnDeviceSpeechRecognizer(context)
            .also { recognizer = it }

        engine.setRecognitionListener(Listener())
        engine.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                // Belt and braces against a future edit: this recogniser is
                // already on-device, and this says so a second time.
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            },
        )
    }

    private fun cancel() {
        recognizer?.cancel()
        finish { it.success(null) }
    }

    private fun release() {
        recognizer?.destroy()
        recognizer = null
    }

    /**
     * Answers the outstanding listen exactly once, if there is one.
     *
     * Flutter requires a result to be used once and only once, and the
     * recognition listener has several callbacks that can each be the end of
     * the same utterance - `onResults` then `onEndOfSpeech`, or `onError`
     * after a partial. Funnelling every ending through here is what stops the
     * second one crashing the engine.
     */
    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val pending = pendingListen ?: return
        pendingListen = null
        Handler(context.mainLooper).post { answer(pending) }
    }

    private inner class Listener : RecognitionListener {
        override fun onResults(results: Bundle?) {
            val heard = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
            // Null for "nothing was matched", which is an ordinary outcome and
            // not an error: the user pressed the button and said nothing, or
            // the room was loud.
            finish { it.success(heard.ifBlank { null }) }
        }

        override fun onError(error: Int) {
            finish {
                when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                        it.error("denied", "the microphone is not granted", null)
                    SpeechRecognizer.ERROR_NO_MATCH,
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                    -> it.success(null)
                    else -> it.error("failed", "speech error $error", null)
                }
            }
        }

        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onPartialResults(partialResults: Bundle?) = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }
}
