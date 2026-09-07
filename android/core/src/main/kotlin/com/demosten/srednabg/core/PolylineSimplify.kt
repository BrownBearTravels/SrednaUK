// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / core

package com.demosten.srednabg.core

/**
 * Geometric simplification of a `[lat, lng]` polyline (Douglas–Peucker).
 *
 * Used by the app's History feature to store a compact copy of a zone's
 * centerline on each trip record: at 10 m tolerance a motorway centerline of
 * a few hundred points shrinks to a few dozen while still drawing as the same
 * road at zone-fit zoom. Pure, so it unit-tests on the JVM and hand-ports 1:1
 * to Swift (`PolylineSimplify.swift`) — keep the two in sync via the shared
 * `history/simplify_centerline.json` fixture.
 */
object PolylineSimplify {

    /** Default tolerance for stored history geometry, in metres. */
    const val HISTORY_TOLERANCE_M = 10.0

    /**
     * Return the subsequence of [points] that stays within [toleranceM] of the
     * original line, always keeping the first and last point. Inputs shorter
     * than three points are returned unchanged. Deterministic: the same input
     * always yields the same output, and the retained points are originals
     * (never interpolated), so the endpoints stay exactly where the zone's
     * cameras are.
     */
    fun simplify(points: List<List<Double>>, toleranceM: Double = HISTORY_TOLERANCE_M): List<List<Double>> {
        if (points.size < 3) return points
        val keep = BooleanArray(points.size)
        keep[0] = true
        keep[points.size - 1] = true
        // Explicit stack instead of recursion: an 875-point centerline is fine
        // either way, but a stack keeps the traversal order identical to Swift.
        val stack = ArrayDeque<Pair<Int, Int>>()
        stack.addLast(0 to points.size - 1)
        while (stack.isNotEmpty()) {
            val (first, last) = stack.removeLast()
            var maxDist = 0.0
            var index = -1
            val a = points[first]
            val b = points[last]
            for (i in first + 1 until last) {
                val d = pointToSegmentDistance(points[i][0], points[i][1], a[0], a[1], b[0], b[1])
                if (d > maxDist) {
                    maxDist = d
                    index = i
                }
            }
            if (index >= 0 && maxDist > toleranceM) {
                keep[index] = true
                stack.addLast(first to index)
                stack.addLast(index to last)
            }
        }
        return points.filterIndexed { i, _ -> keep[i] }
    }
}
