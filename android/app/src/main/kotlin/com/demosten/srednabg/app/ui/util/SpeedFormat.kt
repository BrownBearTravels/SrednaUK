// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / app

package com.demosten.srednabg.app.ui.util

import com.demosten.srednabg.core.KMH_PER_MPH
import java.util.Locale
import kotlin.math.floor

const val DASH_PLACEHOLDER = "--"
private const val METRES_PER_MILE = 1609.344

// Display conversions. Measured speeds are km/h end to end and convert only
// here; zone limits are already whole mph (core SpeedUnits.kt) and must NOT be
// passed through these.
fun Double.kmhToMph(): Double = this / KMH_PER_MPH
fun Double?.kmhToMph(): Double? = this?.let { it / KMH_PER_MPH }

/**
 * "Max ahead" in whole mph, rounded **down**: rounding up could advise a speed
 * that tips the average over the limit (80.3 km/h would read "50 mph", which is
 * 80.47 km/h).
 */
fun Double.kmhToMphFloor(): Int = floor(kmhToMph()).toInt()

/** Remaining distance, e.g. "1.3 mi". */
fun formatMiles(metres: Double): String =
    String.format(Locale.UK, "%.1f mi", metres / METRES_PER_MILE)

fun Double.metresToMiles(): Double = this / METRES_PER_MILE

// An integer conversion specifier (`%d`/`%o`/`%x`/`%X`, with optional flags/width)
// requires an Int arg; a float specifier (`%.1f`) takes the Double as-is. Match the
// specifier explicitly instead of sniffing for a bare 'd', which would mis-fire on
// a literal 'd' elsewhere in the format string (e.g. "%.1f km/h — done").
private val INT_CONVERSION = Regex("%[-#+ 0,(]*\\d*[doxX]")

fun Double?.orDash(format: String = "%d"): String {
    if (this == null || isNaN() || isInfinite()) return DASH_PLACEHOLDER
    return format.format(if (INT_CONVERSION.containsMatchIn(format)) toInt() else this)
}
