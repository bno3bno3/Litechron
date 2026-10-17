package io.github.bno3bno3.litechron.upcoming

import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId

data class UpcomingItem(val id: String, val type: String, val title: String,
    val location: String, val start: Long, val end: Long)

data class UpcomingSnapshot(val from: Long, val until: Long, val items: List<UpcomingItem>) {
    fun today(now: Long, zone: ZoneId = ZoneId.systemDefault()): List<UpcomingItem> {
        val date = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val start = date.atStartOfDay(zone).toInstant().toEpochMilli()
        val end = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        return items.filter { it.start < end && it.end > start }
    }
    fun remaining(now: Long, zone: ZoneId = ZoneId.systemDefault()): List<UpcomingItem> =
        today(now, zone).filter { it.end > now }.sortedWith(
            compareBy<UpcomingItem> { if (it.start <= now) 0 else 1 }
                .thenBy { it.start }
                .thenBy { when (it.type) { "exam" -> 0; "schedule" -> 1; else -> 2 } }
                .thenBy { it.end }.thenBy { it.id })

    companion object {
        fun parse(raw: String): UpcomingSnapshot {
            val json = JSONObject(raw)
            require(json.getInt("version") == 1)
            val array = json.getJSONArray("items")
            val items = (0 until array.length()).map { index ->
                val p = array.getJSONObject(index)
                UpcomingItem(p.getString("id"), p.getString("type"), p.getString("title"),
                    p.getString("location"), p.getLong("start"), p.getLong("end"))
            }
            require(items.all { it.end > it.start && it.type in setOf("exam", "schedule", "course") })
            return UpcomingSnapshot(json.getLong("from"), json.getLong("until"), items)
        }
    }
}
