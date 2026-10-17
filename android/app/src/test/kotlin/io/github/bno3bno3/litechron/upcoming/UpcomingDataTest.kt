package io.github.bno3bno3.litechron.upcoming

import org.junit.Assert.*
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class UpcomingDataTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private fun time(day: Int, hour: Int) = ZonedDateTime.of(2026, 10, day, hour, 0, 0, 0, zone).toInstant().toEpochMilli()
    private fun item(id: String, type: String, start: Long, end: Long) = UpcomingItem(id, type, id, "", start, end)

    @Test fun tiePriorityDoesNotOverrideDifferentStartTimes() {
        val snapshot = UpcomingSnapshot(time(17, 0), time(20, 0), listOf(
            item("course", "course", time(17, 10), time(17, 12)),
            item("schedule", "schedule", time(17, 10), time(17, 12)),
            item("exam", "exam", time(17, 10), time(17, 12)),
            item("earlier", "course", time(17, 9), time(17, 12))))
        assertEquals(listOf("earlier", "exam", "schedule", "course"), snapshot.remaining(time(17, 11), zone).map { it.id })
    }
    @Test fun exactEndAndNextDayAreExcludedButOvernightIsIncluded() {
        val snapshot = UpcomingSnapshot(time(17, 0), time(20, 0), listOf(
            item("ended", "course", time(17, 8), time(17, 10)),
            item("overnight", "schedule", time(16, 23), time(17, 11)),
            item("tomorrow", "exam", time(18, 8), time(18, 9))))
        assertEquals(listOf("overnight"), snapshot.remaining(time(17, 10), zone).map { it.id })
        assertEquals(2, snapshot.today(time(17, 12), zone).size)
        assertTrue(snapshot.remaining(time(17, 12), zone).isEmpty())
        assertEquals(listOf("tomorrow"), snapshot.remaining(time(18, 0), zone).map { it.id })
    }
}
