# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 SrednaBG Contributors
#
# SrednaBG — scrapers

"""Tests for the SrednaUK converter (speedcameramap.uk sections → zones.json)."""

import json

import pytest

from src.geo import haversine_m
from src.uk_sections import (
    MIN_SECTION_M,
    OUTPUT_PATH,
    build_document,
    compass_direction,
    compute_hash,
    decode_polyline,
    road_type,
)


def encode_polyline(points):
    """Reference encoder (Google algorithm) so tests can build sections."""
    out, prev = [], [0, 0]
    for lat, lng in points:
        for i, v in enumerate((round(lat * 1e5), round(lng * 1e5))):
            d = v - prev[i]
            prev[i] = v
            d = ~(d << 1) if d < 0 else d << 1
            while d >= 0x20:
                out.append(chr((0x20 | (d & 0x1F)) + 63))
                d >>= 5
            out.append(chr(d + 63))
    return "".join(out)


def section(sid, scheme, points, limit=50, road="A1", street=None):
    return {"id": sid, "scheme": scheme, "road": road, "street": street,
            "limit": limit, "lengthM": None, "page": None, "g": encode_polyline(points)}


# Due north, ~1.1 km, in Lincolnshire.
NORTH = [[53.00000, -0.50000], [53.00500, -0.50000], [53.01000, -0.50000]]


class TestDecode:
    def test_google_reference_example(self):
        # The worked example from Google's polyline algorithm documentation.
        assert decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@") == [
            [38.5, -120.2], [40.7, -120.95], [43.252, -126.453],
        ]

    def test_round_trips_with_reference_encoder(self):
        assert decode_polyline(encode_polyline(NORTH)) == NORTH

    def test_empty(self):
        assert decode_polyline("") == []


class TestDirection:
    @pytest.mark.parametrize(("end", "expected"), [
        ([53.01, -0.50], "north"), ([52.99, -0.50], "south"),
        ([53.00, -0.48], "east"), ([53.00, -0.52], "west"),
    ])
    def test_cardinal(self, end, expected):
        assert compass_direction([53.0, -0.5], end) == expected

    def test_longitude_is_scaled_by_latitude(self):
        # 0.008° lng at 53°N is ~535 m; 0.006° lat is ~667 m → north wins.
        assert compass_direction([53.0, -0.5], [53.006, -0.492]) == "north"


class TestRoadType:
    @pytest.mark.parametrize(("road", "expected"), [
        ("M4", "motorway"), ("A1M", "road"), ("A1(M)", "road"), ("A38", "road"),
        ("B2032", "road"), (None, "road"),
    ])
    def test_road_type(self, road, expected):
        assert road_type(road) == expected


class TestBuild:
    def doc(self, *sections, updated="2026-09-27"):
        return {"updated": updated, "sections": list(sections)}

    def test_zone_shape(self):
        doc, notes = build_document(self.doc(section(1, "a1-test", NORTH, street="High St")), None)
        assert doc["speed_unit"] == "mph"
        assert doc["version"] == "2026-09-27T00:00:00Z"
        assert "OpenStreetMap" in doc["attribution"]
        (z,) = doc["zones"]
        assert z["id"] == "a1-test-01-north"
        assert z["direction"] == "north"
        assert z["description"] == "A1, High St"
        assert z["speed_limits"] == {"car": 50, "truck": 50, "bus": 50, "motorcycle": None}
        assert z["centerline"][0] == [z["start"]["lat"], z["start"]["lng"]]
        assert z["centerline"][-1] == [z["end"]["lat"], z["end"]["lng"]]
        assert z["distance_m"] == pytest.approx(1112, abs=5)
        assert notes == []

    def test_skips_short_sections(self):
        short = [[53.0, -0.5], [53.0005, -0.5]]  # ~56 m
        doc, notes = build_document(self.doc(section(1, "a1-test", short)), None)
        assert doc["zones"] == []
        assert any(f"shorter than {MIN_SECTION_M} m" in n for n in notes)

    def test_skips_missing_limit_and_outside_uk(self):
        paris = [[48.85, 2.35], [48.86, 2.35]]
        doc, _ = build_document(self.doc(
            section(1, "a1-test", NORTH, limit=None),
            section(2, "fr-test", paris),
        ), None)
        assert doc["zones"] == []

    def test_dedupes_same_direction_copies_but_keeps_opposite_direction(self):
        nudged = [[p[0] + 0.0001, p[1]] for p in NORTH]  # ~11 m off
        reverse = list(reversed(NORTH))
        doc, notes = build_document(self.doc(
            section(1, "a1-test", NORTH),
            section(2, "a1-test", nudged),
            section(3, "a1-test", reverse),
        ), None)
        assert [z["direction"] for z in doc["zones"]] == ["north", "south"]
        assert any("duplicate of a1-test#1" in n for n in notes)

    def test_ids_number_per_scheme(self):
        east = [[53.0, -0.5], [53.0, -0.49]]
        doc, _ = build_document(self.doc(
            section(1, "a1-test", NORTH), section(2, "a1-test", east),
            section(3, "b2-test", [[54.0, -1.0], [54.01, -1.0]], road="B2"),
        ), None)
        assert [z["id"] for z in doc["zones"]] == [
            "a1-test-01-north", "a1-test-02-east", "b2-test-01-north",
        ]

    def test_camera_cross_check_notes_far_endpoints(self):
        cams = {"kinds": ["fixed", "average"], "rows": [[53.0, -0.5, 1, 50]]}
        _, notes = build_document(self.doc(section(1, "a1-test", NORTH)), cams)
        # Start sits on the camera; the end (~1.1 km away) is flagged.
        assert any("end is" in n for n in notes)
        assert not any("start is" in n for n in notes)

    def test_hash_ignores_last_verified(self):
        z = {"id": "x", "last_verified": "2026-01-01"}
        assert compute_hash([z]) == compute_hash([{**z, "last_verified": "2026-02-01"}])


@pytest.fixture(scope="module")
def doc():
    return json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))


class TestCommittedData:
    """The bundled UK catalog both apps ship (backend/data/zones.json)."""

    def test_is_mph_and_attributed(self, doc):
        assert doc["speed_unit"] == "mph"
        assert doc["licence"] == "ODbL-1.0"
        assert "OpenStreetMap" in doc["attribution"]

    def test_hash_matches_content(self, doc):
        assert doc["hash"] == compute_hash(doc["zones"])

    def test_ids_unique(self, doc):
        ids = [z["id"] for z in doc["zones"]]
        assert len(ids) == len(set(ids))

    def test_every_zone_is_usable(self, doc):
        # Mirrors the apps' ZoneSanitizer: a zone failing these is dropped on load.
        for z in doc["zones"]:
            assert len(z["centerline"]) >= 2, z["id"]
            assert z["distance_m"] >= MIN_SECTION_M, z["id"]
            assert all(z["speed_limits"][k] > 0 for k in ("car", "truck", "bus")), z["id"]
            assert z["direction"] in {"north", "south", "east", "west"}, z["id"]

    def test_centerlines_run_start_to_end(self, doc):
        for z in doc["zones"]:
            first, last = z["centerline"][0], z["centerline"][-1]
            assert haversine_m(*first, z["start"]["lat"], z["start"]["lng"]) < 1, z["id"]
            assert haversine_m(*last, z["end"]["lat"], z["end"]["lng"]) < 1, z["id"]
