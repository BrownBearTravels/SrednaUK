// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / core

package com.demosten.srednabg.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue

class PolylineSimplifyTest {

    @Test
    fun `fewer than three points pass through unchanged`() {
        val two = listOf(listOf(42.0, 23.0), listOf(42.1, 23.1))
        assertEquals(two, PolylineSimplify.simplify(two))
        assertEquals(emptyList<List<Double>>(), PolylineSimplify.simplify(emptyList()))
    }

    @Test
    fun `collinear points collapse to the endpoints`() {
        val line = (0..10).map { listOf(42.0 + it * 0.001, 23.0) }
        assertEquals(listOf(line.first(), line.last()), PolylineSimplify.simplify(line))
    }

    @Test
    fun `a deviation beyond tolerance is kept, one within is dropped`() {
        val kink = listOf(42.0, 23.0 + 0.0005) // ~41 m east of the straight line
        val line = listOf(listOf(41.9, 23.0), kink, listOf(42.1, 23.0))
        assertEquals(line, PolylineSimplify.simplify(line, toleranceM = 10.0))
        assertEquals(listOf(line.first(), line.last()), PolylineSimplify.simplify(line, toleranceM = 50.0))
    }

    @Test
    fun `endpoints are always the originals`() {
        val fx = loadFixture()
        val out = PolylineSimplify.simplify(fx.points, fx.toleranceM)
        assertEquals(fx.points.first(), out.first())
        assertEquals(fx.points.last(), out.last())
    }

    @Test
    fun `every original point stays within tolerance of the simplified line`() {
        val fx = loadFixture()
        val out = PolylineSimplify.simplify(fx.points, fx.toleranceM)
        for (p in fx.points) {
            assertTrue(pointToPolylineDistance(p[0], p[1], out) <= fx.toleranceM + 0.01)
        }
    }

    @Test
    fun `matches the shared centerline fixture`() {
        val fx = loadFixture()
        val out = PolylineSimplify.simplify(fx.points, fx.toleranceM)
        assertEquals(fx.expectedIndices.map { fx.points[it] }, out)
        assertTrue(out.size < fx.points.size / 5, "expected a >5x reduction, got ${fx.points.size} -> ${out.size}")
    }

    @Serializable
    private data class Fixture(
        val toleranceM: Double,
        val points: List<List<Double>>,
        val expectedIndices: List<Int>,
    )

    private fun loadFixture(): Fixture {
        val text = requireNotNull(javaClass.classLoader?.getResourceAsStream("history/simplify_centerline.json")) {
            "fixture not found on test classpath"
        }.bufferedReader().use { it.readText() }
        return Json { ignoreUnknownKeys = true }.decodeFromString(Fixture.serializer(), text)
    }
}
