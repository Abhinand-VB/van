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
 * **It works, and it is far too slow to use.** Measured on a Snapdragon 8
 * Elite with Gemma 4 E2B: about two and three quarter minutes for one capture,
 * against under a millisecond for the deterministic parser that answers the
 * same question correctly. Nothing is routed here and the gate in `STATUS.md`
 * 3e is what would change that. `DECISIONS_PENDING.md` D82 and D84 have every
 * number.
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
        // **No backend is asked for, and that is a measurement, not an
        // omission.** All three published builds of these weights were put on
        // the owner's phone and run through `ModelProbe`:
        //
        //  - the CPU build answers, in about two and three quarter minutes;
        //  - `gemma-4-E2B-it-gpu.litertlm` carries a
        //    `tf_lite_artisan_text_decoder` section constrained to
        //    `gpu_artisan`, which this runtime does not read at all - it looks
        //    for `TF_LITE_PREFILL_DECODE`, finds nothing, and fails in 217 ms
        //    with "model is null";
        //  - `gemma-4-E2B-it_qualcomm_sm8750.litertlm`, built for this exact
        //    chip, does have a prefill/decode section but a QNN signature, and
        //    fails in 295 ms with "Unsupported model signature".
        //
        // `setPreferredBackend(GPU)` was tried and removed. It cannot help:
        // whether the GPU can be used is a property of the weights, and no
        // obtainable file has weights this runtime can put on a GPU. Asking
        // anyway cost about seven seconds of failed OpenCL setup on every cold
        // start, for nothing. Getting to the GPU means replacing
        // `com.google.mediapipe:tasks-genai` with the LiteRT-LM runtime, which
        // is a different dependency and a different bet.
        //
        // See `DECISIONS_PENDING.md` D84.
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
