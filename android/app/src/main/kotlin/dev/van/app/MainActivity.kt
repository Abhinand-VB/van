package dev.van.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var localLlm: LocalLlmPlugin? = null
    private var calendars: CalendarPlugin? = null

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
    }

    /**
     * Hands the calendar permission answer back to the plugin.
     *
     * Without this the dialog appears, the user taps Allow, and the Dart side
     * waits forever on a future nobody completes.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (calendars?.onPermissionResult(requestCode, grantResults) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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
        super.onDestroy()
    }
}
