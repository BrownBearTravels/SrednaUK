// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGCore

import Foundation
import Testing
@testable import SrednaBGCore

/// Mirrors the Kotlin `SpeedUnitsTest`.
@Suite("SpeedUnits")
struct SpeedUnitsTests {

    @Test
    func mphLimitsConvertToExactKmh() {
        #expect(abs(50.mphToKmh - 80.4672) < 1e-9)
        #expect(abs(70.mphToKmh - 112.65408) < 1e-9)
    }

    @Test
    func kmhSourceLimitsRoundToNearestMph() {
        #expect(140.kmhToMphLimit == 87)
        #expect(90.kmhToMphLimit == 56)
        #expect(80.kmhToMphLimit == 50)
    }

    @Test
    func maxAheadRoundsDown() {
        // 80.3 km/h ≈ 49.9 mph — must read 49, never 50 (50 mph = 80.47 km/h).
        #expect(80.3.kmhToMphFloor == 49)
    }

    @Test
    func overLimitVerdictAgreesWithTheMphLimit() {
        // 80.4 km/h ≈ 49.96 mph: within 50 mph against the exact 80.4672 km/h.
        let within = AverageSpeedCalc.calculate(
            entryTime: 0, currentTime: 100_000, stopDurationMs: 0,
            distanceTraveled: 80.4 / 3.6 * 100, zoneDistance: 10_000,
            speedLimitKmh: 50.mphToKmh
        )
        #expect(!within.isOverLimit)
        let over = AverageSpeedCalc.calculate(
            entryTime: 0, currentTime: 100_000, stopDurationMs: 0,
            distanceTraveled: 80.6 / 3.6 * 100, zoneDistance: 10_000,
            speedLimitKmh: 50.mphToKmh
        )
        #expect(over.isOverLimit)
    }

    @Test
    func milesFormatting() {
        #expect(formatMiles(1_609.344) == "1.0 mi")
        #expect(formatMiles(12_350) == "7.7 mi")
    }
}
