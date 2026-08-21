package dev.van.app

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Dart side's only route to a local language model.
 *
 * Five methods, matching `LlmBackend` in Dart one for one, because a channel
 * that grows a sixth convenience method is a channel that has started making
 * decisions. Everything about *what to ask* lives in the capabilities; this
 * moves strings across the boundary and nothing else.
 *
 * Generation runs on a single background thread. Inference on a 2B model takes
 * seconds and blocking the platform thread would freeze the UI; one thread
 * rather than a pool because the engine holds a single model session and
 * concurrent calls into it are not safe.
 */
class LocalLlmPlugin(
    private val context: Context,
    private val engineFactory: (Context) -> LlmEngine = ::defaultEngine,
) {
    companion object {
        const val CHANNEL: String = "dev.van.app/local_llm"

        /**
         * Chooses the engine for this build.
         *
         * **This is the WP-6 wiring point.** When LiteRT-LM is added, return
         * the real engine here when [ModelStorage.isPresent] and a
         * [MissingEngine] otherwise — the "otherwise" branch stays forever,
         * because the model is downloaded on first run rather than bundled.
         */
        fun defaultEngine(context: Context): LlmEngine = MissingEngine(
            if (ModelStorage.isPresent(context.filesDir)) {
                "no inference engine is compiled into this build"
            } else {
                "no model file at ${ModelStorage.modelFile(context.filesDir)}"
            },
        )
    }

    private val engine: LlmEngine by lazy { engineFactory(context) }
    private var worker: ExecutorService? = null
    private var channel: MethodChannel? = null

    /** Starts listening on [CHANNEL]. */
    fun attach(messenger: BinaryMessenger) {
        worker = Executors.newSingleThreadExecutor { r ->
            Thread(r, "van-local-llm")
        }
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(::onCall)
        }
    }

    /** Stops listening and releases the engine. */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        engine.cancel()
        engine.dispose()
        worker?.shutdownNow()
        worker = null
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(engine.isAvailable())
            "warmUp" -> offload(result) { engine.warmUp() }
            "generate" -> offload(result) {
                engine.generate(
                    system = call.argument<String>("system").orEmpty(),
                    prompt = call.argument<String>("prompt").orEmpty(),
                    maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 256,
                    temperature = call.argument<Double>("temperature") ?: 0.7,
                )
            }
            "cancel" -> {
                engine.cancel()
                result.success(null)
            }
            "dispose" -> {
                engine.cancel()
                engine.dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Runs [work] off the platform thread and answers on it.
     *
     * Flutter requires `result` to be used on the platform thread, and a
     * MethodChannel result may be used exactly once — so failures are reported
     * as errors rather than thrown, or the Dart side would hang forever
     * waiting on a reply that is never coming.
     */
    private fun <T> offload(result: MethodChannel.Result, work: () -> T) {
        val executor = worker
        if (executor == null) {
            result.error("detached", "the local model channel is not attached", null)
            return
        }
        executor.execute {
            val outcome = runCatching(work)
            android.os.Handler(context.mainLooper).post {
                outcome
                    .onSuccess(result::success)
                    .onFailure { error ->
                        result.error(
                            if (error is LlmUnavailable) "unavailable" else "failed",
                            error.message ?: error::class.java.simpleName,
                            null,
                        )
                    }
            }
        }
    }
}
