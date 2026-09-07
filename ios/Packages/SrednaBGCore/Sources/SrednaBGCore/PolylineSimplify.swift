// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGCore

/// Geometric simplification of a `[lat, lng]` polyline (Douglas–Peucker).
///
/// Hand-port of the Kotlin `PolylineSimplify.kt`: same algorithm, same
/// segment-distance metric (`pointToSegmentDistance`), same traversal order,
/// verified against the shared `history/simplify_centerline.json` fixture.
/// The History feature stores a 10 m simplification of a zone's centerline on
/// each trip record so "Show on map" never depends on the live catalog.
public enum PolylineSimplify {

    /// Default tolerance for stored history geometry, in metres.
    public static let historyToleranceM = 10.0

    /// The subsequence of `points` within `toleranceM` of the original line,
    /// always keeping the first and last point. Fewer than three points are
    /// returned unchanged. Retained points are originals, never interpolated.
    public static func simplify(_ points: [[Double]], toleranceM: Double = historyToleranceM) -> [[Double]] {
        guard points.count >= 3 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            var maxDist = 0.0
            var index = -1
            let a = points[first]
            let b = points[last]
            if first + 1 < last {
                for i in (first + 1)..<last {
                    let d = pointToSegmentDistance(
                        pLat: points[i][0], pLng: points[i][1],
                        aLat: a[0], aLng: a[1],
                        bLat: b[0], bLng: b[1]
                    )
                    if d > maxDist {
                        maxDist = d
                        index = i
                    }
                }
            }
            if index >= 0, maxDist > toleranceM {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }
        return points.enumerated().filter { keep[$0.offset] }.map(\.element)
    }
}
