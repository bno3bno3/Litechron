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

/**
 * New courses/schedules avoid the two on either side. Established colors stay
 * fixed unless two displayed neighbors match, in which case only the lower one
 * changes. Exams retain the widget's theme error colors.
 */
internal fun upcomingCardPalettes(
    items: List<UpcomingItem>,
    established: Map<String, UpcomingCardPalette> = emptyMap(),
    repairAdjacent: Boolean = true,
): Map<String, UpcomingCardPalette> {
    val result = LinkedHashMap<String, UpcomingCardPalette>()
    val colored = items.withIndex().filter { it.value.type != "exam" }
    // Include established colors below a new insertion before assigning it.
    for ((_, item) in colored) {
        established[item.id]?.let { result[item.id] = it }
    }
    for ((index, entry) in colored.withIndex()) {
        val (displayIndex, item) = entry
        val previous = items.getOrNull(displayIndex - 1)
        val current = result[item.id]
        val collision = previous != null && previous.type != "exam" && current != null && result[previous.id] == current
        if (current != null && (!repairAdjacent || !collision)) continue

        val excluded = (maxOf(0, index - 2)..minOf(colored.lastIndex, index + 2))
            .filter { it != index }.mapNotNull { result[colored[it].value.id] }.toSet()
        val candidates = UpcomingCardPalette.entries.filter { it !in excluded }
        val neighborHues = listOfNotNull(previous, items.getOrNull(displayIndex + 1)).mapNotNull {
            if (it.type == "exam") 0 else result[it.id]?.hue
        }
        fun separation(palette: UpcomingCardPalette): Int = neighborHues.minOfOrNull { hue ->
            val difference = abs(palette.hue - hue)
            minOf(difference, 360 - difference)
        } ?: 360

        val preferred = UpcomingCardPalette.entries[Math.floorMod(item.id.hashCode(), UpcomingCardPalette.entries.size)]
        val palette = if (preferred in candidates && separation(preferred) >= 90) preferred
            else candidates.maxBy { separation(it) }
        result[item.id] = palette
    }
    return result
}
