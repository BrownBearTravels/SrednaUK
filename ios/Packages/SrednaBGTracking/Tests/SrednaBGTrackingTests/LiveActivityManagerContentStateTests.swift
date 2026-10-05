// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGTracking

#if os(iOS)
import Foundation
import Testing
@testable import SrednaBGTracking
import SrednaBGCore

// NOT `@available(iOS 16.2, *)`: the `@Suite` / `@Test` macros reject an
// availability-narrowed declaration ("Attribute 'Suite' cannot be applied to
// this structure because it has been marked '@available'"), which silently kept
// this whole file from ever compiling. The annotation was redundant anyway —
// Package.swift floors iOS at 17, so `LiveActivityManager`'s own 16.2 gate is
// always satisfied here. The file stays `#if os(iOS)` because ActivityKit's
// core symbols don't exist on macOS, so `swift test` (macOS) skips it; run it
// with:
//   xcodebuild test -workspace . -scheme SrednaBG-Package \
//       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
@Suite("LiveActivityManager.contentState")
struct LiveActivityManagerContentStateTests {

    private static let zone = Zone(
        id: "trakiya-01-west",
        road: "АМ Тракия",
        roadLatin: "Trakiya",
        direction: "west",
        description: "Test",
        start: ZoneEndpoint(lat: 42.427, lng: 23.855),
        end: ZoneEndpoint(lat: 42.550, lng: 23.703),
        distanceM: 19_160,
        // Trakiya's 140/90/100 km/h limits as whole mph (SpeedUnits.swift).
        speedLimits: SpeedLimits(car: 87, truck: 56, bus: 62, motorcycle: 87),
        centerline: [[42.427, 23.855], [42.550, 23.703]],
        source: "test",
        lastVerified: "2026-04-12"
    )

    private func inZone(
        avg: Double?,
        traveled: Double = 4_000,
        remaining: Double = 15_160,
        over: Bool = false
    ) -> ZoneState.InZone {
        ZoneState.InZone(
            zone: Self.zone,
            entryTime: 0,
            distanceTraveled: traveled,
            speedStatus: SpeedStatus(
                avgSpeed: avg,
                maxSpeedForRemainder: 140,
                distanceRemaining: remaining,
                timeRemaining: 0,
                isOverLimit: over
            ),
            distanceRemaining: remaining
        )
    }

    @Test("Maps every ContentState field from InZone + current speed")
    func mapsEveryField() {
        let state = inZone(avg: 120.4, traveled: 4_000.6, remaining: 15_159.4)
        let content = LiveActivityManager.contentState(
            from: state,
            currentSpeedKmh: 132.7,
            limitMph: 140
        )
        #expect(content.phase == .inZone)
        #expect(content.roadName == "АМ Тракия")
        #expect(content.avgSpeedMph == 75)  // 120.4 km/h
        #expect(content.currentSpeedMph == 82)  // 132.7 km/h
        #expect(content.speedLimitMph == 140)
        #expect(content.distanceTraveledM == 4_001)
        #expect(content.zoneTotalM == 19_160)
        #expect(content.distanceRemainingM == 15_159)
        #expect(content.isOverLimit == false)
    }

    @Test("Badge shows the vehicle-resolved limit, not the car default")
    func vehicleResolvedLimitWins() {
        // Truck limit (90) differs from car (140) in the fixture zone — the
        // chip must show the limit the engine's over-limit verdict used.
        let content = LiveActivityManager.contentState(
            from: inZone(avg: 100),
            currentSpeedKmh: 100,
            limitMph: VehicleType.truck.limit(Self.zone.speedLimits)
        )
        #expect(content.speedLimitMph == 56)
    }

    @Test("Nil limit falls back to the car limit so the projection stays total")
    func nilLimitFallsBackToCar() {
        let content = LiveActivityManager.contentState(
            from: inZone(avg: 100),
            currentSpeedKmh: 100,
            limitMph: nil
        )
        #expect(content.speedLimitMph == 87)
    }

    @Test("Unmeasured projects the road's facts with no verdict anywhere")
    func unmeasuredCarriesNoVerdict() {
        let content = LiveActivityManager.contentState(
            from: ZoneState.Unmeasured(zone: Self.zone, distanceRemaining: 15_159.4),
            currentSpeedKmh: 132.7,
            limitMph: 140
        )
        #expect(content.phase == .unmeasured)
        #expect(content.roadName == "АМ Тракия")
        #expect(content.currentSpeedMph == 82)  // 132.7 km/h
        #expect(content.speedLimitMph == 140)
        #expect(content.zoneTotalM == 19_160)
        #expect(content.distanceRemainingM == 15_159)
        // The whole point of the phase: no average, no over-limit claim, and a
        // neutral tint — the traffic light is a verdict, and an entry we never
        // witnessed earns none.
        #expect(content.avgSpeedMph == nil)
        #expect(content.isOverLimit == false)
        #expect(content.statusColorPacked == zoneColorNeutral)
        #expect(content.statusColorPacked != zoneColorGreen)
        #expect(content.statusColorPacked != zoneColorYellow)
        #expect(content.statusColorPacked != zoneColorRed)
    }

