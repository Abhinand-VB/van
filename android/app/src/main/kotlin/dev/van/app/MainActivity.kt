package dev.van.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var localLlm: LocalLlmPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        localLlm = LocalLlmPlugin(applicationContext).also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun onDestroy() {
        // Releasing the engine matters here: a loaded model holds hundreds of
        // megabytes, and leaking it across an activity restart is the fastest
        // way to be killed for memory.
        localLlm?.detach()
        localLlm = null
        super.onDestroy()
    }
}
