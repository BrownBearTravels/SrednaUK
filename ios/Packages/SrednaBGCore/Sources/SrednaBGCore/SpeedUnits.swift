// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / core

import Foundation

/// SrednaUK unit convention: zone **limits** are whole mph (as UK signs and data
/// sources publish them), while every **measured** speed — GPS fixes, running
/// averages, max-for-remainder — stays in km/h. The engine converts a limit with
/// `mphToKmh` at the point of comparison, never by rounding to an integer km/h,
/// so "over the limit" agrees exactly with what the mph display shows.
///
/// Kotlin twin: `android/core/.../SpeedUnits.kt`.
public let kmhPerMph = 1.609344

public extension Int {
    /// Exact km/h equivalent of a whole-mph limit.
    var mphToKmh: Double { Double(self) * kmhPerMph }

    /// Nearest whole mph — for converting km/h source data into mph limits.
    var kmhToMphLimit: Int { Int((Double(self) / kmhPerMph).rounded()) }
}

public extension Double {
    /// Display conversion for a measured km/h speed.
    var kmhToMph: Double { self / kmhPerMph }

    /// "Max ahead" in whole mph, rounded **down** so it never advises a speed
    /// that tips the average over the limit.
    var kmhToMphFloor: Int { Int((self / kmhPerMph).rounded(.down)) }
}

private let metresPerMile = 1609.344

/// Remaining distance, e.g. "1.3 mi".
public func formatMiles(_ metres: Double) -> String {
    String(format: "%.1f mi", locale: Locale(identifier: "en_GB"), metres / metresPerMile)
}

public func metresToMiles(_ metres: Double) -> Double { metres / metresPerMile }
