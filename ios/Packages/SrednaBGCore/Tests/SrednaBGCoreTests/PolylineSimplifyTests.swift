// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGCore tests

// Hand-port of the Kotlin `PolylineSimplifyTest`; the shared
// `history/simplify_centerline.json` fixture pins both ports to one output.

import Foundation
import Testing
@testable import SrednaBGCore

struct PolylineSimplifyTests {

    @Test func fewerThanThreePointsPassThroughUnchanged() {
        let two: [[Double]] = [[42.0, 23.0], [42.1, 23.1]]
        #expect(PolylineSimplify.simplify(two) == two)
        #expect(PolylineSimplify.simplify([]).isEmpty)
    }

    @Test func collinearPointsCollapseToTheEndpoints() {
        let line = (0...10).map { [42.0 + Double($0) * 0.001, 23.0] }
        #expect(PolylineSimplify.simplify(line) == [line[0], line[10]])
    }

    @Test func aDeviationBeyondToleranceIsKeptOneWithinIsDropped() {
        let line: [[Double]] = [[41.9, 23.0], [42.0, 23.0005], [42.1, 23.0]]
        #expect(PolylineSimplify.simplify(line, toleranceM: 10.0) == line)
        #expect(PolylineSimplify.simplify(line, toleranceM: 50.0) == [line[0], line[2]])
    }

    @Test func everyOriginalPointStaysWithinToleranceOfTheSimplifiedLine() throws {
        let fx = try loadFixture()
        let out = PolylineSimplify.simplify(fx.points, toleranceM: fx.toleranceM)
        #expect(out.first == fx.points.first)
        #expect(out.last == fx.points.last)
        for p in fx.points {
            #expect(pointToPolylineDistance(p[0], p[1], out) <= fx.toleranceM + 0.01)
        }
    }

    @Test func matchesTheSharedCenterlineFixture() throws {
        let fx = try loadFixture()
        let out = PolylineSimplify.simplify(fx.points, toleranceM: fx.toleranceM)
        #expect(out == fx.expectedIndices.map { fx.points[$0] })
        #expect(out.count < fx.points.count / 5)
    }

    private struct Fixture: Decodable {
        let toleranceM: Double
        let points: [[Double]]
        let expectedIndices: [Int]
    }

    private func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "Resources/history/simplify_centerline", withExtension: "json"),
            "fixture not found"
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}
