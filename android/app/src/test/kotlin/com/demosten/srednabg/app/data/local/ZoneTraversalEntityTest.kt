// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / app

package com.demosten.srednabg.app.data.local

import com.demosten.srednabg.core.SpeedSample
import com.google.gson.FieldNamingPolicy
import com.google.gson.GsonBuilder
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ZoneTraversalEntityTest {

    // Same Gson configuration AppModule.provideGson() builds, so the
    // serialize/parse pair matches what the app actually persists.
    private val gson = GsonBuilder()
        .setFieldNamingPolicy(FieldNamingPolicy.LOWER_CASE_WITH_UNDERSCORES)
        .create()

    @Test
    fun `samples round-trip through the JSON column`() {
        val samples = listOf(
            SpeedSample(1000, 88.5),
            SpeedSample(2000, 120.0),
            SpeedSample(3000, 133.3),
        )
        val json = samples.toSamplesJson(gson)
        val entity = entityWith(json)
        assertEquals(samples, entity.speedSamples(gson))
    }

    @Test
    fun `blank samples column parses to empty list`() {
        assertTrue(entityWith("").speedSamples(gson).isEmpty())
    }

    @Test
    fun `malformed samples column parses to empty list, not a crash`() {
        assertTrue(entityWith("{not valid json").speedSamples(gson).isEmpty())
    }

    @Test
    fun `snapshotZone rebuilds the recorded geometry keyed by the record id`() {
        val centerline = listOf(listOf(42.55, 23.7), listOf(42.5, 23.8), listOf(42.43, 23.86))
        val entity = entityWith("[]").copy(
            description = "Вакарел – Ихтиман",
            startLat = 42.55, startLng = 23.7,
            endLat = 42.43, endLng = 23.86,
            centerlineJson = centerline.toCenterlineJson(gson),
        )
        val zone = entity.snapshotZone(gson)!!
        assertEquals("id", zone.id)
        assertEquals("Вакарел – Ихтиман", zone.description)
        assertEquals(42.55, zone.start.lat)
        assertEquals(23.86, zone.end.lng)
        assertEquals(centerline, zone.centerline)
        assertEquals(140, zone.speedLimits.car)
        assertEquals("history", zone.source)
    }

    @Test
    fun `snapshotZone is null for a pre-snapshot row`() {
        assertNull(entityWith("[]").snapshotZone(gson))
    }

    @Test
    fun `snapshotZone is null when the geometry is unusable`() {
        val base = entityWith("[]").copy(startLat = 42.0, startLng = 23.0, endLat = 42.1, endLng = 23.1)
        assertNull(base.copy(centerlineJson = "[[42.0,23.0]]").snapshotZone(gson))
        assertNull(base.copy(centerlineJson = "{broken").snapshotZone(gson))
        assertNull(base.copy(centerlineJson = "[[42.0,23.0],[42.1,23.1]]", endLat = null).snapshotZone(gson))
    }

    private fun entityWith(samplesJson: String) = ZoneTraversalEntity(
        id = "id",
        zoneId = "zone",
        road = "road",
        roadLatin = null,
        direction = "east",
        speedLimitKmh = 140,
        vehicleType = "car",
        entryTimeMs = 0,
        exitTimeMs = 60_000,
        avgSpeedKmh = 120.0,
        sustainedMinKmh = 100.0,
        sustainedMaxKmh = 130.0,
        isOverLimit = false,
        distanceM = 19160,
        samplesJson = samplesJson,
    )
}
