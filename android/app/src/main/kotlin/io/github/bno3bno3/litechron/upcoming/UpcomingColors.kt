package io.github.bno3bno3.litechron.upcoming

import kotlin.math.abs

/** Soft containers with stronger stripes; text uses a neutral day/night color. */
internal enum class UpcomingCardPalette(
    val hue: Int,
    val lightBackground: Long,
    val darkBackground: Long,
    val lightAccent: Long,
    val darkAccent: Long,
) {
    BLUE(210, 0xFFE4EFFB, 0xFF213347, 0xFF3979B9, 0xFF91BEED),
    TEAL(165, 0xFFDFF3ED, 0xFF203D35, 0xFF287F69, 0xFF82CCB6),
    GREEN(110, 0xFFE9F2DE, 0xFF2C3B25, 0xFF56863D, 0xFFA9CF8B),
    ORANGE(30, 0xFFFFEBD9, 0xFF473323, 0xFFB36C2C, 0xFFE5AD79),
    PURPLE(270, 0xFFF0E6FA, 0xFF372A45, 0xFF8552AF, 0xFFC7A1E7),
    YELLOW(55, 0xFFFAF3CF, 0xFF403A20, 0xFF93801B, 0xFFE0CB6B);
}

/** Input is the actual display order. Exams retain the widget's theme error colors. */
internal fun upcomingCardPalettes(items: List<UpcomingItem>): Map<String, UpcomingCardPalette> {
    val result = LinkedHashMap<String, UpcomingCardPalette>()
    var previousHue: Int? = null
    for ((index, item) in items.withIndex()) {
        if (item.type == "exam") {
            previousHue = 0
            continue
        }
        val neighbors = listOfNotNull(previousHue, 0.takeIf { items.getOrNull(index + 1)?.type == "exam" })
        fun separation(palette: UpcomingCardPalette): Int = neighbors.minOfOrNull { hue ->
            val difference = abs(palette.hue - hue)
            minOf(difference, 360 - difference)
        } ?: 360

        val preferred = UpcomingCardPalette.entries[Math.floorMod(item.id.hashCode(), UpcomingCardPalette.entries.size)]
        val palette = if (separation(preferred) >= 90) preferred
            else UpcomingCardPalette.entries.maxBy { separation(it) }
        result[item.id] = palette
        previousHue = palette.hue
    }
    return result
}
