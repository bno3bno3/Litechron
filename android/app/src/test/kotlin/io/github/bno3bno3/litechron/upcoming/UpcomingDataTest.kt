package io.github.bno3bno3.litechron.upcoming

import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

class UpcomingDataTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private fun time(day: Int, hour: Int) = ZonedDateTime.of(2026, 10, day, hour, 0, 0, 0, zone).toInstant().toEpochMilli()
    private fun item(id: String, type: String, start: Long, end: Long) = UpcomingItem(id, type, id, "", start, end)

    @Test fun allTypesKeepThePageOrderWithoutAPrioritySort() {
        val snapshot = UpcomingSnapshot(listOf(
            item("course", "course", time(21, 10), time(21, 12)),
            item("schedule", "schedule", time(21, 10), time(21, 12)),
            item("flow", "flow", time(21, 10), time(21, 12)),
            item("exam", "exam", time(21, 10), time(21, 12))))
        assertEquals(listOf("course", "schedule", "flow", "exam"), snapshot.remaining(time(21, 11)).map { it.id })
    }

    @Test fun exactEndIsExcludedButOvernightAndAllFutureItemsRemain() {
        val far = time(21, 12) + 80 * 86_400_000L
        val snapshot = UpcomingSnapshot(listOf(
            item("overnight", "schedule", time(20, 23), time(21, 11)),
            item("ended", "course", time(21, 8), time(21, 10)),
            item("tomorrow", "exam", time(22, 8), time(22, 9)),
            item("far", "flow", far, far + 3_600_000)))
        assertEquals(listOf("overnight", "tomorrow", "far"), snapshot.remaining(time(21, 10)).map { it.id })
        assertEquals(listOf("tomorrow", "far"), snapshot.remaining(time(21, 12)).map { it.id })
        assertEquals(listOf("tomorrow", "far"), snapshot.remaining(time(22, 0)).map { it.id })
        assertTrue(snapshot.remaining(far + 3_600_000).isEmpty())
    }

    @Test fun rowsIncludeTodaySkipEmptyDaysAndKeepStableDistinctIds() {
        val snapshot = UpcomingSnapshot(listOf(
            item("a", "course", time(21, 10), time(21, 12)),
            item("b", "flow", time(21, 13), time(21, 14)),
            item("c", "schedule", time(22, 8), time(22, 9)),
            item("d", "exam", time(24, 8), time(24, 9))))
        val rows = snapshot.rows(time(21, 11), zone)
        assertEquals(listOf("date:2026-10-21", "item:a", "item:b", "date:2026-10-22", "item:c", "date:2026-10-24", "item:d"),
            rows.map { it.id })
        assertEquals(listOf("a", "b", "c", "d"), rows.filterIsInstance<UpcomingRow.Event>().map { it.item.id })
        assertEquals(listOf(true, false, false, false), rows.filterIsInstance<UpcomingRow.Event>().map { it.hasNextInDay })
        assertEquals(rows.size, rows.map { it.id }.toSet().size)
        assertEquals(rows.size, rows.map { stableId(it.id) }.toSet().size)
        assertEquals(rows.drop(3), snapshot.rows(time(22, 0), zone))
        assertEquals(rows.drop(3), snapshot.rows(time(21, 15), zone))
    }

    @Test fun todayOnlyListContainsOneTodayHeaderBeforeItsEvents() {
        val snapshot = UpcomingSnapshot(listOf(
            item("a", "course", time(21, 10), time(21, 12)),
            item("b", "flow", time(21, 13), time(21, 14))))
        val rows = snapshot.rows(time(21, 11), zone)
        assertEquals(listOf("date:2026-10-21", "item:a", "item:b"), rows.map { it.id })
        assertEquals("今天", dateTitle((rows.first() as UpcomingRow.DateHeader).date, LocalDate.of(2026, 10, 21)))
        assertEquals(listOf(true, false), rows.filterIsInstance<UpcomingRow.Event>().map { it.hasNextInDay })
    }

    @Test fun futureOnlyListStartsWithTheFirstAvailableDate() {
        val snapshot = UpcomingSnapshot(listOf(item("later", "schedule", time(23, 10), time(23, 12))))
        val rows = snapshot.rows(time(21, 11), zone)
        assertEquals(listOf("date:2026-10-23", "item:later"), rows.map { it.id })
        assertEquals("后天", dateTitle((rows.first() as UpcomingRow.DateHeader).date, LocalDate.of(2026, 10, 21)))
    }

    @Test fun midnightRelabelsTomorrowAsTodayAndTheFollowingDayAsTomorrow() {
        val snapshot = UpcomingSnapshot(listOf(
            item("tomorrow", "course", time(22, 10), time(22, 12)),
            item("after", "schedule", time(23, 10), time(23, 12))))
        val before = snapshot.rows(time(21, 23), zone)
        val after = snapshot.rows(time(22, 0), zone)
        assertEquals(listOf("明天", "后天"), before.filterIsInstance<UpcomingRow.DateHeader>()
            .map { dateTitle(it.date, LocalDate.of(2026, 10, 21)) })
        assertEquals(before, after)
        assertEquals(listOf("今天", "明天"), after.filterIsInstance<UpcomingRow.DateHeader>()
            .map { dateTitle(it.date, LocalDate.of(2026, 10, 22)) })
    }

    @Test fun overnightIsShownOnceUnderTodayUntilItsEnd() {
        val snapshot = UpcomingSnapshot(listOf(item("overnight", "schedule", time(21, 23), time(22, 2))))
        val before = snapshot.rows(time(21, 23), zone)
        val after = snapshot.rows(time(22, 0), zone)
        assertEquals(listOf("date:2026-10-21", "item:overnight"), before.map { it.id })
        assertEquals(listOf("date:2026-10-22", "item:overnight"), after.map { it.id })
        assertEquals("今天", dateTitle((after.first() as UpcomingRow.DateHeader).date, LocalDate.of(2026, 10, 22)))
        assertEquals(before.last(), after.last())
        assertTrue(snapshot.rows(time(22, 2), zone).isEmpty())
    }

    @Test fun nearHeadersUseRelativeLabelsAcrossMonthAndYearBoundaries() {
        for (today in listOf(LocalDate.of(2026, 10, 21), LocalDate.of(2026, 10, 30),
            LocalDate.of(2026, 10, 31), LocalDate.of(2026, 12, 30), LocalDate.of(2026, 12, 31))) {
            assertEquals("今天", dateTitle(today, today))
            assertEquals("明天", dateTitle(today.plusDays(1), today))
            assertEquals("后天", dateTitle(today.plusDays(2), today))
        }
    }

    @Test fun distantHeadersUseChineseWeekdaysAndShowTheYearWhenNeeded() {
        val today = LocalDate.of(2026, 10, 21)
        assertEquals("10月24日 | 星期六", dateTitle(today.plusDays(3), today))
        assertEquals("2027年1月1日 | 星期五", dateTitle(LocalDate.of(2027, 1, 1), today))
    }

    @Test fun timeRangesIdentifyBothDatesForOvernightAndCrossYearItems() {
        val now = time(22, 0)
        assertEquals("10:00–12:00", timeRange(item("course", "course", time(22, 10), time(22, 12)), now, zone))
        assertEquals("10/21 23:00–10/22 02:00", timeRange(item("night", "schedule", time(21, 23), time(22, 2)), now, zone))
        assertEquals("10/21 23:00–10/24 02:00", timeRange(item("long", "schedule", time(21, 23), time(24, 2)), now, zone))
        val newYear = ZonedDateTime.of(2027, 1, 1, 2, 0, 0, 0, zone).toInstant().toEpochMilli()
        val previous = newYear - 3 * 3_600_000
        assertEquals("2026/12/31 23:00–1/1 02:00", timeRange(item("year", "schedule", previous, newYear), newYear - 3_600_000, zone))
    }
}
