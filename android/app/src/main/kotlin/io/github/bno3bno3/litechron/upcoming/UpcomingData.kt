package io.github.bno3bno3.litechron.upcoming

import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

data class UpcomingItem(val id: String, val type: String, val title: String,
    val location: String, val start: Long, val end: Long)

internal fun UpcomingItem.displayDate(now: Long, zone: ZoneId): LocalDate = maxOf(
    Instant.ofEpochMilli(start).atZone(zone).toLocalDate(),
    Instant.ofEpochMilli(now).atZone(zone).toLocalDate())

internal sealed interface UpcomingRow {
    val id: String

    data class DateHeader(val date: LocalDate) : UpcomingRow {
        override val id = "date:$date"
    }

    data class Event(val item: UpcomingItem, val hasNextInDay: Boolean) : UpcomingRow {
        override val id = "item:${item.id}"
    }
}

data class UpcomingSnapshot(val items: List<UpcomingItem>) {
    // The Flutter page owns ordering and range. Only prune finished items here.
    fun remaining(now: Long): List<UpcomingItem> = items.filter { it.end > now }

    internal fun rows(now: Long, zone: ZoneId = ZoneId.systemDefault()): List<UpcomingRow> = buildList {
        val remaining = remaining(now)
        var previousDate: LocalDate? = null
        remaining.forEachIndexed { index, item ->
            val date = item.displayDate(now, zone)
            if (date != previousDate) add(UpcomingRow.DateHeader(date))
            add(UpcomingRow.Event(item, remaining.getOrNull(index + 1)?.displayDate(now, zone) == date))
            previousDate = date
        }
    }

    companion object {
        fun parse(raw: String): UpcomingSnapshot {
            val json = JSONObject(raw)
            // v1 used a separate 30-day list rather than the page's contents.
            require(json.getInt("version") == 2)
            val array = json.getJSONArray("items")
            val items = (0 until array.length()).map { index ->
                val p = array.getJSONObject(index)
                UpcomingItem(p.getString("id"), p.getString("type"), p.getString("title"),
                    p.getString("location"), p.getLong("start"), p.getLong("end"))
            }
            require(items.all { it.end > it.start && it.type in setOf("exam", "schedule", "course", "flow") })
            return UpcomingSnapshot(items)
        }
    }
}

internal fun dateTitle(date: LocalDate, today: LocalDate): String = when (date) {
    today -> "今天"
    today.plusDays(1) -> "明天"
    today.plusDays(2) -> "后天"
    else -> date.format(DateTimeFormatter.ofPattern(
        if (date.year == today.year) "M月d日 | EEEE" else "yyyy年M月d日 | EEEE",
        Locale.SIMPLIFIED_CHINESE))
}

internal fun timeRange(item: UpcomingItem, now: Long, zone: ZoneId = ZoneId.systemDefault()): String {
    val start = Instant.ofEpochMilli(item.start).atZone(zone)
    val end = Instant.ofEpochMilli(item.end).atZone(zone)
    val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
    val timeFormat = DateTimeFormatter.ofPattern("HH:mm")
    if (start.toLocalDate() == end.toLocalDate()) return "${start.format(timeFormat)}–${end.format(timeFormat)}"
    fun datedTime(value: ZonedDateTime): String {
        val format = DateTimeFormatter.ofPattern(if (value.year == today.year) "M/d HH:mm" else "yyyy/M/d HH:mm")
        return value.format(format)
    }
    return "${datedTime(start)}–${datedTime(end)}"
}
