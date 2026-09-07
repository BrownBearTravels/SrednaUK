# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 SrednaBG Contributors
#
# SrednaBG — qa

"""History detail's "Show on map" action must gate on tracking.

The button (testTag `history-show-on-map`, a TopAppBar action on the History
detail screen) draws the record's own geometry snapshot on the Map tab — it
never consults the live catalog, so a renumbered zone name can't disable or
misplace it. Two features must never drive the map at once, so it has to be:

  1. absent for a record without a geometry snapshot (a row written before
     the snapshot existed — seeded with `--es legacy N`): nothing to show, so
     no button rather than a greyed-out one,
  2. enabled while tracking is off for a record with its snapshot (the seeder
     stores one for every real catalog zone), and
  3. disabled the moment tracking starts (`LocationTrackingService` also
     clears any active highlight via `MapHighlightStore` on start).

Mechanism (Android-only, like the rest of the ui suite — asserts through the
uiautomator accessibility tree; iOS has no analog here):
  1. `SEED_HISTORY legacy=<all>` fills the DB with snapshot-less rows;
     History tab → first row → detail; assert `history-show-on-map` is
     absent from the tree.
  2. `SEED_HISTORY` (normal) refills with snapshot rows; same navigation;
     assert enabled="true".
  3. `START_TRACKING`, re-dump, assert enabled="false".

Teardown stops tracking so later scenarios/suites are unaffected.
"""

from __future__ import annotations

import time

from ... import adb
from ... import device as device_mod
from ... import uiauto
from ...assertions import AssertionFailure, expect_crash_free
from ...runner import RunContext, Scenario, step_lambda
from ...ui import UiRecorder

ACTION_SEED_HISTORY = "com.demosten.srednabg.debug.SEED_HISTORY"
SEED_COUNT = 12
BUTTON_RESOURCE_ID = "history-show-on-map"
ROW_RESOURCE_ID = "history-row"
POLL_TIMEOUT_S = 20.0


def _await_button(*, enabled: str) -> None:
    """Poll the accessibility tree until the button reports the wanted state."""
    deadline = time.monotonic() + POLL_TIMEOUT_S
    last_seen: str | None = None
    while time.monotonic() < deadline:
        node = uiauto.find_by_resource_id(uiauto.dump_ui(), BUTTON_RESOURCE_ID)
        if node is not None:
            last_seen = node.attrib.get("enabled")
            if last_seen == enabled:
                return
        time.sleep(1.0)
    if last_seen is None:
        raise AssertionFailure(
            f"'{BUTTON_RESOURCE_ID}' never appeared — is the History detail "
            "screen open and the action present in the TopAppBar?")
    raise AssertionFailure(
        f"'{BUTTON_RESOURCE_ID}' stayed enabled={last_seen!r}, wanted {enabled!r}")


def _await_button_absent() -> None:
    """The action must not be in the tree at all once the detail has rendered."""
    deadline = time.monotonic() + POLL_TIMEOUT_S
    while time.monotonic() < deadline:
        tree = uiauto.dump_ui()
        # The detail is up when its back-navigation icon is (the button, when
        # present, renders in the same TopAppBar composition pass).
        if uiauto.find_by_resource_id(tree, ROW_RESOURCE_ID) is None:
            if uiauto.find_by_resource_id(tree, BUTTON_RESOURCE_ID) is None:
                return
            raise AssertionFailure(
                f"'{BUTTON_RESOURCE_ID}' is present on a record without a "
                "geometry snapshot — it must be hidden, not disabled")
        time.sleep(1.0)
    raise AssertionFailure("History detail never opened")


def build() -> Scenario:
    def open_detail(ctx: RunContext, *, legacy: int) -> None:
        d = device_mod.current()
        d.grant_runtime_permissions()
        # A leftover tracking session from an earlier scenario would flip the
        # gate under test; make the baseline deterministic.
        d.stop_tracking()
        d.start_main()
        time.sleep(2.0)
        adb.broadcast(
            ACTION_SEED_HISTORY, adb.DEBUG_CONTROL_RECEIVER,
            {"count": str(SEED_COUNT), "legacy": str(legacy)})
        time.sleep(1.5)
        uiauto.tap_node(uiauto.dump_ui(), "tab-history", "History tab")
        time.sleep(1.5)
        # Rows carry the `history-row` test tag (matching by display text broke
        # when the translatable caption was reworded); the first tagged node is
        # the newest record's row, so tapping it opens that record's detail.
        # Poll a little — the seeded rows land via a Room Flow emission.
        deadline = time.monotonic() + 10.0
        row = None
        while row is None and time.monotonic() < deadline:
            row = uiauto.find_by_resource_id(uiauto.dump_ui(), ROW_RESOURCE_ID)
            if row is None:
                time.sleep(1.0)
        if row is None:
            raise AssertionFailure("no history rows visible after SEED_HISTORY")
        x, y = uiauto.bounds_center(row)
        adb.shell(f"input tap {x} {y}")
        time.sleep(1.5)

    def assert_hidden_without_snapshot(ctx: RunContext) -> None:
        # Every seeded row is pre-snapshot: the button must be absent, whatever
        # the live catalog contains (it is never consulted).
        open_detail(ctx, legacy=SEED_COUNT)
        _await_button_absent()
        UiRecorder(ctx.report_dir).screenshot("history_show_on_map_no_snapshot")
        device_mod.current().force_stop()

    def assert_enabled_when_idle(ctx: RunContext) -> None:
        open_detail(ctx, legacy=0)
        _await_button(enabled="true")
        UiRecorder(ctx.report_dir).screenshot("history_show_on_map_enabled")

    def assert_disabled_while_tracking(ctx: RunContext) -> None:
        device_mod.current().start_tracking()
        _await_button(enabled="false")
        UiRecorder(ctx.report_dir).screenshot("history_show_on_map_disabled")

    def teardown(ctx: RunContext) -> None:
        d = device_mod.current()
        d.stop_tracking()
        d.force_stop()
        expect_crash_free(ctx.obs)

    return Scenario(
        name="ui.history_show_on_map",
        steps=[
            step_lambda("assert_hidden_without_snapshot", assert_hidden_without_snapshot),
            step_lambda("assert_enabled_when_idle", assert_enabled_when_idle),
            step_lambda("assert_disabled_while_tracking", assert_disabled_while_tracking),
        ],
        teardown=teardown,
        timeout_s=120,
    )
