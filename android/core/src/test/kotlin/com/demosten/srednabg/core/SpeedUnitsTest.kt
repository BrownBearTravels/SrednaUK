// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / core

package com.demosten.srednabg.core

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SpeedUnitsTest {

    @Test
    fun `mph limits convert to exact km per hour`() {
        assertEquals(80.4672, 50.mphToKmh(), 1e-9)
        assertEquals(112.65408, 70.mphToKmh(), 1e-9)
    }

    @Test
    fun `km per hour source limits round to the nearest mph`() {
        assertEquals(87, 140.kmhToMphLimit())
        assertEquals(56, 90.kmhToMphLimit())
        assertEquals(50, 80.kmhToMphLimit())
    }

    @Test
    fun `over-limit verdict agrees with the mph limit, not a rounded km per hour one`() {
        // 80.4 km/h ≈ 49.96 mph. Against a 50 mph limit stored as an integer
        // 80 km/h this read "over"; against the exact 80.4672 it is within.
        val status = AverageSpeedCalc.calculate(
            entryTime = 0L,
            currentTime = 100_000L,
            stopDurationMs = 0L,
            distanceTraveled = 80.4 / 3.6 * 100,
            zoneDistance = 10_000.0,
            speedLimitKmh = 50.mphToKmh(),
        )
        assertFalse(status.isOverLimit)

        val over = AverageSpeedCalc.calculate(
            entryTime = 0L,
            currentTime = 100_000L,
            stopDurationMs = 0L,
            distanceTraveled = 80.6 / 3.6 * 100,
            zoneDistance = 10_000.0,
            speedLimitKmh = 50.mphToKmh(),
        )
        assertTrue(over.isOverLimit)
    }
}
