package io.github.bno3bno3.litechron.upcoming

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
    private const val COLORS = "paletteAssignments"
    private val mutex = Mutex()
    private fun prefs(c: Context) = c.getSharedPreferences("upcoming_widget", Context.MODE_PRIVATE)
    fun raw(c: Context): String? = prefs(c).getString("snapshot", null)
    fun ids(c: Context) = AppWidgetManager.getInstance(c).getAppWidgetIds(
        ComponentName(c, UpcomingWidgetReceiver::class.java))

    private fun savedPalettes(prefs: SharedPreferences): Map<String, UpcomingCardPalette> {
        val json = runCatching { JSONObject(prefs.getString(COLORS, null) ?: "{}") }.getOrNull()
            ?: return emptyMap()
        return json.keys().asSequence().mapNotNull { id ->
            UpcomingCardPalette.entries.find { it.name == json.optString(id) }?.let { id to it }
        }.toMap()
    }

    private fun encodePalettes(palettes: Map<String, UpcomingCardPalette>) =
        JSONObject(palettes.mapValues { it.value.name }).toString()

    private fun palettesFor(snapshot: UpcomingSnapshot, saved: Map<String, UpcomingCardPalette>, now: Long)
        : Map<String, UpcomingCardPalette> {
        val active = snapshot.items.filter { it.end > now }.sortedWith(upcomingItemOrder)
        // Reserve colors throughout the snapshot, but repair only neighbors
        // actually displayed together today, not items on different days.
        val palettes = upcomingCardPalettes(active, saved, repairAdjacent = false)
        return palettes + upcomingCardPalettes(snapshot.remaining(now), palettes)
    }

    internal suspend fun load(c: Context, now: Long): Pair<UpcomingSnapshot?, Map<String, UpcomingCardPalette>> = mutex.withLock {
        val prefs = prefs(c)
        val snapshot = runCatching { raw(c)?.let(UpcomingSnapshot::parse) }.getOrNull()
            ?: return@withLock null to emptyMap()
        val saved = savedPalettes(prefs)
        val palettes = palettesFor(snapshot, saved, now)
        if (palettes != saved) check(prefs.edit().putString(COLORS, encodePalettes(palettes)).commit())
        snapshot to palettes
    }

    suspend fun publish(c: Context, raw: String) {
        mutex.withLock {
            val snapshot = UpcomingSnapshot.parse(raw)
            val generation = JSONObject(raw).getLong("generation")
            val prefs = prefs(c)
            check(generation == prefs.getLong("generation", -1)) { "Stale snapshot" }
            val palettes = palettesFor(snapshot, savedPalettes(prefs), System.currentTimeMillis())
            check(prefs.edit().putString("snapshot", raw).putString(COLORS, encodePalettes(palettes)).commit())
        }
        update(c)
    }

    suspend fun invalidate(c: Context, generation: Long, preserveColors: Boolean = false) {
        val invalidated = mutex.withLock {
            val prefs = prefs(c)
            if (generation < prefs.getLong("generation", -1)) return@withLock false
            val editor = prefs.edit().putLong("generation", generation).remove("snapshot")
            if (!preserveColors) editor.remove(COLORS)
            check(editor.commit())
            true
        }
        if (!invalidated) return
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
