// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGCarPlay

import Foundation
import Testing
@testable import SrednaBGCarPlay
import SrednaBGCore

@Suite("CarPlaySpeedOverlayModel")
struct CarPlaySpeedOverlayModelTests {

    // MARK: - Fixtures

    private static let labels = CarPlayLabels(
        overLimit: "OVER",
        withinLimit: "WITHIN",
        nowSpeedFormat: "Now %@ mph",
        currentSpeedLabel: "current",
        avgSpeedLabel: "avg",
        remaining: "remaining",
        speedLimit: "limit",
        finalAvgSpeedFormat: "final %@ mph",
        zoneCompleteTitle: "COMPLETE",
        trackingOutsideTitle: "OUTSIDE",
        notTrackingTitle: "OFF",
        tapToStartHint: "TAP",
        notMeasuredTitle: "NOT MEASURED"
    )

    private static func fixtureZone() -> Zone {
        Zone(
            id: "zone-1",
            road: "AM Trakia",
            roadLatin: nil,
            direction: "east",
            description: "fixture",
            start: ZoneEndpoint(lat: 42.0, lng: 24.0, kmMarker: nil, settlement: nil, settlementLatin: nil),
            end: ZoneEndpoint(lat: 42.1, lng: 24.1, kmMarker: nil, settlement: nil, settlementLatin: nil),
            distanceM: 10_000,
            // 120/100/110 km/h as whole mph (SpeedUnits.swift).
            speedLimits: SpeedLimits(car: 75, truck: 62, bus: 68, motorcycle: nil),
            centerline: [[42.0, 24.0], [42.1, 24.1]],
            source: "test",
            lastVerified: "2026-04-24"
        )
    }

    private static func overSpeed(status: SpeedStatus) -> Bool { status.isOverLimit }

    // MARK: - notTracking

