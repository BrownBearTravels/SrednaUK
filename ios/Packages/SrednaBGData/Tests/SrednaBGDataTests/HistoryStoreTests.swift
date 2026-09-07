// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGData

import Foundation
import Testing
@testable import SrednaBGData
import SrednaBGCore

@MainActor
@Suite("HistoryStore")
struct HistoryStoreTests {

    private func record(
        id: String,
        zoneId: String = "trakiya-01-east",
        exitTimeMs: Int64,
        avg: Double? = 118.0,
        over: Bool = false
    ) -> ZoneTraversalRecord {
        ZoneTraversalRecord(
            id: id,
            zoneId: zoneId,
            road: "АМ Тракия",
            roadLatin: "Trakiya",
            direction: "east",
            speedLimitKmh: 140,
            vehicleType: "car",
            entryTimeMs: exitTimeMs - 60_000,
            exitTimeMs: exitTimeMs,
            avgSpeedKmh: avg,
            sustainedMinKmh: 90,
            sustainedMaxKmh: 130,
            isOverLimit: over,
            distanceM: 19_000,
            samples: ZoneTraversalRecord.encodeSamples([
                SpeedSample(timestampMs: exitTimeMs - 60_000, speedKmh: 100),
                SpeedSample(timestampMs: exitTimeMs, speedKmh: 120)
            ])
        )
    }

    @Test func geometrySnapshotRoundTripsAndIsKeyedByRecordId() throws {
        let store = try HistoryStore.inMemory()
        let centerline: [[Double]] = [[42.55, 23.7], [42.5, 23.8], [42.43, 23.86]]
        let rec = record(id: "a", exitTimeMs: 1_000)
        rec.zoneDescription = "Вакарел – Ихтиман"
        rec.startLat = 42.55
        rec.startLng = 23.7
        rec.endLat = 42.43
        rec.endLng = 23.86
        rec.centerline = ZoneTraversalRecord.encodeCenterline(centerline)
        store.insert(rec)

        let zone = try #require(store.fetchById("a")?.snapshotZone)
        // Keyed by the RECORD id — never the zone name, which a later catalog
        // can reassign to another section.
        #expect(zone.id == "a")
        #expect(zone.description == "Вакарел – Ихтиман")
        #expect(zone.start.lat == 42.55)
        #expect(zone.end.lng == 23.86)
        #expect(zone.centerline == centerline)
        #expect(zone.speedLimits.car == 140)
        #expect(zone.source == "history")
    }

    @Test func recordsWithoutASnapshotHaveNoZone() throws {
        // Pre-snapshot records, and unusable geometry, both yield nil.
        #expect(record(id: "legacy", exitTimeMs: 1_000).snapshotZone == nil)
        let short = record(id: "short", exitTimeMs: 1_000)
        short.startLat = 42.0
        short.startLng = 23.0
        short.endLat = 42.1
        short.endLng = 23.1
        short.centerline = ZoneTraversalRecord.encodeCenterline([[42.0, 23.0]])
        #expect(short.snapshotZone == nil)
        short.centerline = Data("{broken".utf8)
        #expect(short.snapshotZone == nil)
        short.centerline = ZoneTraversalRecord.encodeCenterline([[42.0, 23.0], [42.1, 23.1]])
        short.endLat = nil
        #expect(short.snapshotZone == nil)
        short.endLat = 42.1
        #expect(short.snapshotZone != nil)
    }

    @Test func insertAndFetchAllSortsByExitDescending() throws {
        let store = try HistoryStore.inMemory()
        store.insert(record(id: "a", exitTimeMs: 1_000))
        store.insert(record(id: "b", exitTimeMs: 3_000))
        store.insert(record(id: "c", exitTimeMs: 2_000))

        let all = store.fetchAll()
        #expect(all.map(\.id) == ["b", "c", "a"])
        #expect(store.count() == 3)
        #expect(store.fetchLatest()?.id == "b")
        #expect(store.fetchById("c")?.exitTimeMs == 2_000)
    }

    @Test func emptyStoreReportsNoLatest() throws {
        let store = try HistoryStore.inMemory()
        #expect(store.count() == 0)
        #expect(store.fetchLatest() == nil)
    }

    @Test func pruneDropsOnlyRecordsOlderThanCutoff() throws {
        let store = try HistoryStore.inMemory()
        store.insert(record(id: "old", exitTimeMs: 1_000))
        store.insert(record(id: "new", exitTimeMs: 10_000))

        store.prune(olderThanMs: 5_000)
        #expect(store.fetchAll().map(\.id) == ["new"])
    }

    @Test func applyRetentionNonePurgesEverything() throws {
        let store = try HistoryStore.inMemory()
        store.insert(record(id: "a", exitTimeMs: 1_000))
        store.insert(record(id: "b", exitTimeMs: 2_000))

        store.applyRetention(.none, nowMs: 10_000)
        #expect(store.count() == 0)
    }

    @Test func applyRetentionKeepsRecordsInsideWindow() throws {
        let store = try HistoryStore.inMemory()
        let now: Int64 = 200 * 24 * 60 * 60 * 1000
        // Well inside 3 months (90 days), and well outside it.
        store.insert(record(id: "recent", exitTimeMs: now - 10 * 24 * 60 * 60 * 1000))
        store.insert(record(id: "stale", exitTimeMs: now - 100 * 24 * 60 * 60 * 1000))

        store.applyRetention(.threeMonths, nowMs: now)
        #expect(store.fetchAll().map(\.id) == ["recent"])
    }

    @Test func encodedSamplesRoundTrip() throws {
        let store = try HistoryStore.inMemory()
        store.insert(record(id: "a", exitTimeMs: 1_000))
        let fetched = try #require(store.fetchById("a"))
        #expect(fetched.speedSamples.count == 2)
        #expect(fetched.speedSamples.first?.speedKmh == 100)
    }
}
