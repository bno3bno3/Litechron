package io.github.bno3bno3.litechron.upcoming

import android.app.Application
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
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
import org.robolectric.annotation.Config
import org.json.JSONArray
import org.json.JSONObject

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
        val root = views.apply(context, FrameLayout(context))
        val labels = textViews(root).map { it.text.toString() }
        assertTrue("Title missing: $labels", "接下来" in labels)
    }

    private fun textViews(view: View): List<TextView> = when (view) {
        is TextView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { textViews(view.getChildAt(it)) }
        else -> emptyList()
    }
}
