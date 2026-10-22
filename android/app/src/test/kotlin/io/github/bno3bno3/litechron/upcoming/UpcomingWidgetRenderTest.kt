package io.github.bno3bno3.litechron.upcoming

import android.app.Application
import android.appwidget.AppWidgetHostView
import android.content.Context
import android.os.Build
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ListView
import android.widget.RemoteViews
import android.widget.TextView
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.emptyPreferences
import androidx.glance.appwidget.compose
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executor
import java.lang.reflect.Proxy
import java.time.Instant
import java.time.ZoneId

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 35], application = Application::class)
class UpcomingWidgetRenderTest {
    @Before fun clearSnapshot() {
        RuntimeEnvironment.getApplication().getSharedPreferences("upcoming_widget", 0).edit().clear().commit()
    }

    @Test fun emptyWidgetComposesAndInflatesWithTitle() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val views = UpcomingWidget().compose(
            context,
            size = DpSize(200.dp, 200.dp),
            state = emptyPreferences(),
        )
        val root = views.apply(context, FrameLayout(context))
        val labels = textViews(root).map { it.text.toString() }
        assertTrue("Title missing: $labels", "接下来" in labels)
        assertTrue("Empty state missing: $labels", "打开 Litechron" in labels)
    }

    @Test fun scheduledWidgetComposesAndInflates() = runBlocking {
        checkScheduledWidget(DpSize(200.dp, 200.dp))
    }

    @Test fun smallWidgetKeepsItsScrollableDateRows() = runBlocking {
        checkScheduledWidget(DpSize(110.dp, 110.dp))
    }

    @Test fun tallWidgetKeepsItsScrollableDateRows() = runBlocking {
        checkScheduledWidget(DpSize(320.dp, 400.dp))
    }

    @Test @Config(qualifiers = "night")
    fun darkWidgetComposesAndInflates() = runBlocking {
        checkScheduledWidget(DpSize(200.dp, 200.dp))
    }

    @Test fun finishedListShowsAnUpcomingEmptyState() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        saveSnapshot(context, JSONArray().put(JSONObject().apply {
            put("id", "ended"); put("type", "flow"); put("title", "示例规划")
            put("location", ""); put("start", 1); put("end", 2)
        }))
        val views = UpcomingWidget().compose(context, size = DpSize(200.dp, 200.dp), state = emptyPreferences())
        val labels = textViews(views.apply(context, FrameLayout(context))).map { it.text.toString() }
        assertTrue("Wrong empty state: $labels", "暂无接下来的安排" in labels)
    }

    @Test fun futureOnlyListShowsTomorrowInsteadOfATodayEmptyState() = runBlocking {
        checkScheduledWidget(DpSize(200.dp, 200.dp), futureOnly = true)
    }

    private fun saveSnapshot(context: Context, items: JSONArray) {
        context.getSharedPreferences("upcoming_widget", 0).edit()
            .putString("snapshot", JSONObject().apply {
                put("version", 2)
                put("items", items)
            }.toString()).commit()
    }

    private suspend fun checkScheduledWidget(size: DpSize, futureOnly: Boolean = false) {
        val context = RuntimeEnvironment.getApplication()
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val tomorrow = today.plusDays(1).atTime(10, 0).atZone(zone).toInstant().toEpochMilli()
        val dayAfterTomorrow = today.plusDays(2).atTime(10, 0).atZone(zone).toInstant().toEpochMilli()
        val far = today.plusDays(80).atTime(10, 0).atZone(zone).toInstant().toEpochMilli()
        val events = buildList {
            if (!futureOnly) listOf("course", "exam", "schedule", "flow").forEachIndexed { index, type ->
                add(UpcomingItem("$type-$index", type, "示例安排 $index", "示例地点", now - 60_000, now + 3_600_000))
            }
            add(UpcomingItem("tomorrow", "schedule", "明天的日程", "", tomorrow, tomorrow + 3_600_000))
            add(UpcomingItem("day-after-tomorrow", "schedule", "后天的日程", "", dayAfterTomorrow, dayAfterTomorrow + 3_600_000))
            add(UpcomingItem("far", "flow", "较远日期的规划", "示例地点", far, far + 3_600_000))
        }
        val items = JSONArray()
        events.forEach { item ->
            items.put(JSONObject().apply {
                put("id", item.id); put("type", item.type); put("title", item.title)
                put("location", item.location); put("start", item.start); put("end", item.end)
            })
        }
        saveSnapshot(context, items)
        val views = UpcomingWidget().compose(
            context,
            size = size,
            state = emptyPreferences(),
        )
        // Collection adapters are only installed when the root parent is a
        // widget host; a plain FrameLayout silently leaves the list empty.
        for (asynchronous in listOf(false, true)) {
            val host = AppWidgetHostView(context)
            val root = if (asynchronous) applyAsync(views, host) else views.apply(context, host)
            val labels = textViews(root).map { it.text.toString() }
            assertTrue("Title missing: $labels", "接下来" in labels)
            val title = textViews(root).single { it.text.toString() == "接下来" }
            // Glance may put the click target on a wrapper around the text.
            assertTrue("Title should open the page: ${describe(root)}",
                generateSequence<View>(title) { it.parent as? View }.any { it.hasOnClickListeners() })
            val width = (size.width.value * context.resources.displayMetrics.density).toInt()
            val height = (size.height.value * context.resources.displayMetrics.density).toInt()
            root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
            root.layout(0, 0, width, height)
            shadowOf(Looper.getMainLooper()).idle()
            val list = descendants(root).filterIsInstance<ListView>().single()
            assertTrue("Blank list (async=$asynchronous): ${describe(root)}", list.width > 0 && list.height > 0)
            if (Build.VERSION.SDK_INT >= 31) {
                assertTrue("List window must clip its corners", (list.parent as View).clipToOutline)
                val dates = events.map { it.displayDate(now, zone) }.distinct()
                assertTrue("Missing date/event rows (async=$asynchronous): ${describe(root)}", list.count == events.size + dates.size)
                val rowLabels = (0 until list.count).flatMap { index ->
                    textViews(list.adapter.getView(index, null, list)).map { it.text.toString() }
                }
                for (event in events) assertTrue("Schedule missing: $rowLabels", event.title in rowLabels)
                assertEquals("Tomorrow label missing: $rowLabels", 1, rowLabels.count { it == "明天" })
                assertEquals("Day-after-tomorrow label missing: $rowLabels", 1, rowLabels.count { it == "后天" })
                assertEquals("Unexpected today headers: $rowLabels", if (futureOnly) 0 else 1,
                    rowLabels.count { it == "今天" })
                assertEquals("Unexpected date headers: $rowLabels", listOf(dateTitle(today.plusDays(80), today)),
                    rowLabels.filter { " | 星期" in it })
                val firstRowLabels = textViews(list.adapter.getView(0, null, list)).map { it.text.toString() }
                assertTrue("Unexpected first row: $firstRowLabels",
                    (if (futureOnly) "明天" else "今天") in firstRowLabels)
                assertTrue("Flow type missing: $rowLabels", rowLabels.any { it.endsWith("· 规划任务") })
            }
        }
    }

    private fun applyAsync(views: RemoteViews, host: AppWidgetHostView): View {
        var applied: View? = null
        var failure: Exception? = null
        // Launcher async inflation is a hidden framework API, available in the
        // full Android runtime used by Robolectric rather than the SDK stubs.
        val listenerClass = Class.forName("android.widget.RemoteViews\$OnViewAppliedListener")
        val listener = Proxy.newProxyInstance(listenerClass.classLoader, arrayOf(listenerClass)) { _, method, args ->
            when (method.name) {
                "onViewApplied" -> applied = args!![0] as View
                "onError" -> failure = args!![0] as Exception
            }
            null
        }
        RemoteViews::class.java.getMethod("applyAsync", Context::class.java, ViewGroup::class.java,
            Executor::class.java, listenerClass).invoke(views, host.context, host, Executor { it.run() }, listener)
        shadowOf(Looper.getMainLooper()).idle()
        failure?.let { throw it }
        return checkNotNull(applied) { "Widget async apply did not finish" }
    }

    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun describe(view: View) = descendants(view).joinToString("\n") {
        "${it.javaClass.simpleName} id=${it.id} size=${it.width}x${it.height} lp=${it.layoutParams?.width}x${it.layoutParams?.height}"
    }

    private fun textViews(view: View): List<TextView> = when (view) {
        is TextView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { textViews(view.getChildAt(it)) }
        else -> emptyList()
    }
}
