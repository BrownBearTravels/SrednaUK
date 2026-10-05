// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / app

package com.demosten.srednabg.app

/**
 * Compile-time ship gates. Stay constant across debug and release flavors;
 * flip only in a release that intentionally enables the feature.
 *
 * Mirrors `FeatureFlags` in `ios/Packages/SrednaBGData/Sources/SrednaBGData/QAFlags.swift`.
 */
object FeatureFlags {

    /**
     * Map-sync client paths (`MapSyncWorker`, `MapRepository.syncFromServer`,
     * `MapApi.downloadBundle`) are plumbed but the production backend
     * (`srednabg.com/api/...`) does not yet serve `/api/map/bundle.zip` or
     * populate `map_hash` — the Namecheap scraper cron only emits zones. Stay
     * `false` across debug and release until the backend bundle pipeline is
     * live and the round-trip has been QA'd; otherwise we'd ship untested
     * client code that lights up the moment the backend changes.
     */
    const val IS_MAP_SYNC_ENABLED = false

    /**
     * SrednaUK fork: the upstream zone feed (srednabg.com) only serves Bulgarian
     * zones. While `false` the app never contacts it: the periodic worker is not
     * scheduled (and short-circuits if a stale one fires), and the Settings
     * toggle, "Sync zones now" button and the map's "Try again" are hidden, so
     * the bundled zones.json is the only zone source. Gated at those entry
     * points rather than inside `ZoneRepository.syncFromServer` so the
     * repository stays unit-testable. Flip it only once you host your own feed
     * and point ZONE_API_BASE_URL at it.
     */
    const val IS_ZONE_SYNC_ENABLED = false
}
