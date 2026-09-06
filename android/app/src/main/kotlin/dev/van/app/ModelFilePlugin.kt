package dev.van.app

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Puts the on-device model's weights where [ModelStorage] expects them.
 *
 * Two routes in, and a deliberate line between them.
 *
 * **Van still has no HTTP client and opens no socket.** It hands a URL to
 * Android's [DownloadManager], a system service that runs in its own process -
 * the same shape as handing a URI to a browser or to the document picker, and
 * the reason this app declares no `INTERNET` permission in its release
 * manifest. `AGENTS.md` forbids adding a *network dependency*; asking the
 * operating system to fetch a file is not one, and the alternative was a
 * feature nobody could use. See `DECISIONS_PENDING.md` D79.
 *
 * The manual route stays: a file picked through the storage access framework,
 * which needs no storage permission at all because Android grants access to
 * that one document. It is the fallback for a phone that already has the file,
 * or a download that will not start.
 *
 * Either way the file lands in app-private storage, so it disappears when Van
 * is uninstalled and nothing else on the phone can read it. Copying runs on a
 * background thread: the file is measured in gigabytes and doing it on the
 * platform thread would freeze the UI for the whole copy.
 */
class ModelFilePlugin(
    private val context: Context,
    private val activity: () -> Activity?,
) {
    companion object {
        const val CHANNEL: String = "dev.van.app/model_file"

        /** Arbitrary but stable, and matched in [onActivityResult]. */
        const val PICK_REQUEST: Int = 4713

        /** What the download is called on its way in. */
        const val DOWNLOAD_NAME: String = "van-model-download.litertlm"
    }

    private var channel: MethodChannel? = null
    private var worker: ExecutorService? = null
    private var pendingPick: MethodChannel.Result? = null

    /** The download in flight, so it can be watched and cancelled. */
    private var downloadId: Long? = null

    private val downloads: DownloadManager?
        get() = context.getSystemService(DownloadManager::class.java)

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
            "download" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("bad_arguments", "url is required", null)
                } else {
                    result.success(startDownload(url))
                }
            }
            "downloadStatus" -> result.success(downloadStatus())
            "cancelDownload" -> {
                downloadId?.let { downloads?.remove(it) }
                downloadId = null
                result.success(downloadStatus())
            }
            "adoptDownload" -> adoptDownload(result)
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
            "pending" to downloadedFile().let { it.isFile && it.length() > 0 },
        )
    }

    /** Where a finished download sits until it is adopted. */
    private fun downloadedFile(): java.io.File =
        java.io.File(context.getExternalFilesDir(null), DOWNLOAD_NAME)

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

    /**
     * Asks Android to fetch [url] into Van's own external files directory.
     *
     * `setAllowedOverMetered(false)` because this is two and a half gigabytes.
     * Starting that on someone's mobile data without asking is not a
     * convenience, it is a bill - so the download waits for Wi-Fi, and the
     * Dart side is told that is what it is doing rather than it appearing
     * stuck.
     *
     * The destination is `getExternalFilesDir`, which needs no permission and
     * is removed on uninstall. It is not the final home - [adoptDownload]
     * moves it to internal storage where the engine looks - because
     * `DownloadManager` cannot write there directly.
     */
    private fun startDownload(url: String): Map<String, Any?> {
        val manager = downloads ?: return downloadStatus()
        if (downloadId != null) return downloadStatus()

        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("Van language model")
            .setDescription("Downloaded once, then it works offline")
            .setAllowedOverMetered(false)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
            )
            .setDestinationInExternalFilesDir(context, null, DOWNLOAD_NAME)
        downloadId = manager.enqueue(request)
        return downloadStatus()
    }

    /**
     * Where the download has got to.
     *
     * Polled rather than pushed. A broadcast receiver would tell Van the
     * moment it finished and nothing in between, and a progress bar that moves
     * only once is worse than no progress bar on a file this size.
     */
    private fun downloadStatus(): Map<String, Any?> {
        // The file on disk outranks anything remembered in memory, and that is
        // the whole fix for the bug this had: `downloadId` lives only as long
        // as the process, so a download that finished while Van was closed -
        // or simply while this page was not open - left two and a half
        // gigabytes sitting unclaimed and a screen offering to fetch it again.
        // Asking the filesystem cannot forget.
        val finished = downloadedFile()
        if (finished.isFile && finished.length() > 0) {
            return mapOf(
                "state" to "done",
                "bytes" to finished.length(),
                "total" to finished.length(),
            )
        }

        val id = downloadId ?: return mapOf("state" to "idle")
        val manager = downloads ?: return mapOf("state" to "idle")

        manager.query(DownloadManager.Query().setFilterById(id)).use { c ->
            if (c == null || !c.moveToFirst()) {
                downloadId = null
                return mapOf("state" to "idle")
            }
            val status = c.getInt(
                c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS),
            )
            val soFar = c.getLong(
                c.getColumnIndexOrThrow(
                    DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
                ),
            )
            val total = c.getLong(
                c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
            )
            return mapOf(
                "state" to when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> "done"
                    DownloadManager.STATUS_FAILED -> "failed"
                    // Paused waiting for Wi-Fi is the expected state on mobile
                    // data, not a fault, and the page says so.
                    DownloadManager.STATUS_PAUSED -> "paused"
                    else -> "running"
                },
                "bytes" to soFar,
                "total" to total,
            )
        }
    }

    /**
     * Moves a finished download into the place the engine looks.
     *
     * A rename first, because internal and external storage are usually the
     * same volume on a modern phone and renaming two and a half gigabytes is
     * instant where copying it is a minute. The copy is the fallback for the
     * phones where they are not.
     */
    private fun adoptDownload(result: MethodChannel.Result) {
        val executor = worker
        if (executor == null) {
            result.error("detached", "the model channel is not attached", null)
            return
        }
        executor.execute {
            val outcome = runCatching {
                val source = java.io.File(
                    context.getExternalFilesDir(null),
                    DOWNLOAD_NAME,
                )
                check(source.isFile && source.length() > 0) {
                    "no finished download to adopt"
                }
                val target = ModelStorage.modelFile(context.filesDir)
                target.parentFile?.mkdirs()
                target.delete()
                if (!source.renameTo(target)) {
                    source.inputStream().use { input ->
                        target.outputStream().use(input::copyTo)
                    }
                    source.delete()
                }
                downloadId = null
                status()
            }
            android.os.Handler(context.mainLooper).post {
                outcome
                    .onSuccess(result::success)
                    .onFailure { error ->
                        result.error(
                            "adopt_failed",
                            error.message ?: error::class.java.simpleName,
                            null,
                        )
                    }
            }
        }
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
