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
import org.junit.Assert.assertTrue
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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 35], application = Application::class)
class UpcomingWidgetRenderTest {
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
        val context = RuntimeEnvironment.getApplication()
        val now = System.currentTimeMillis()
        val items = JSONArray()
        listOf("course", "exam", "schedule").forEachIndexed { index, type ->
            items.put(JSONObject().apply {
                put("id", "$type-$index")
                put("type", type)
                put("title", "示例安排 $index")
                put("location", "示例地点")
                put("start", now - 60_000)
                put("end", now + 3_600_000)
            })
        }
        context.getSharedPreferences("upcoming_widget", 0).edit()
            .putString("snapshot", JSONObject().apply {
                put("version", 1)
                put("from", now - 86_400_000)
                put("until", now + 86_400_000)
                put("items", items)
            }.toString()).commit()
        val views = UpcomingWidget().compose(
            context,
            size = DpSize(200.dp, 200.dp),
            state = emptyPreferences(),
        )
        // Collection adapters are only installed when the root parent is a
        // widget host; a plain FrameLayout silently leaves the list empty.
        for (asynchronous in listOf(false, true)) {
            val host = AppWidgetHostView(context)
            val root = if (asynchronous) applyAsync(views, host) else views.apply(context, host)
            val labels = textViews(root).map { it.text.toString() }
            assertTrue("Title missing: $labels", "接下来" in labels)
            val pixels = (200 * context.resources.displayMetrics.density).toInt()
            root.measure(View.MeasureSpec.makeMeasureSpec(pixels, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(pixels, View.MeasureSpec.EXACTLY))
            root.layout(0, 0, pixels, pixels)
            shadowOf(Looper.getMainLooper()).idle()
            val list = descendants(root).filterIsInstance<ListView>().single()
            assertTrue("Blank list (async=$asynchronous): ${describe(root)}", list.width > 0 && list.height > 0)
            if (Build.VERSION.SDK_INT >= 31) {
                assertTrue("List window must clip its corners", (list.parent as View).clipToOutline)
                assertTrue("No schedule rows (async=$asynchronous): ${describe(root)}", list.count == 3)
                val rowLabels = (0 until list.count).flatMap { index ->
                    textViews(list.adapter.getView(index, null, list)).map { it.text.toString() }
                }
                for (index in 0..2) assertTrue("Schedule missing: $rowLabels", "示例安排 $index" in rowLabels)
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
