package io.github.bno3bno3.litechron.upcoming

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs
import kotlin.math.pow

class UpcomingColorsTest {
    private fun item(id: String, type: String = "course") = UpcomingItem(id, type, id, "", 0, 1)

    private fun assertSeparated(items: List<UpcomingItem>) {
        val palettes = upcomingCardPalettes(items)
        assertEquals(items.filter { it.type != "exam" }.map { it.id }.toSet(), palettes.keys)
        for ((first, second) in items.zipWithNext()) {
            if (first.type == "exam" && second.type == "exam") continue
            val firstHue = palettes[first.id]?.hue ?: 0
            val secondHue = palettes[second.id]?.hue ?: 0
            val difference = abs(firstHue - secondHue)
            assertTrue("${first.id} / ${second.id}", minOf(difference, 360 - difference) >= 90)
        }
    }

    @Test fun allSixColorsIncludingYellowAreReachableAndRepeatable() {
        val colors = (0..1000).map { index ->
            val items = listOf(item("安排-$index"))
            val first = upcomingCardPalettes(items)
            assertEquals(first, upcomingCardPalettes(items))
            first.getValue(items.single().id)
        }.toSet()
        assertEquals(UpcomingCardPalette.entries.toSet(), colors)
    }

    @Test fun collidingIdsAndMixedListsStillHaveSeparatedNeighbors() {
        // Aa and BB have the same JVM string hash.
        val collision = listOf(item("Aa"), item("BB", "schedule"))
        assertSeparated(collision)
        assertNotEquals(upcomingCardPalettes(collision)["Aa"], upcomingCardPalettes(collision)["BB"])
        val items = (0..500).map { index ->
            item("item-$index", when (index % 7) { 0, 1 -> "exam"; 2, 3 -> "schedule"; else -> "course" })
        }
        assertSeparated(items)
        assertEquals(upcomingCardPalettes(items), upcomingCardPalettes(items))
    }

    @Test fun examsOnEitherSideAreAvoidedForEveryPreferredColor() {
        for (index in 0..100) {
            val course = item("course-$index")
            val schedule = item("schedule-$index", "schedule")
            assertSeparated(listOf(course, item("exam", "exam")))
            assertSeparated(listOf(item("exam", "exam"), course))
            assertSeparated(listOf(item("first-exam", "exam"), course, item("last-exam", "exam")))
            assertSeparated(listOf(course, schedule, item("exam", "exam")))
        }
        assertTrue(upcomingCardPalettes(listOf(item("exam", "exam"))).isEmpty())
    }

    @Test fun removedAndReorderedItemsAreRecoloredWithoutChangingInput() {
        val original = (0..30).map { item("course-$it") }
        val before = original.toList()
        assertSeparated(original.filterIndexed { index, _ -> index % 3 != 0 })
        assertSeparated(original.reversed())
        assertEquals(before, original)
        assertTrue(upcomingCardPalettes(emptyList()).isEmpty())
    }

    @Test fun textAndStripesHaveSufficientContrastInBothThemes() {
        for (palette in UpcomingCardPalette.entries) {
            assertTrue("$palette day text", contrast(0xFF202124, palette.lightBackground) >= 4.5)
            assertTrue("$palette night text", contrast(0xFFF1F3F4, palette.darkBackground) >= 4.5)
            assertTrue("$palette day stripe", contrast(palette.lightAccent, palette.lightBackground) >= 3.0)
            assertTrue("$palette night stripe", contrast(palette.darkAccent, palette.darkBackground) >= 3.0)
        }
    }

    private fun contrast(first: Long, second: Long): Double {
        fun luminance(color: Long): Double {
            fun channel(shift: Int): Double {
                val value = ((color shr shift) and 255).toDouble() / 255
                return if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        val a = luminance(first)
        val b = luminance(second)
        return (maxOf(a, b) + 0.05) / (minOf(a, b) + 0.05)
    }
}
