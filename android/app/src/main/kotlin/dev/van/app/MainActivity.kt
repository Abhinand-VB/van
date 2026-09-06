package dev.van.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var localLlm: LocalLlmPlugin? = null
    private var calendars: CalendarPlugin? = null
    private var speech: SpeechPlugin? = null
    private var modelFile: ModelFilePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        localLlm = LocalLlmPlugin(applicationContext).also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
        // The activity is passed as a lambda rather than a reference: the
        // plugin needs one only to put a permission dialog on screen, and
        // holding the activity itself would outlive it on a configuration
        // change.
        calendars = CalendarPlugin(applicationContext) { this }.also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
        speech = SpeechPlugin(applicationContext) { this }.also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
        modelFile = ModelFilePlugin(applicationContext) { this }.also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    /**
     * Hands a permission answer back to whichever plugin asked for it.
     *
     * Without this the dialog appears, the user taps Allow, and the Dart side
     * waits forever on a future nobody completes. Each plugin recognises its
     * own request code and returns false for anyone else's, so the order here
     * does not matter and adding a third is one more line.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        val handled =
            calendars?.onPermissionResult(requestCode, grantResults) == true ||
                speech?.onPermissionResult(requestCode, grantResults) == true
        if (!handled) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    /**
     * Hands the picked model file back to the plugin.
     *
     * Same shape as the permission forwarding above, and needed for the same
     * reason: without it the picker closes and the Dart side waits forever.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (modelFile?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        // Releasing the engine matters here: a loaded model holds hundreds of
        // megabytes, and leaking it across an activity restart is the fastest
        // way to be killed for memory.
        localLlm?.detach()
        localLlm = null
        calendars?.detach()
        calendars = null
        speech?.detach()
        speech = null
        modelFile?.detach()
        modelFile = null
        super.onDestroy()
    }
}
