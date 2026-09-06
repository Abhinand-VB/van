package dev.van.app

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession

/**
 * Runs the on-device model, when its weights are actually on the device.
 *
 * The other half of the seam [LlmEngine] was written for. Everything above it
 * — the channel, the Dart backend, the router, the capabilities, the golden
 * set — was finished and testable long before this existed, against
 * [MissingEngine].
 *
 * **Nothing here has produced a token.** The weights are licence-gated, no
 * agent may accept a licence on the owner's behalf, and so this has been
 * compiled and installed but never run. Treat every claim about its behaviour
 * as unproven until the golden set has been run on the phone with a real file
 * in place — see `STATUS.md` 3e for the gate that decides whether anything is
 * routed here at all, and `DECISIONS_PENDING.md` D77.
 *
 * One session per generation rather than one held open. A session carries the
 * conversation, and Van's capabilities are all one-shot: `extract_task` asking
 * about this sentence must not be coloured by the last nudge that was worded.
 * The expensive object is the [LlmInference] itself, which is held.
 */
class LiteRtEngine(
    private val context: Context,
    private val maxTokens: Int = 1024,
) : LlmEngine {

    private var inference: LlmInference? = null

    override fun isAvailable(): Boolean = ModelStorage.isPresent(context.filesDir)

    override fun warmUp(): Boolean = runCatching { engine() }.isSuccess

    /**
     * Loads the model, once.
     *
     * Kept between calls because loading is seconds and hundreds of megabytes.
     * [LocalLlmPlugin] already serialises every call onto one thread, so there
     * is no locking here and there must not be two of these.
     */
    private fun engine(): LlmInference {
        inference?.let { return it }
        val file = ModelStorage.modelFile(context.filesDir)
        if (!ModelStorage.isPresent(context.filesDir)) {
            throw LlmUnavailable("no model file at $file")
        }
        return LlmInference.createFromOptions(
            context,
            LlmInference.LlmInferenceOptions.builder()
                .setModelPath(file.absolutePath)
                .setMaxTokens(maxTokens)
                .build(),
        ).also { inference = it }
    }

    override fun generate(
        system: String,
        prompt: String,
        maxOutputTokens: Int,
        temperature: Double,
    ): String {
        val session = LlmInferenceSession.createFromOptions(
            engine(),
            LlmInferenceSession.LlmInferenceSessionOptions.builder()
                .setTemperature(temperature.toFloat())
                .build(),
        )
        return session.use {
            // **One chunk, not two.** The first version added the system
            // prompt and the user prompt as separate query chunks, and the
            // model answered with a stray `<turn|>` and then a tail of
            // `<eos>` tokens all the way to the output cap - it had lost
            // track of whose turn it was, so it never stopped. A single turn
            // is a single chunk.
            it.addQueryChunk(
                if (system.isBlank()) prompt else system + "\n\n" + prompt,
            )
            it.generateResponse()
        }
    }

    /**
     * Not implementable against the synchronous API, and it says so.
     *
     * `generateResponse` blocks until it is finished and there is nothing to
     * interrupt. The Dart side already treats cancel as best-effort, and
     * pretending otherwise here would put a promise in the codebase that the
     * platform cannot keep. Switching to the async API is the way to make this
     * real, and is not worth doing before anything has been measured.
     */
    override fun cancel() = Unit

    override fun dispose() {
        inference?.close()
        inference = null
    }
}
