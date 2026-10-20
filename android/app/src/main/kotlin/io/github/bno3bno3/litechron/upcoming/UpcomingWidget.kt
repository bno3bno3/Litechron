package io.github.bno3bno3.litechron.upcoming

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.glance.*
import androidx.glance.action.*
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.*
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.color.ColorProvider
import androidx.glance.layout.*
import androidx.glance.text.*
import io.github.bno3bno3.litechron.R
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class UpcomingWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = UpcomingWidget()
    override fun onUpdate(c: Context, manager: AppWidgetManager, ids: IntArray) {
        UpcomingRuntime.schedule(c)
        super.onUpdate(c, manager, ids)
    }
    override fun onDisabled(c: Context) {
        UpcomingRuntime.schedule(c)
        super.onDisabled(c)
    }
}

class RefreshUpcomingAction : ActionCallback {
    companion object {
        val busy = booleanPreferencesKey("busy")
        val failed = booleanPreferencesKey("failed")
        private val active = java.util.concurrent.ConcurrentHashMap.newKeySet<GlanceId>()
    }
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        if (!active.add(glanceId)) return
        try {
            updateAppWidgetState(context, glanceId) { it[busy] = true; it[failed] = false }
            UpcomingWidget().update(context, glanceId)
            // Only the native local snapshot is read. No credentials or HTTP.
            UpcomingRuntime.raw(context)?.let(UpcomingSnapshot::parse)
            updateAppWidgetState(context, glanceId) { it[busy] = false }
            UpcomingWidget().update(context, glanceId)
            UpcomingRuntime.schedule(context)
        } catch (_: Exception) {
            updateAppWidgetState(context, glanceId) { it[busy] = false; it[failed] = true }
            UpcomingWidget().update(context, glanceId)
            delay(2000)
            updateAppWidgetState(context, glanceId) { it[failed] = false }
            UpcomingWidget().update(context, glanceId)
        } finally { active.remove(glanceId) }
    }
}

class UpcomingWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val initialData = UpcomingRuntime.load(context, System.currentTimeMillis())
        val intent = Intent(Intent.ACTION_VIEW,
            Uri.parse("${context.getString(R.string.app_link_scheme)}://upcoming"))
            .setClass(context, io.github.bno3bno3.litechron.MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        provideContent {
            GlanceTheme {
                val state = currentState<androidx.datastore.preferences.core.Preferences>()
                // A live Glance session can recompose without calling
                // provideGlance again, so reload after its preferences change.
                val data by produceState(initialValue = initialData, key1 = state) {
                    value = UpcomingRuntime.load(context, System.currentTimeMillis())
                }
                val (snapshot, palettes) = data
                val now = System.currentTimeMillis()
                val remaining = snapshot?.remaining(now).orEmpty()
                val empty = when {
                    snapshot == null -> "打开 Litechron" to "同步课程与日程"
                    now < snapshot.from || now >= snapshot.until -> "打开 Litechron" to "更新接下来的安排"
                    snapshot.today(now).isEmpty() -> "今日暂无安排" to "享受自由的一天"
                    else -> "今日安排已结束" to "好好休息一下吧"
                }
                Column(GlanceModifier.fillMaxSize().background(GlanceTheme.colors.background)
                    .cornerRadius(20.dp).padding(horizontal = 12.dp, vertical = 4.dp)) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(if (state[RefreshUpcomingAction.failed] == true) "刷新失败" else "接下来",
                            GlanceModifier.defaultWeight().clickable(actionStartActivity(intent)).padding(start = 4.dp),
                            style = TextStyle(color = GlanceTheme.colors.onBackground, fontSize = 14.sp, fontWeight = FontWeight.Bold), maxLines = 1)
                        Box(GlanceModifier.size(48.dp).clickable(actionRunCallback<RefreshUpcomingAction>()),
                            contentAlignment = Alignment.Center) {
                            if (state[RefreshUpcomingAction.busy] == true) {
                                Text("…", style = TextStyle(color = GlanceTheme.colors.onBackground, fontSize = 20.sp))
                            } else Image(ImageProvider(R.drawable.sync_24px), "刷新本地安排",
                                GlanceModifier.size(20.dp), colorFilter = ColorFilter.tint(GlanceTheme.colors.onBackground))
                        }
                    }
                    if (remaining.isEmpty() || snapshot == null || now < snapshot.from || now >= snapshot.until) {
                        val compact = LocalSize.current.height < 180.dp
                        Box(GlanceModifier.fillMaxWidth().defaultWeight()
                            .clickable(actionStartActivity(intent))
                            .padding(start = 8.dp, end = 8.dp,
                                top = if (compact) 0.dp else 4.dp,
                                bottom = if (compact) 8.dp else 20.dp),
                            contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(empty.first, style = TextStyle(
                                    color = GlanceTheme.colors.onBackground,
                                    fontSize = 18.sp, fontWeight = FontWeight.Medium,
                                    textAlign = TextAlign.Center))
                                Spacer(GlanceModifier.height(if (compact) 6.dp else 10.dp))
                                Text(empty.second, style = TextStyle(
                                    color = GlanceTheme.colors.onSurfaceVariant,
                                    fontSize = 14.sp, textAlign = TextAlign.Center))
                            }
                        }
                    } else {
                        // Keep the collection in one Glance tree. Nesting it in
                        // AndroidRemoteViews breaks adapter binding during async apply.
                        Box(GlanceModifier.fillMaxWidth().defaultWeight()
                            .background(GlanceTheme.colors.background).cornerRadius(16.dp)) {
                            LazyColumn(GlanceModifier.fillMaxSize()) {
                                items(remaining, itemId = { stableId(it.id) }) { item ->
                                    Card(item, now, actionStartActivity(intent), item.id != remaining.last().id,
                                        palettes[item.id])
                                }
                            }
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) WindowCorners()
                        }
                        Spacer(GlanceModifier.height(12.dp))
                    }
                }
            }
        }
    }

    @Composable
    private fun WindowCorners() {
        // Pre-12 RemoteViews cannot set an outline radius. Fixed masks use the
        // widget background so scrolling cards have the same rounded window.
        Column(GlanceModifier.fillMaxSize()) {
            Row(GlanceModifier.fillMaxWidth()) {
                WindowCorner(R.drawable.upcoming_window_top_left)
                Spacer(GlanceModifier.defaultWeight())
                WindowCorner(R.drawable.upcoming_window_top_right)
            }
            Spacer(GlanceModifier.defaultWeight())
            Row(GlanceModifier.fillMaxWidth()) {
                WindowCorner(R.drawable.upcoming_window_bottom_left)
                Spacer(GlanceModifier.defaultWeight())
                WindowCorner(R.drawable.upcoming_window_bottom_right)
            }
        }
    }

    @Composable
    private fun WindowCorner(drawable: Int) {
        Image(ImageProvider(drawable), contentDescription = null,
            modifier = GlanceModifier.size(16.dp),
            colorFilter = ColorFilter.tint(GlanceTheme.colors.background))
    }

    @Composable
    private fun Card(item: UpcomingItem, now: Long, action: Action, hasNext: Boolean,
        palette: UpcomingCardPalette?) {
        val accent = if (palette == null) GlanceTheme.colors.error else
            ColorProvider(day = Color(palette.lightAccent), night = Color(palette.darkAccent))
        val background = if (palette == null) GlanceTheme.colors.errorContainer else
            ColorProvider(day = Color(palette.lightBackground), night = Color(palette.darkBackground))
        val foreground = if (palette == null) GlanceTheme.colors.onErrorContainer else
            ColorProvider(day = Color(0xFF202124), night = Color(0xFFF1F3F4))
        val type = when (item.type) { "exam" -> "考试"; "schedule" -> "日程"; else -> "课程" }
        Column(GlanceModifier.fillMaxWidth().padding(bottom = if (hasNext) 6.dp else 0.dp)) {
            // The exposed background is the accent stripe. Unlike a fixed-height
            // sibling, it follows the text height without forcing list overflow.
            Column(GlanceModifier.fillMaxWidth().background(accent).cornerRadius(12.dp)
                .clickable(action).padding(start = 3.dp)) {
                Column(GlanceModifier.fillMaxWidth().background(background)
                    .padding(horizontal = 10.dp, vertical = 6.dp)) {
                    Text("${if (item.start <= now) "进行中" else "即将开始"} · $type", maxLines = 1,
                        style = TextStyle(color = foreground, fontSize = 11.sp))
                    Text(item.title, maxLines = 1, style = TextStyle(color = foreground, fontSize = 17.sp, fontWeight = FontWeight.Bold))
                    if (item.location.isNotBlank()) Text(item.location, maxLines = 2,
                        style = TextStyle(color = foreground, fontSize = 14.sp))
                    Text(timeRange(item), maxLines = 1, style = TextStyle(color = foreground, fontSize = 13.sp))
                }
            }
        }
    }
}

// Glance reserves the lowest Long values for automatically generated item IDs.
internal fun stableId(value: String): Long =
    value.fold(1125899906842597L) { hash, char -> hash * 31 + char.code } and Long.MAX_VALUE
internal fun timeRange(item: UpcomingItem): String {
    val zone = ZoneId.systemDefault()
    val start = Instant.ofEpochMilli(item.start).atZone(zone)
    val end = Instant.ofEpochMilli(item.end).atZone(zone)
    val format = DateTimeFormatter.ofPattern("HH:mm")
    val prefix = if (start.toLocalDate() == end.toLocalDate()) "" else if (start.toLocalDate().plusDays(1) == end.toLocalDate()) "次日 " else "${end.monthValue}/${end.dayOfMonth} "
    return "${start.format(format)}–$prefix${end.format(format)}"
}