    @Test("notTrackingBlanksEverythingAndShowsHint")
    func notTrackingBlanksEverythingAndShowsHint() {
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: false,
            state: .outside,
            currentSpeedKmh: nil,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.mode == .notTracking)
        #expect(model.heroSpeedText == "--")
        #expect(model.smallSpeedText == nil)
        #expect(model.limitText == nil)
        #expect(model.distanceText == nil)
        #expect(model.statusLabel == "TAP")
        #expect(model.packedStatusColor == 0)
    }

    // MARK: - outside

    @Test("outsideShowsCurrentSpeedHero")
    func outsideShowsCurrentSpeedHero() {
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .outside,
            currentSpeedKmh: 72.4,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.mode == .outside)
        #expect(model.heroSpeedText == "45")     // 72.4 km/h, rounded mph
        #expect(model.heroSubtitle == "current")
        #expect(model.smallSpeedText == nil)
        #expect(model.limitText == nil)
        #expect(model.distanceText == nil)
        #expect(model.statusLabel == "OUTSIDE")
    }

    @Test("outsideWithNoFixShowsDash")
    func outsideWithNoFixShowsDash() {
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .outside,
            currentSpeedKmh: nil,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.heroSpeedText == "--")
    }

    // MARK: - inZone

    @Test("inZoneWithinLimitShowsGreenStatus")
    func inZoneWithinLimitShowsGreenStatus() {
        let zone = Self.fixtureZone()
        let status = SpeedStatus(
            avgSpeed: 110,
            maxSpeedForRemainder: 130,
            distanceRemaining: 5_000,
            timeRemaining: 150,
            isOverLimit: false
        )
        let inZone = ZoneState.InZone(
            zone: zone,
            entryTime: 0,
            distanceTraveled: 5_000,
            speedStatus: status,
            distanceRemaining: 5_000
        )
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .inZone(inZone),
            currentSpeedKmh: 115,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.mode == .inZone)
        #expect(model.heroSpeedText == "68")  // 110 km/h
        #expect(model.heroSubtitle == "avg")
        #expect(model.smallSpeedText == "71")  // 115 km/h
        #expect(model.smallSubtitle == "current")
        #expect(model.limitText == "75")  // car limit from fixture
        #expect(model.distanceText == "3.1 mi")
        #expect(model.distanceSubtitle == "remaining")
        #expect(model.statusLabel == "WITHIN")
        // green when under limit
        #expect(model.packedStatusColor == zoneColorGreen)
    }

    @Test("inZoneOverLimitShowsRedStatus")
    func inZoneOverLimitShowsRedStatus() {
        let zone = Self.fixtureZone()
        let status = SpeedStatus(
            avgSpeed: 130,
            maxSpeedForRemainder: 100,
            distanceRemaining: 3_000,
            timeRemaining: 90,
            isOverLimit: true
        )
        let inZone = ZoneState.InZone(
            zone: zone,
            entryTime: 0,
            distanceTraveled: 7_000,
            speedStatus: status,
            distanceRemaining: 3_000
        )
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .inZone(inZone),
            currentSpeedKmh: 135,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.statusLabel == "OVER")
        #expect(model.packedStatusColor == zoneColorRed)
        #expect(model.distanceText == "1.9 mi")
    }

    @Test("inZoneUsesVehicleTypeLimit")
    func inZoneUsesVehicleTypeLimit() {
        let zone = Self.fixtureZone()
        let status = SpeedStatus(
            avgSpeed: 90,
            maxSpeedForRemainder: 110,
            distanceRemaining: 2_000,
            timeRemaining: 80,
            isOverLimit: false
        )
        let inZone = ZoneState.InZone(
            zone: zone,
            entryTime: 0,
            distanceTraveled: 8_000,
            speedStatus: status,
            distanceRemaining: 2_000
        )
        let truckModel = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .inZone(inZone),
            currentSpeedKmh: 92,
            vehicleType: .truck,
            labels: Self.labels
        )
        #expect(truckModel.limitText == "62")   // truck limit from fixture
        let busModel = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .inZone(inZone),
            currentSpeedKmh: 92,
            vehicleType: .bus,
            labels: Self.labels
        )
        #expect(busModel.limitText == "68")
    }

    @Test("inZoneWithNilSpeedsRendersDashes")
    func inZoneWithNilSpeedsRendersDashes() {
        let zone = Self.fixtureZone()
        let status = SpeedStatus(
            avgSpeed: nil,
            maxSpeedForRemainder: 120,
            distanceRemaining: 1_000,
            timeRemaining: 60,
            isOverLimit: false
        )
        let inZone = ZoneState.InZone(
            zone: zone,
            entryTime: 0,
            distanceTraveled: 9_000,
            speedStatus: status,
            distanceRemaining: 1_000
        )
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .inZone(inZone),
            currentSpeedKmh: nil,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.heroSpeedText == "--")
        #expect(model.smallSpeedText == "--")
        #expect(model.limitText == "75")
        #expect(model.distanceText == "0.6 mi")
    }

    // MARK: - exiting

    @Test("exitingShowsFinalRecap")
    func exitingShowsFinalRecap() {
        let zone = Self.fixtureZone()
        let exiting = ZoneState.Exiting(zone: zone, finalAvgSpeed: 108.6)
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .exiting(exiting),
            currentSpeedKmh: 90,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.mode == .exiting)
        #expect(model.heroSpeedText == "67")  // 108.6 km/h, rounded mph
        #expect(model.statusLabel == "final 67 mph")
        #expect(model.limitText == nil)
        #expect(model.distanceText == nil)
        #expect(model.smallSpeedText == nil)
    }

    @Test("exitingWithNilFinalSpeedFallsBackToDash")
    func exitingWithNilFinalSpeedFallsBackToDash() {
        let zone = Self.fixtureZone()
        let exiting = ZoneState.Exiting(zone: zone, finalAvgSpeed: nil)
        let model = CarPlaySpeedOverlayModel.from(
            isTracking: true,
            state: .exiting(exiting),
            currentSpeedKmh: nil,
            vehicleType: .car,
            labels: Self.labels
        )
        #expect(model.heroSpeedText == "--")
        #expect(model.statusLabel == "final -- mph")
    }

    // MARK: - formatting

    @Test("formatSpeedHandlesNonFinite")
    func formatSpeedHandlesNonFinite() {
        #expect(CarPlaySpeedOverlayModel.formatSpeed(.nan) == "--")
        #expect(CarPlaySpeedOverlayModel.formatSpeed(.infinity) == "--")
        #expect(CarPlaySpeedOverlayModel.formatSpeed(nil) == "--")
        #expect(CarPlaySpeedOverlayModel.formatSpeed(96.5) == "60")  // 59.96 mph
    }

    @Test("formatDistanceHandlesNegativeAndNonFinite")
    func formatDistanceHandlesNegativeAndNonFinite() {
        #expect(CarPlaySpeedOverlayModel.formatDistance(.nan) == "--")
        #expect(CarPlaySpeedOverlayModel.formatDistance(-5) == "--")
        #expect(CarPlaySpeedOverlayModel.formatDistance(0) == "0.0 mi")
        // 12350 m ≈ 7.674 mi → "7.7 mi".
        #expect(CarPlaySpeedOverlayModel.formatDistance(12_350) == "7.7 mi")
        // 1 mile exactly.
        #expect(CarPlaySpeedOverlayModel.formatDistance(1_609.344) == "1.0 mi")
    }

    @Test("modelEqualityStableAcrossRebuild")
    func modelEqualityStableAcrossRebuild() {
        let a = CarPlaySpeedOverlayModel.from(
            isTracking: true, state: .outside, currentSpeedKmh: 50,
            vehicleType: .car, labels: Self.labels
        )
        let b = CarPlaySpeedOverlayModel.from(
            isTracking: true, state: .outside, currentSpeedKmh: 50,
            vehicleType: .car, labels: Self.labels
        )
        #expect(a == b)
    }
}
