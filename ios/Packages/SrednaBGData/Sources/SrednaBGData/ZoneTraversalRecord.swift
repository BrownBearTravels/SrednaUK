// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGData

import Foundation
import SwiftData
import SrednaBGCore

/// A completed average-speed-zone traversal, persisted for the History tab.
///
/// Fields are **denormalized** on purpose: the zone's road / direction / limit
/// and the driver's speeds are all copied in, so a record survives the source
/// zone being edited, re-numbered, or deleted by a later data sync. The captured
/// speed-over-time series lives in `samples` as encoded JSON (`[SpeedSample]`),
/// downsampled to ≤500 points before storage.
///
/// The zone's **geometry at the time of the trip** is denormalized too
/// (`zoneDescription`, start/end coordinates, `centerline` — simplified to 10 m
/// by the core `PolylineSimplify`, ~1 KB), so "Show on map" draws the historic
/// truth without looking the zone up in the live catalog. Zone *names*
/// (`zoneId`) renumber whenever a section is inserted mid-road, so a catalog
/// lookup by name can silently land on a different section. The geometry
/// properties are optional: records written before they existed have none and
/// simply can't be shown on the map (`snapshotZone` is nil). Optional additions
/// are a SwiftData lightweight migration — no versioned schema needed.
///
/// Mirrors Android's `ZoneTraversalEntity` (Room). SwiftData rather than the
/// JSON-file `ZoneStore` because history is append-heavy, date-queried, growing,
/// and carries a per-record blob — the shape SwiftData fits.
@Model
public final class ZoneTraversalRecord {
    /// Stable identity. Uses the exit timestamp + zone id so a re-inserted
    /// identical record (unexpected) collapses rather than duplicating.
    @Attribute(.unique) public var id: String
    public var zoneId: String
    public var road: String
    public var roadLatin: String?
    public var direction: String
    public var speedLimitKmh: Int
    public var vehicleType: String
    public var entryTimeMs: Int64
    public var exitTimeMs: Int64
    public var avgSpeedKmh: Double?
    public var sustainedMinKmh: Double
    public var sustainedMaxKmh: Double
    public var isOverLimit: Bool
    public var distanceM: Int
    /// JSON-encoded `[SpeedSample]` (downsampled). Decoded via `speedSamples`.
    public var samples: Data
    // Geometry snapshot — nil on records written before it existed.
    public var zoneDescription: String?
    public var startLat: Double?
    public var startLng: Double?
    public var endLat: Double?
    public var endLng: Double?
    /// JSON-encoded `[[Double]]` (`[lat, lng]` pairs, simplified). Decoded via `snapshotZone`.
    public var centerline: Data?

    public init(
        id: String,
        zoneId: String,
        road: String,
        roadLatin: String?,
        direction: String,
        speedLimitKmh: Int,
        vehicleType: String,
        entryTimeMs: Int64,
        exitTimeMs: Int64,
        avgSpeedKmh: Double?,
        sustainedMinKmh: Double,
        sustainedMaxKmh: Double,
        isOverLimit: Bool,
        distanceM: Int,
        samples: Data,
        zoneDescription: String? = nil,
        startLat: Double? = nil,
        startLng: Double? = nil,
        endLat: Double? = nil,
        endLng: Double? = nil,
        centerline: Data? = nil
    ) {
        self.id = id
        self.zoneId = zoneId
        self.road = road
        self.roadLatin = roadLatin
        self.direction = direction
        self.speedLimitKmh = speedLimitKmh
        self.vehicleType = vehicleType
        self.entryTimeMs = entryTimeMs
        self.exitTimeMs = exitTimeMs
        self.avgSpeedKmh = avgSpeedKmh
        self.sustainedMinKmh = sustainedMinKmh
        self.sustainedMaxKmh = sustainedMaxKmh
        self.isOverLimit = isOverLimit
        self.distanceM = distanceM
        self.samples = samples
        self.zoneDescription = zoneDescription
        self.startLat = startLat
        self.startLng = startLng
        self.endLat = endLat
        self.endLng = endLng
        self.centerline = centerline
    }
}

public extension ZoneTraversalRecord {
    /// Decode the stored speed-over-time series (empty on malformed/blank).
    var speedSamples: [SpeedSample] {
        guard !samples.isEmpty else { return [] }
        return (try? JSONDecoder().decode([SpeedSample].self, from: samples)) ?? []
    }

    /// Encode a captured series into the `samples` column payload.
    ///
    /// Casing note: `JSONEncoder` defaults produce **camelCase** keys
    /// (`timestampMs` / `speedKmh`). Android serializes the same `SpeedSample`
    /// through its shared `Gson` (`LOWER_CASE_WITH_UNDERSCORES`), yielding
    /// **snake_case** (`timestamp_ms` / `speed_kmh`). Each platform round-trips
    /// its own blob, so this is not a runtime bug — but a future cross-platform
    /// history import/export must reconcile the casing. Kept intentionally.
    static func encodeSamples(_ series: [SpeedSample]) -> Data {
        (try? JSONEncoder().encode(series)) ?? Data()
    }

    /// Encode a `[lat, lng]` polyline into the `centerline` payload.
    static func encodeCenterline(_ points: [[Double]]) -> Data {
        (try? JSONEncoder().encode(points)) ?? Data()
    }

    /// The zone as it was when this trip was recorded, rebuilt from the
    /// snapshot properties as a core `Zone` so the map can draw it with the
    /// same helpers it uses for catalog zones. Nil when the record predates the
    /// snapshot or the geometry is unusable (fewer than two centerline points,
    /// missing endpoints). The synthetic zone's `id` is the **record** id, never
    /// the zone name, so it can't collide with a live catalog zone.
    var snapshotZone: Zone? {
        guard let startLat, let startLng, let endLat, let endLng,
              let data = centerline, !data.isEmpty,
              let decoded = try? JSONDecoder().decode([[Double]].self, from: data)
        else { return nil }
        let points = decoded.filter { $0.count >= 2 }
        guard points.count >= 2 else { return nil }
        return Zone(
            id: id,
            road: road,
            roadLatin: roadLatin,
            direction: direction,
            description: zoneDescription ?? "",
            start: ZoneEndpoint(lat: startLat, lng: startLng),
            end: ZoneEndpoint(lat: endLat, lng: endLng),
            distanceM: distanceM,
            speedLimits: SpeedLimits(car: speedLimitKmh, truck: speedLimitKmh, bus: speedLimitKmh, motorcycle: nil),
            centerline: points,
            source: "history",
            lastVerified: ""
        )
    }
}
