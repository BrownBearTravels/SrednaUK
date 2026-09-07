// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / app

package com.demosten.srednabg.app.data

import com.demosten.srednabg.core.Zone
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * A History-detail "Show on map" request: draw [zone] — the record's own
 * geometry snapshot (see `ZoneTraversalEntity.snapshotZone`), NOT a catalog
 * zone — on the Map tab in the trip's verdict color. Carrying the geometry
 * itself is what makes the request independent of the live catalog: zone
 * names renumber on mid-road insertions, so a lookup by name could paint a
 * different section. [requestId] is monotonic so the map can key its one-shot
 * camera fit on it (revisiting the Map tab doesn't re-fit).
 */
data class MapHighlight(
    val zone: Zone,
    val isOverLimit: Boolean,
    val requestId: Long,
)

/**
 * Cross-tab holder for the map highlight request. In-memory only (process
 * death resets it — same semantics as the map camera session). The map honors
 * it only while tracking is off; [LocationTrackingService] clears it whenever
 * tracking starts so the live-tracking rendering never competes with it.
 */
@Singleton
class MapHighlightStore @Inject constructor() {

    private val _highlight = MutableStateFlow<MapHighlight?>(null)
    val highlight: StateFlow<MapHighlight?> = _highlight.asStateFlow()

    private var nextRequestId = 0L

    fun request(zone: Zone, isOverLimit: Boolean) {
        _highlight.value = MapHighlight(zone, isOverLimit, ++nextRequestId)
    }

    fun clear() {
        _highlight.value = null
    }
}