    @Test("Unmeasured resolves the vehicle limit, falls back to car, floors distance at 0")
    func unmeasuredLimitAndDistanceEdges() {
        let truck = LiveActivityManager.contentState(
            from: ZoneState.Unmeasured(zone: Self.zone, distanceRemaining: 1_000),
            currentSpeedKmh: 80,
            limitMph: VehicleType.truck.limit(Self.zone.speedLimits)
        )
        #expect(truck.speedLimitMph == 56)

        // Nil limit falls back to the car limit so the projection stays total,
        // and a negative remainder (projection overshoot past the exit camera)
        // can never render as a negative distance.
        let fallback = LiveActivityManager.contentState(
            from: ZoneState.Unmeasured(zone: Self.zone, distanceRemaining: -5),
            currentSpeedKmh: nil,
            limitMph: nil
        )
        #expect(fallback.speedLimitMph == 87)
        #expect(fallback.currentSpeedMph == nil)
        #expect(fallback.distanceRemainingM == 0)
        #expect(fallback.avgSpeedMph == nil)
    }

    @Test("trackingPlaceholder uses .tracking phase with no zone fields")
    func trackingPlaceholder() {
        let placeholder = LiveActivityManager.trackingPlaceholder()
        #expect(placeholder.phase == .tracking)
        #expect(placeholder.roadName == nil)
        #expect(placeholder.avgSpeedMph == nil)
        #expect(placeholder.currentSpeedMph == nil)
        #expect(placeholder.speedLimitMph == nil)
        #expect(placeholder.zoneTotalM == 0)
    }

    @Test("zoneComplete preserves road, avg, and limit; clears live fields")
    func zoneCompletePreservesRecap() {
        let live = LiveActivityManager.contentState(
            from: inZone(avg: 130, traveled: 10_000, remaining: 9_160),
            currentSpeedKmh: 132,
            limitMph: 140
        )
        let recap = LiveActivityManager.zoneComplete(from: live)
        #expect(recap.phase == .zoneComplete)
        #expect(recap.roadName == "АМ Тракия")
        #expect(recap.avgSpeedMph == 81)  // 130 km/h
        #expect(recap.speedLimitMph == 140)
        #expect(recap.statusColorPacked == live.statusColorPacked)
        // Live-only readings are cleared.
        #expect(recap.currentSpeedMph == nil)
        #expect(recap.distanceRemainingM == 0)
        // Progress shows full bar — distanceTraveled == zoneTotal.
        #expect(recap.distanceTraveledM == recap.zoneTotalM)
    }

    @Test("Nil and non-finite speeds round-trip as nil")
    func nilSpeedsBecomeNil() {
        let content = LiveActivityManager.contentState(
            from: inZone(avg: nil),
            currentSpeedKmh: nil,
            limitMph: 140
        )
        #expect(content.avgSpeedMph == nil)
        #expect(content.currentSpeedMph == nil)

        let infinite = LiveActivityManager.contentState(
            from: inZone(avg: .infinity),
            currentSpeedKmh: .nan,
            limitMph: 140
        )
        #expect(infinite.avgSpeedMph == nil)
        #expect(infinite.currentSpeedMph == nil)
    }

    @Test("Status color: green when avg under and current under")
    func greenStatus() {
        let content = LiveActivityManager.contentState(
            from: inZone(avg: 120, over: false),
            currentSpeedKmh: 130,
            limitMph: 140
        )
        #expect(content.statusColorPacked == zoneColorGreen)
    }

    @Test("Status color: yellow when current speed exceeds limit but avg is fine")
    func yellowStatus() {
        let content = LiveActivityManager.contentState(
            from: inZone(avg: 120, over: false),
            currentSpeedKmh: 145,
            limitMph: 140
        )
        #expect(content.statusColorPacked == zoneColorYellow)
    }

    @Test("Status color: red when running average is over the limit")
    func redStatus() {
        let content = LiveActivityManager.contentState(
            from: inZone(avg: 145, over: true),
            currentSpeedKmh: 100,
            limitMph: 140
        )
        #expect(content.statusColorPacked == zoneColorRed)
        #expect(content.isOverLimit)
    }

    @Test("zoneTotalM is clamped to a positive integer to avoid divide-by-zero")
    func zoneTotalClampedPositive() {
        // Build a degenerate zone with distanceM = 0 to confirm we floor at 1.
        let degenerate = Zone(
            id: "x", road: "X", direction: "east", description: "",
            start: ZoneEndpoint(lat: 0, lng: 0),
            end: ZoneEndpoint(lat: 0, lng: 0),
            distanceM: 0,
            speedLimits: SpeedLimits(car: 90, truck: 90, bus: 90),
            centerline: [],
            source: "test",
            lastVerified: "2026-04-12"
        )
        let state = ZoneState.InZone(
            zone: degenerate,
            entryTime: 0,
            distanceTraveled: 0,
            speedStatus: SpeedStatus(
                avgSpeed: nil,
                maxSpeedForRemainder: 90,
                distanceRemaining: 0,
                timeRemaining: 0,
                isOverLimit: false
            ),
            distanceRemaining: 0
        )
        let content = LiveActivityManager.contentState(from: state, currentSpeedKmh: nil, limitMph: nil)
        #expect(content.zoneTotalM >= 1)
    }
}
#endif
