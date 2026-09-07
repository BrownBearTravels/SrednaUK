// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / app

package com.demosten.srednabg.app.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.demosten.srednabg.core.SpeedLimits
import com.demosten.srednabg.core.SpeedSample
import com.demosten.srednabg.core.Zone
import com.demosten.srednabg.core.ZoneEndpoint
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

/**
 * A completed average-speed-zone traversal, persisted for the History tab.
 *
 * Fields are **denormalized** on purpose: the zone's road/direction/limit and
 * the driver's speeds are all copied in, so a record survives the source zone
 * being edited, re-numbered, or deleted by a later data sync. The captured
 * speed-over-time series lives in [samplesJson] as a JSON array (mirroring
 * [ZoneEntity.centerlineJson]), downsampled to ≤500 points before storage.
 *
 * The zone's **geometry at the time of the trip** is denormalized too
 * ([description], start/end coordinates, [centerlineJson] — the centerline
 * simplified to 10 m by the core `PolylineSimplify`, ~1 KB), so "Show on map"
 * draws the historic truth without looking the zone up in the live catalog.
 * Zone *names* (`zoneId`) renumber whenever a section is inserted mid-road, so
 * a catalog lookup by name can silently land on a different section. The six
 * geometry columns are nullable: rows written before v3 have none and simply
 * can't be shown on the map ([snapshotZone] returns null).
 */
@Entity(tableName = "zone_traversals")
data class ZoneTraversalEntity(
    @PrimaryKey val id: String,
    val zoneId: String,
    val road: String,
    val roadLatin: String?,
    val direction: String,
    val speedLimitKmh: Int,
    val vehicleType: String,
    val entryTimeMs: Long,
    val exitTimeMs: Long,
    val avgSpeedKmh: Double?,
    val sustainedMinKmh: Double,
    val sustainedMaxKmh: Double,
    val isOverLimit: Boolean,
    val distanceM: Int,
    val samplesJson: String,
    // Geometry snapshot (v3) — null on rows recorded before it existed.
    val description: String? = null,
    val startLat: Double? = null,
    val startLng: Double? = null,
    val endLat: Double? = null,
    val endLng: Double? = null,
    val centerlineJson: String? = null,
)

private val speedSampleListType = object : TypeToken<List<SpeedSample>>() {}.type

/**
 * Serialize a captured series to the JSON array stored in [ZoneTraversalEntity.samplesJson].
 *
 * Casing note: the injected [Gson] is the shared app singleton configured with
 * `FieldNamingPolicy.LOWER_CASE_WITH_UNDERSCORES` (see `AppModule.provideGson`),
 * so keys serialize as `timestamp_ms` / `speed_kmh` (**snake_case**). The iOS
 * port encodes the same [SpeedSample] with `JSONEncoder` defaults
 * (`timestampMs` / `speedKmh`, **camelCase**). Each platform round-trips its own
 * blob, so this is not a runtime bug — but a future cross-platform history
 * import/export must reconcile the casing (the shared `Gson` can't simply be
 * re-cased here without also changing zone-API parsing). Kept intentionally.
 */
fun List<SpeedSample>.toSamplesJson(gson: Gson): String = gson.toJson(this, speedSampleListType)

private val centerlineType = object : TypeToken<List<List<Double>>>() {}.type

/** Serialize a `[lat, lng]` polyline to the JSON stored in [ZoneTraversalEntity.centerlineJson]. */
fun List<List<Double>>.toCenterlineJson(gson: Gson): String = gson.toJson(this, centerlineType)

/**
 * The zone as it was when this trip was recorded, rebuilt from the snapshot
 * columns as a core [Zone] so the map can draw it with the same helpers it uses
 * for catalog zones. Null when the row predates the snapshot or the geometry
 * is unusable (fewer than two centerline points, missing endpoints). The
 * synthetic zone's `id` is the **record** id, never the zone name, so it can't
 * collide with a live catalog zone.
 */
fun ZoneTraversalEntity.snapshotZone(gson: Gson): Zone? {
    val sLat = startLat ?: return null
    val sLng = startLng ?: return null
    val eLat = endLat ?: return null
    val eLng = endLng ?: return null
    val json = centerlineJson?.takeIf { it.isNotBlank() } ?: return null
    val centerline = runCatching { gson.fromJson<List<List<Double>>>(json, centerlineType) }
        .getOrNull()
        ?.filter { it.size >= 2 }
        ?: return null
    if (centerline.size < 2) return null
    return Zone(
        id = id,
        road = road,
        roadLatin = roadLatin,
        direction = direction,
        description = description ?: "",
        start = ZoneEndpoint(lat = sLat, lng = sLng),
        end = ZoneEndpoint(lat = eLat, lng = eLng),
        distanceM = distanceM,
        speedLimits = SpeedLimits(car = speedLimitKmh, truck = speedLimitKmh, bus = speedLimitKmh),
        centerline = centerline,
        source = "history",
        lastVerified = "",
    )
}

/** Parse [ZoneTraversalEntity.samplesJson] back into a [SpeedSample] series (empty on malformed/blank). */
fun ZoneTraversalEntity.speedSamples(gson: Gson): List<SpeedSample> {
    if (samplesJson.isBlank()) return emptyList()
    return runCatching { gson.fromJson<List<SpeedSample>>(samplesJson, speedSampleListType) }
        .getOrNull()
        ?: emptyList()
}
