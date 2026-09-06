package dev.van.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Puts the on-device model's weights where [ModelStorage] expects them.
 *
 * **It receives a file. It does not fetch one, and there is nothing here that
 * could.** Two constraints decide that and they agree: `AGENTS.md` forbids a
 * network dependency in v1 outright, and the weights are licence-gated, so
 * whoever installs them has to have accepted that licence - which is the user.
 * A downloader would need both an HTTP client Van does not have and a token
 * Van has no right to hold.
 *
 * The file is taken through the storage access framework, so Van needs no
 * storage permission at all: the user picks a document and Android grants
 * access to that one document. It is then copied into app-private storage,
 * which means it disappears when Van is uninstalled and nothing else on the
 * phone can read it.
 *
 * Copying runs on a background thread. The file is measured in gigabytes and
 * doing it on the platform thread would freeze the UI for the whole copy.
 */
class ModelFilePlugin(
    private val context: Context,
    private val activity: () -> Activity?,
) {
    companion object {
        const val CHANNEL: String = "dev.van.app/model_file"

        /** Arbitrary but stable, and matched in [onActivityResult]. */
        const val PICK_REQUEST: Int = 4713
    }

    private var channel: MethodChannel? = null
    private var worker: ExecutorService? = null
    private var pendingPick: MethodChannel.Result? = null

    /** Starts listening on [CHANNEL]. */
    fun attach(messenger: BinaryMessenger) {
        worker = Executors.newSingleThreadExecutor { r -> Thread(r, "van-model") }
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(::onCall)
        }
    }

    /** Stops listening. */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        // A pick left outstanding across a teardown would hang the Dart side
        // on a reply that can no longer arrive.
        pendingPick?.success(status())
        pendingPick = null
        worker?.shutdownNow()
        worker = null
    }

    /**
     * Receives the document the user picked.
     *
     * Must be called from `MainActivity.onActivityResult`, or the picker
     * closes and Dart waits on a future nobody completes.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null

        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            // Cancelled. Not an error - the status is simply what it was.
            result.success(status())
            return true
        }

        val executor = worker
        if (executor == null) {
            result.error("detached", "the model channel is not attached", null)
            return true
        }
        executor.execute {
            val outcome = runCatching {
                val target = ModelStorage.modelFile(context.filesDir)
                target.parentFile?.mkdirs()
                // Written beside the target and renamed, so an interrupted
                // copy cannot leave a half a model where the engine looks for
                // a whole one - which would load, and fail in a way that
                // reads as a bad model rather than a bad copy.
                val partial = java.io.File(target.parentFile, target.name + ".part")
                context.contentResolver.openInputStream(uri).use { input ->
                    checkNotNull(input) { "could not open the chosen file" }
                    partial.outputStream().use(input::copyTo)
                }
                partial.renameTo(target)
                status()
            }
            android.os.Handler(context.mainLooper).post {
                outcome
                    .onSuccess(result::success)
                    .onFailure { error ->
                        result.error(
                            "copy_failed",
                            error.message ?: error::class.java.simpleName,
                            null,
                        )
                    }
            }
        }
        return true
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "install" -> install(result)
            "remove" -> {
                ModelStorage.modelFile(context.filesDir).delete()
                result.success(status())
            }
            "openPage" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("bad_arguments", "url is required", null)
                } else {
                    openPage(url)
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any?> {
        val file = ModelStorage.modelFile(context.filesDir)
        return mapOf(
            "present" to ModelStorage.isPresent(context.filesDir),
            "path" to file.absolutePath,
            "bytes" to if (file.isFile) file.length() else 0L,
            "expectedName" to ModelStorage.FILE_NAME,
        )
    }

    /**
     * Hands [url] to whatever browser the phone has.
     *
     * **This is not a network dependency and Van does not gain one.** No
     * request is made from this process; a URI is handed to the OS and the
     * browser does everything after that - including the licence the user has
     * to accept, which is theirs to accept on the vendor's own page rather
     * than something an app can click through for them.
     *
     * `NEW_TASK` because the plugin holds the application context, not the
     * activity's, and starting an activity from a non-activity context
     * without it throws.
     */
    private fun openPage(url: String) {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    private fun install(result: MethodChannel.Result) {
        val host = activity()
        if (host == null || pendingPick != null) {
            result.success(status())
            return
        }
        pendingPick = result
        host.startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                // Deliberately not narrowed by MIME type. A `.litertlm` or
                // `.task` file has no registered type, and every provider that
                // reports one reports something different - a filter here is
                // how the file the user just downloaded turns up greyed out.
                type = "*/*"
            },
            PICK_REQUEST,
        )
    }
}
