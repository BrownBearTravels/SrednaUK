// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — ios / SrednaBGCore

import Foundation

public enum MapThemeMode: String, Sendable, CaseIterable, Codable {
    case auto
    case light
    case dark
}

public enum MapTheme: String, Sendable, CaseIterable, Codable {
    case light
    case dark
}

/// Picks the map theme to render given the user's preference, the user's
/// current GPS position (used as the observer location for sun-altitude in
/// `.auto`), and the current UTC instant.
///
/// `.auto` uses civil-twilight as the day/night gate (solar altitude > -6° →
/// `.light`). This matches Google Maps / Waze / Apple Maps and avoids
/// flipping exactly at the visible horizon, which would feel premature
/// while the sky is still bright.
///
/// If no GPS fix is available yet, `.auto` falls back to central England
/// (SrednaUK). It only bridges the moments before the first fix, so the error
/// toward the edges of Great Britain (roughly half an hour of sun time) is an
/// acceptable stopgap.
///
/// Hysteresis (e.g. 10-min debounce around the boundary) belongs in the
/// caller, not the resolver — the resolver stays pure so it can be unit-
/// tested with deterministic inputs.
public enum MapThemeResolver {

    public static let fallbackLat: Double = 52.5
    public static let fallbackLng: Double = -1.9
    public static let civilTwilightAltitudeDeg: Double = -6.0

    public static func resolve(
        mode: MapThemeMode,
        position: GpsPoint?,
        now: Date
    ) -> MapTheme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .auto:
            let lat = position?.lat ?? fallbackLat
            let lng = position?.lng ?? fallbackLng
            let altitudeDeg = solarAltitudeDegrees(lat: lat, lng: lng, now: now)
            return altitudeDeg > civilTwilightAltitudeDeg ? .light : .dark
        }
    }

    /// Solar altitude (degrees) at the given location and UTC instant. NOAA
    /// low-precision formula (Astronomical Algorithms §25, Meeus): accurate
    /// to a few arc-minutes, far better than the ±6° civil-twilight margin
    /// we gate on. Treats UTC ≈ TT (the seconds-scale drift moves the sun
    /// <0.04°, well below tolerance).
    public static func solarAltitudeDegrees(lat: Double, lng: Double, now: Date) -> Double {
        let daysSinceJ2000 = (now.timeIntervalSince1970 - j2000Epoch) / secondsPerDay

        let meanLongDeg = wrap360(280.460 + 0.9856474 * daysSinceJ2000)
        let meanAnomDeg = wrap360(357.528 + 0.9856003 * daysSinceJ2000)
        let gRad = meanAnomDeg * degToRad
        let eclipticLongDeg = meanLongDeg + 1.915 * sin(gRad) + 0.020 * sin(2.0 * gRad)
        let obliquityDeg = 23.439 - 0.0000004 * daysSinceJ2000

        let lambdaRad = eclipticLongDeg * degToRad
        let epsilonRad = obliquityDeg * degToRad
        let sinLambda = sin(lambdaRad)
        let cosLambda = cos(lambdaRad)
        let sinEps = sin(epsilonRad)
        let cosEps = cos(epsilonRad)

        let declRad = asin(sinEps * sinLambda)
        let raRad = atan2(cosEps * sinLambda, cosLambda)
        let raDeg = wrap360(raRad * radToDeg)

        let gmstDeg = wrap360(280.46061837 + 360.98564736629 * daysSinceJ2000)
        let lstDeg = wrap360(gmstDeg + lng)
        let hourAngleRad = wrap180(lstDeg - raDeg) * degToRad

        let latRad = lat * degToRad
        let sinAlt = sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(hourAngleRad)
        return asin(min(max(sinAlt, -1.0), 1.0)) * radToDeg
    }

    private static let j2000Epoch: TimeInterval = 946_728_000  // 2000-01-01 12:00:00Z, seconds since 1970
    private static let secondsPerDay: Double = 86_400
    private static let degToRad: Double = .pi / 180.0
    private static let radToDeg: Double = 180.0 / .pi

    private static func wrap360(_ deg: Double) -> Double {
        let mod = deg.truncatingRemainder(dividingBy: 360.0)
        return mod < 0 ? mod + 360.0 : mod
    }

    private static func wrap180(_ deg: Double) -> Double {
        var x = wrap360(deg)
        if x > 180.0 { x -= 360.0 }
        return x
    }
}
