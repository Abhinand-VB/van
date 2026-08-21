package dev.van.app

import java.io.File

/**
 * What the platform channel needs from a local language model.
 *
 * An interface rather than a direct LiteRT-LM call because LiteRT is not
 * wired up yet, and this is the seam where it goes. Everything above it —
 * the channel, the Dart backend, the router, the capabilities — is finished
 * and testable today against [MissingEngine].
 *
 * Adding the real thing is deliberately confined to two edits:
 *
 *  1. a LiteRT-LM dependency in `android/app/build.gradle.kts`, and
 *  2. one implementation of this interface, selected in [LocalLlmPlugin].
 *
 * Nothing else in the app should need to change. If it does, the abstraction
 * in ARCHITECTURE.md section 5 has failed and that is worth stopping over.
 */
interface LlmEngine {

    /** Whether this engine could run right now. */
    fun isAvailable(): Boolean

    /**
     * Loads the model so the first real call is not the slow one.
     *
     * Returns false when there is nothing to load. Must be safe to call more
     * than once.
     */
    fun warmUp(): Boolean

    /**
     * Runs one prompt to completion.
     *
     * Throws [LlmUnavailable] rather than returning a sentinel, so a missing
     * model cannot be mistaken for a model that answered with nothing.
     */
    fun generate(
        system: String,
        prompt: String,
        maxOutputTokens: Int,
        temperature: Double,
    ): String

    /** Abandons any generation in flight. Safe when there is none. */
    fun cancel()

    /** Releases whatever the engine is holding. */
    fun dispose()
}

/** Raised when a call is made and no model is actually present. */
class LlmUnavailable(message: String) : IllegalStateException(message)

/**
 * The engine Van ships with today: none.
 *
 * Not a stub to be deleted — it is the correct behaviour for a build with no
 * model file, which is every build until WP-6 finishes and most builds after
 * it, since the model is downloaded on first run rather than bundled. Every
 * capability has a deterministic fallback, so reporting "unavailable" honestly
 * is a working configuration rather than a broken one.
 */
class MissingEngine(private val reason: String) : LlmEngine {

    override fun isAvailable(): Boolean = false

    override fun warmUp(): Boolean = false

    override fun generate(
        system: String,
        prompt: String,
        maxOutputTokens: Int,
        temperature: Double,
    ): String = throw LlmUnavailable(reason)

    override fun cancel() = Unit

    override fun dispose() = Unit
}

/**
 * Where the model file is expected to live once it has been downloaded.
 *
 * App-private storage, so it is removed when Van is uninstalled and is not
 * visible to anything else on the phone. Nothing downloads it yet; this is
 * only the agreed location, kept in one place so the downloader and the engine
 * cannot disagree about it later.
 */
object ModelStorage {
    const val FILE_NAME: String = "gemma-e2b-int4.litertlm"

    fun modelFile(filesDir: File): File = File(File(filesDir, "models"), FILE_NAME)

    fun isPresent(filesDir: File): Boolean = modelFile(filesDir).let {
        it.isFile && it.length() > 0
    }
}
