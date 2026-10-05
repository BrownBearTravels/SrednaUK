# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 SrednaBG Contributors
#
# SrednaBG — qa

"""Shared helpers for the edge-scenario family.

These scenarios construct DrivePlans with custom shapes (stops, gaps,
direction reversals) rather than going through the bulk YAML loader.
"""

from __future__ import annotations

import time
from typing import Any

from ... import settings as settings_mod
from ... import zone_source
from ...assertions import AssertionFailure, expect_crash_free
from ...drive import DrivePlan, parse_gpx
from ...events import Event
from ...runner import RunContext
from ..bulk_loader import _ensure_gpx, BulkScenarioSpec

# The harness's default zone — SrednaUK: A47 Acle Straight, westbound. An
# anchor, not an id: see qa/fixtures/zone_anchors.yaml for why. (Upstream
# used АМ Тракия; scenarios tuned to its 19 km length may need re-tuning.)
DEFAULT_ZONE = "a47-acle-straight-west"
# For scenarios that assert on the approach and the entry: a long zone whose
# entry camera is shared with no other zone, so the lead-in is truly Outside.
ISOLATED_ENTRY_ZONE = "a47-acle-straight-west"


def resolve_zone(anchor: str) -> str:
    """Today's id for the stretch of road `anchor` names, in the catalog under
    test. Call it from `build()`, never at import time — the nightly switches
    catalogs after the scenario modules may already have been imported."""
    return zone_source.resolve(anchor)


def load_zone(zone_id: str) -> dict[str, Any]:
    zone = zone_source.zones_by_id().get(zone_id)
    if zone is None:
        raise ValueError(f"zone not found: {zone_id}")
    return zone


def base_plan(zone_id: str, *, speed_kmh: float = 130, approach_km: float = 2,
              exit_km: float = 1, hz: float = 1.0) -> DrivePlan:
    """Generate or reuse a baseline GPX for the given zone, return the
    parsed DrivePlan (uncompressed)."""
    spec = BulkScenarioSpec(
        name=f"{zone_id}-edge", zone_id=zone_id, speed_kmh=speed_kmh,
        approach_km=approach_km, exit_km=exit_km, hz=hz,
    )
    gpx = _ensure_gpx(spec)
    return parse_gpx(gpx)


def scenario_setup(ctx: RunContext, *, settings_id: str = "S1") -> None:
    from ... import device as device_mod
    # Foreground the app before issuing start-tracking. On Android this
    # satisfies the background-start restriction; on iOS it ensures the
    # CoreLocation pipeline is alive and Live Activities can be created.
    device_mod.current().start_main()
    time.sleep(2.0)
    combo = settings_mod.combo_by_id(settings_id)
    combo.apply(ctx.obs)
    settings_mod.start_tracking()
    time.sleep(2.5)
    ctx.obs.clear()


def scenario_teardown(ctx: RunContext) -> None:
    settings_mod.stop_tracking()
    expect_crash_free(ctx.obs)


def assert_signal_observed(
    ctx: RunContext, event_type: type[Event], *, since: int, label: str
) -> None:
    """Fail loudly if no `event_type` events were parsed since the `since`
    snapshot of `obs.type_counts[event_type.__name__]`.

    Anti-vacuous guard for `expect_never`-style assertions: if the underlying
    diagnostic log line isn't emitted on the running platform, `expect_never`
    drains an empty queue and returns green without testing anything. Snapshot
    the count before the observation window, then call this before the
    `expect_never` so an absent signal is a hard failure instead of a false
    pass. `type_counts` is incremented by the observer thread (survives
    `clear()`); the delta is therefore scenario-scoped even though the counter
    accumulates suite-wide."""
    seen = ctx.obs.type_counts[event_type.__name__] - since
    if seen <= 0:
        raise AssertionFailure(
            f"no {event_type.__name__} events observed during {label} — the "
            f"diagnostic log line is missing on this platform, so the following "
            f"assertion would pass vacuously",
            ctx.obs,
        )
