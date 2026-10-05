// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGData

import Foundation
import SrednaBGCore

/// Mirrors `VersionResponse` in `android/.../data/remote/ZoneApi.kt`. The
/// backend emits snake_case; we decode with `.convertFromSnakeCase`.
public struct VersionResponse: Sendable, Codable, Equatable {
    public let version: String
    public let hash: String
    public let minAppVersion: String?
    public let zoneCount: Int?
    public let mapHash: String?
    /// Set by the backend when this build's data feed is no longer maintained.
    /// Any non-zero value means "tell the user to update"; absent is the normal,
    /// supported state. Read through `isFeedUnsupported` — the field is
    /// deliberately an `Int?` so a future `true` decodes as readily as `1`.
    public let unsupported: Int?

    /// Whether this feed has been retired and stopped receiving fresh data.
    public var isFeedUnsupported: Bool { (unsupported ?? 0) != 0 }

    public init(
        version: String,
        hash: String,
        minAppVersion: String? = nil,
        zoneCount: Int? = nil,
        mapHash: String? = nil,
        unsupported: Int? = nil
    ) {
        self.version = version
        self.hash = hash
        self.minAppVersion = minAppVersion
        self.zoneCount = zoneCount
        self.mapHash = mapHash
        self.unsupported = unsupported
    }
}

/// Mirrors `ZonesResponse` in `android/.../data/remote/ZoneApi.kt`. The
/// `zones` array is the same wire shape as `core.Zone` / Swift `Zone`.
public struct ZonesResponse: Sendable, Codable, Equatable {
    public let version: String
    public let hash: String
    public let zones: [Zone]
    /// SrednaUK: unit of every `speed_limits` value in `zones` — `"mph"` for a
    /// UK feed. Absent (the upstream Bulgarian feed) means km/h.
    public let speedUnit: String?

    public static let speedUnitMph = "mph"

    public init(version: String, hash: String, zones: [Zone], speedUnit: String? = nil) {
        self.version = version
        self.hash = hash
        self.zones = zones
        self.speedUnit = speedUnit
    }

    /// `zones` with limits in whole mph, the unit the app runs on
    /// (SpeedUnits.swift). A km/h feed converts each limit to the nearest mph;
    /// a 0 (missing) limit stays 0 so ZoneSanitizer still sees it as missing.
    /// Kotlin twin: `ZonesResponse.zonesInMph`.
    public var zonesInMph: [Zone] {
        if speedUnit?.lowercased() == Self.speedUnitMph { return zones }
        return zones.map { $0.withSpeedLimits($0.speedLimits.kmhToMph) }
    }
}
