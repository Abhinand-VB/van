package dev.van.app

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Dart side's only route to the device calendar. Read-only, by design.
 *
 * Four methods, and none of them decides anything. Whether an entry actually
 * blocks the user's time is a domain rule and lives in `CalendarFilter` in
 * van_core; whether a calendar is excluded is a Van preference the platform
 * has no business knowing. This moves rows across the boundary and nothing
 * else — the same rule [LocalLlmPlugin] follows, and for the same reason.
 *
 * **It never reads a title.** Van's event log is append-only and never
 * deletes, so a meeting title that reaches it lives there permanently. Not
 * putting the string on the channel at all is a stronger guarantee than
 * handling it carefully on the other side, and planning has no use for it.
 *
 * Queries run on a background thread. A `ContentResolver` query against a
 * synced calendar provider is disk and IPC, and blocking the platform thread
 * on it would freeze the UI at exactly the moment the user pressed send.
 */
class CalendarPlugin(
    private val context: Context,
    private val activity: () -> Activity?,
) {
    companion object {
        const val CHANNEL: String = "dev.van.app/calendars"

        /**
         * Arbitrary but stable, and matched in [onPermissionResult]. Android
         * hands it back so an app with several outstanding requests can tell
         * them apart; Van only ever has this one.
         */
        const val PERMISSION_REQUEST: Int = 4711

        private val CALENDAR_COLUMNS = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.CALENDAR_COLOR,
        )

        /**
         * Deliberately no TITLE, DESCRIPTION, LOCATION or ORGANIZER. See the
         * class comment: what is never read cannot be leaked.
         */
        private val INSTANCE_COLUMNS = arrayOf(
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.AVAILABILITY,
            CalendarContract.Instances.SELF_ATTENDEE_STATUS,
        )
    }

    private var worker: ExecutorService? = null
    private var channel: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null

    /** Starts listening on [CHANNEL]. */
    fun attach(messenger: BinaryMessenger) {
        worker = Executors.newSingleThreadExecutor { r ->
            Thread(r, "van-calendars")
        }
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(::onCall)
        }
    }

    /** Stops listening. */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        // A request left outstanding across a teardown would hang the Dart
        // side forever waiting on a reply that can no longer arrive.
        pendingPermission?.success(hasPermission())
        pendingPermission = null
        worker?.shutdownNow()
        worker = null
    }

    /**
     * Delivers the user's answer to the permission dialog.
     *
     * Must be called from `MainActivity.onRequestPermissionsResult`. Without
     * that forwarding the dialog appears, the user taps Allow, and Dart waits
     * on a future nobody ever completes.
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
            "sources" -> offload(result, ::readSources)
            "between" -> {
                val from = call.argument<Number>("from")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                if (from == null || to == null) {
                    result.error("bad_arguments", "from and to are required", null)
                } else {
                    offload(result) { readInstances(from, to) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        val host = activity()
        if (host == null) {
            // No activity means no dialog is possible. Answering "not granted"
            // is the truth and lets planning carry on; erroring here would
            // surface as a failure in a flow the user did not start.
            result.success(false)
            return
        }
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        host.requestPermissions(
            arrayOf(Manifest.permission.READ_CALENDAR),
            PERMISSION_REQUEST,
        )
    }

    private fun readSources(): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        cursor(
            context.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                CALENDAR_COLUMNS,
                null,
                null,
                CalendarContract.Calendars.CALENDAR_DISPLAY_NAME + " ASC",
            ),
        ) { c ->
            rows.add(
                mapOf(
                    "id" to c.getLong(0).toString(),
                    "name" to c.getString(1).orEmpty(),
                    "account" to c.getString(2).orEmpty(),
                    "colour" to if (c.isNull(3)) null else c.getInt(3),
                ),
            )
        }
        return rows
    }

    /**
     * Every occurrence between [from] and [to], as epoch milliseconds.
     *
     * `Instances` rather than `Events` on purpose: it expands recurrence,
     * which is most of what a real calendar contains. A weekly lecture is one
     * event row and fifteen commitments.
     */
    private fun readInstances(from: Long, to: Long): List<Map<String, Any?>> {
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().let {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
            it.build()
        }

        val rows = mutableListOf<Map<String, Any?>>()
        cursor(
            context.contentResolver.query(uri, INSTANCE_COLUMNS, null, null, null),
        ) { c ->
            rows.add(
                mapOf(
                    "calendarId" to c.getLong(0).toString(),
                    "start" to c.getLong(1),
                    "end" to c.getLong(2),
                    "allDay" to (c.getInt(3) != 0),
                    // AVAILABILITY_TENTATIVE counts as busy. When in doubt,
                    // block: the domain comment on CalendarFilter carries the
                    // argument, and this is the one place the platform can
                    // usefully collapse three provider values into the two the
                    // rule is written in.
                    "busy" to (
                        c.isNull(4) ||
                            c.getInt(4) != CalendarContract.Events.AVAILABILITY_FREE
                        ),
                    "attendance" to attendance(if (c.isNull(5)) 0 else c.getInt(5)),
                ),
            )
        }
        return rows
    }

    private fun attendance(status: Int): String = when (status) {
        CalendarContract.Attendees.ATTENDEE_STATUS_ACCEPTED -> "accepted"
        CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED -> "declined"
        CalendarContract.Attendees.ATTENDEE_STATUS_INVITED -> "invited"
        CalendarContract.Attendees.ATTENDEE_STATUS_TENTATIVE -> "tentative"
        else -> "none"
    }

    /** Walks [query] to exhaustion and closes it, even if [each] throws. */
    private inline fun cursor(query: Cursor?, each: (Cursor) -> Unit) {
        query?.use { c ->
            while (c.moveToNext()) each(c)
        }
    }

    /**
     * Runs [work] off the platform thread and answers on it.
     *
     * Flutter requires `result` to be used on the platform thread and exactly
     * once, so a failure is reported as an error rather than thrown - or the
     * Dart side hangs forever waiting on a reply that is never coming.
     */
    private fun <T> offload(result: MethodChannel.Result, work: () -> T) {
        val executor = worker
        if (executor == null) {
            result.error("detached", "the calendar channel is not attached", null)
            return
        }
        executor.execute {
            val outcome = runCatching(work)
            android.os.Handler(context.mainLooper).post {
                outcome
                    .onSuccess(result::success)
                    .onFailure { error ->
                        result.error(
                            if (error is SecurityException) "denied" else "failed",
                            error.message ?: error::class.java.simpleName,
                            null,
                        )
                    }
            }
        }
    }
}
