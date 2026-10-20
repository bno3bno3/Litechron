package io.github.bno3bno3.litechron.upcoming

import android.app.Application
import androidx.work.Configuration
import androidx.work.testing.WorkManagerTestInitHelper
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = Application::class)
class UpcomingRuntimeTest {
    @Before fun initializeRuntime() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("upcoming_widget", 0).edit().clear().commit()
        WorkManagerTestInitHelper.initializeTestWorkManager(context, Configuration.Builder().build())
    }

    private fun snapshot(generation: Long, now: Long, items: List<UpcomingItem>): String = JSONObject().apply {
        put("version", 1)
        put("generation", generation)
        put("from", now - 86_400_000)
        put("until", now + 30 * 86_400_000L)
        put("items", JSONArray().apply {
            for (item in items) put(JSONObject().apply {
                put("id", item.id); put("type", item.type); put("title", item.title)
                put("location", item.location); put("start", item.start); put("end", item.end)
            })
        })
    }.toString()

    @Test fun switchRejectsLateOldAccountAndInvalidDataPreservesValidCache() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val first = """{"version":1,"generation":1,"from":0,"until":1000,"items":[]}"""
        val second = first.replace("\"generation\":1", "\"generation\":2")
        UpcomingRuntime.invalidate(context, 1)
        UpcomingRuntime.publish(context, first)
        assertEquals(first, UpcomingRuntime.raw(context))
        UpcomingRuntime.invalidate(context, 2)
        assertNull(UpcomingRuntime.raw(context))
        assertTrue(runCatching { UpcomingRuntime.publish(context, first) }.isFailure)
        assertNull(UpcomingRuntime.raw(context))
        UpcomingRuntime.publish(context, second)
        UpcomingRuntime.invalidate(context, 1)
        assertEquals(second, UpcomingRuntime.raw(context))
        assertTrue(runCatching { UpcomingRuntime.publish(context, "{}") }.isFailure)
        assertEquals(second, UpcomingRuntime.raw(context))
    }

    @Test fun colorsSurvivePublishingInsertionsAndAppRestartButClearOnAccountChange() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val now = System.currentTimeMillis()
        val items = (0..7).map { UpcomingItem("course-$it", "course", "示例课程", "",
            now - 60_000 + it * 1000, now + 3_600_000) }
        UpcomingRuntime.invalidate(context, 1)
        UpcomingRuntime.publish(context, snapshot(1, now, items))
        val initial = UpcomingRuntime.load(context, now).second

        val inserted = UpcomingItem("inserted", "schedule", "示例日程", "", now - 57_500, now + 3_600_000)
        val updated = items + inserted
        UpcomingRuntime.publish(context, snapshot(1, now, updated.reversed()))
        val afterInsert = UpcomingRuntime.load(context, now).second
        for (item in items) assertEquals(initial[item.id], afterInsert[item.id])
        val neighbors = listOf(items[1], items[2], items[3], items[4])
        assertTrue(neighbors.none { afterInsert[it.id] == afterInsert[inserted.id] })

        UpcomingRuntime.invalidate(context, 2, preserveColors = true)
        assertNull(UpcomingRuntime.raw(context))
        UpcomingRuntime.publish(context, snapshot(2, now, updated.filter { it != items.first() }))
        val afterRestart = UpcomingRuntime.load(context, now).second
        assertEquals(afterInsert.filterKeys { it != items.first().id }, afterRestart)

        UpcomingRuntime.invalidate(context, 3)
        assertFalse(context.getSharedPreferences("upcoming_widget", 0).contains("paletteAssignments"))
        assertTrue(UpcomingRuntime.load(context, now).second.isEmpty())
    }

    @Test fun overlappingEndOnlyRepairsTheLowerAdjacentMatchAndPersistsIt() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val now = System.currentTimeMillis()
        val items = listOf(
            UpcomingItem("a", "schedule", "示例日程", "", now - 3000, now + 60_000),
            UpcomingItem("b", "course", "示例课程", "", now - 2000, now + 1000),
            UpcomingItem("c", "course", "示例课程", "", now - 1000, now + 60_000))
        val established = mapOf("a" to UpcomingCardPalette.BLUE, "b" to UpcomingCardPalette.TEAL,
            "c" to UpcomingCardPalette.BLUE)
        context.getSharedPreferences("upcoming_widget", 0).edit()
            .putString("snapshot", snapshot(1, now, items))
            .putString("paletteAssignments", JSONObject(established.mapValues { it.value.name }).toString()).commit()

        assertEquals(established, UpcomingRuntime.load(context, now).second)
        val repaired = UpcomingRuntime.load(context, now + 1000).second
        assertEquals(established["a"], repaired["a"])
        assertNotEquals(established["c"], repaired["c"])
        assertFalse(repaired.containsKey("b"))
        assertEquals(repaired, UpcomingRuntime.load(context, now + 2000).second)
        val stored = JSONObject(context.getSharedPreferences("upcoming_widget", 0)
            .getString("paletteAssignments", "{}")!!)
        assertEquals(repaired.getValue("c").name, stored.getString("c"))
    }
}
