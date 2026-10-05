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
     * SrednaUK fork: the original app downloads zone updates from srednabg.com,
     * which only serves Bulgarian zones. Leave this `false` so a UK build never
     * replaces its bundled UK zones.json with Bulgarian data. Flip it only if
     * you host your own zone feed and point ZONE_API_BASE_URL at it.
     */
    const val IS_ZONE_SYNC_ENABLED = false
}
