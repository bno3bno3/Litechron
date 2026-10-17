package io.github.bno3bno3.litechron.upcoming

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.work.*
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.glance.appwidget.state.updateAppWidgetState
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit

object UpcomingRuntime {
    private const val WORK = "upcoming-local-refresh"
    private val mutex = Mutex()
    private fun prefs(c: Context) = c.getSharedPreferences("upcoming_widget", Context.MODE_PRIVATE)
    fun raw(c: Context): String? = prefs(c).getString("snapshot", null)
    fun ids(c: Context) = AppWidgetManager.getInstance(c).getAppWidgetIds(
        ComponentName(c, UpcomingWidgetReceiver::class.java))

    suspend fun publish(c: Context, raw: String) = mutex.withLock {
        UpcomingSnapshot.parse(raw)
        val generation = JSONObject(raw).getLong("generation")
        val prefs = prefs(c)
        check(generation == prefs.getLong("generation", -1)) { "Stale snapshot" }
        check(prefs.edit().putString("snapshot", raw).commit())
        update(c)
    }

    suspend fun invalidate(c: Context, generation: Long) = mutex.withLock {
        if (generation < prefs(c).getLong("generation", -1)) return@withLock
        check(prefs(c).edit().putLong("generation", generation).remove("snapshot").commit())
        update(c)
    }

    suspend fun update(c: Context) {
        for (id in ids(c)) {
            val glanceId = androidx.glance.appwidget.AppWidgetId(id)
            updateAppWidgetState(c, glanceId) {
                it[longPreferencesKey("renderAt")] = System.currentTimeMillis()
                it[RefreshUpcomingAction.busy] = false
            }
            UpcomingWidget().update(c, glanceId)
        }
        schedule(c)
    }

    private fun alarm(c: Context): PendingIntent = PendingIntent.getBroadcast(c, 0,
        Intent(c, UpcomingClockReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun schedule(c: Context) {
        val manager = c.getSystemService(AlarmManager::class.java)
        if (ids(c).isEmpty()) {
            WorkManager.getInstance(c).cancelUniqueWork(WORK)
            manager.cancel(alarm(c))
            return
        }
        WorkManager.getInstance(c).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<UpcomingRefreshWorker>(15, TimeUnit.MINUTES).build())
        val now = System.currentTimeMillis()
        var next = LocalDate.now().plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val snapshot = runCatching { raw(c)?.let(UpcomingSnapshot::parse) }.getOrNull()
        snapshot?.items?.forEach {
            if (it.start > now) next = minOf(next, it.start)
            if (it.end > now) next = minOf(next, it.end)
        }
        // Inexact and non-wakeup: no exact-alarm permission or network login.
        manager.set(AlarmManager.RTC, next, alarm(c))
    }

    fun enqueue(c: Context) {
        if (ids(c).isNotEmpty()) WorkManager.getInstance(c).enqueueUniqueWork(
            "$WORK-now", ExistingWorkPolicy.REPLACE, OneTimeWorkRequestBuilder<UpcomingRefreshWorker>().build())
    }
}

class UpcomingRefreshWorker(c: Context, params: WorkerParameters) : CoroutineWorker(c, params) {
    override suspend fun doWork(): Result = try {
        UpcomingRuntime.update(applicationContext)
        Result.success()
    } catch (_: Exception) { Result.retry() }
}

class UpcomingClockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { UpcomingRuntime.enqueue(context) }
}
