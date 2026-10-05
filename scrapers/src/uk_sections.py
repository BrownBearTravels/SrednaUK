# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 SrednaBG Contributors
#
# SrednaBG — scrapers

"""SrednaUK: build the bundled zones.json from speedcameramap.uk's OSM export.

speedcameramap.uk rebuilds two files monthly from the OpenStreetMap Geofabrik
extract (https://speedcameramap.uk/data-sources/):

- ``sections.json`` — one entry per *directional* average-speed section from
  OSM ``enforcement=average_speed`` relations, with the road stretch as a
  Google encoded polyline (precision 5) and the posted limit in **mph**.
- ``cameras.json`` — every camera point; its ``average`` kind is used here
  only to cross-check where each section starts and ends.

Data © OpenStreetMap contributors, ODbL 1.0. The generated zones.json is a
derived database and stays under ODbL — see ``backend/data/LICENSE-DATA.md``.

This is deliberately separate from the Bulgarian pipeline (``output.py``):
that one's schema, validator and publish guard are Bulgaria-specific
(bounding box, Cyrillic transliteration, BG TOLL authority rules).

Usage (from ``scrapers/``)::

    python -m src.uk_sections            # download, fall back to the snapshot
    python -m src.uk_sections --offline  # rebuild from the committed snapshot

Each successful download refreshes the snapshot in ``data/uk/`` so the next
offline or failed-download run still has the latest data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import math
import re
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from src.geo import haversine_m, polyline_length_m

logger = logging.getLogger("uk_sections")

BASE_URL = "https://speedcameramap.uk/data"
SCRAPERS_DIR = Path(__file__).resolve().parent.parent
SNAPSHOT_DIR = SCRAPERS_DIR / "data" / "uk"
OUTPUT_PATH = SCRAPERS_DIR.parent / "backend" / "data" / "zones.json"

ATTRIBUTION = (
    "Average speed sections © OpenStreetMap contributors (ODbL 1.0), "
    "via speedcameramap.uk"
)
SOURCE = "osm-speedcameramap"

# Below this the engine cannot meaningfully measure a traversal: entry is only
# confirmed after min(300 m, 25%) of travel and the start must be witnessed
# within 200 m (ZoneDetector). Such sections are logged and skipped.
MIN_SECTION_M = 200

# Two same-direction sections whose endpoints both lie within this distance
# and whose lengths agree within DUP_LENGTH_RATIO are the same stretch mapped
# twice (OSM often carries one relation per camera pair *and* per scheme).
DUP_ENDPOINT_M = 50
DUP_LENGTH_RATIO = 0.05

# A section end further than this from any average-speed camera is still kept
# (the relation's road stretch can extend past the camera) but is logged.
CAMERA_CHECK_M = 150

# Great Britain + Northern Ireland, generously. Guards against a decoding bug
# or a bad upstream row putting a zone somewhere absurd.
UK_LAT = (49.8, 61.0)
UK_LNG = (-8.7, 2.0)


def fetch_json(name: str, offline: bool) -> dict:
    """Download ``name`` and refresh its snapshot, or fall back to the snapshot."""
    snapshot = SNAPSHOT_DIR / name
    if not offline:
        url = f"{BASE_URL}/{name}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "SrednaUK-zone-import"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read()
            data = json.loads(body)
            SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
            snapshot.write_bytes(body)
            logger.info("downloaded %s (%d bytes)", url, len(body))
            return data
        except (OSError, ValueError) as e:
            logger.warning("download of %s failed (%s); using snapshot", url, e)
    if not snapshot.exists():
        raise FileNotFoundError(f"no snapshot at {snapshot}")
    return json.loads(snapshot.read_text(encoding="utf-8"))


def decode_polyline(encoded: str) -> list[list[float]]:
    """Decode a Google encoded polyline (precision 5) to ``[[lat, lng], ...]``."""
    points: list[list[float]] = []
    index = lat = lng = 0
    while index < len(encoded):
        deltas = []
        for _ in range(2):
            shift = result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            deltas.append(~(result >> 1) if result & 1 else result >> 1)
        lat += deltas[0]
        lng += deltas[1]
        points.append([round(lat / 1e5, 5), round(lng / 1e5, 5)])
    return points


def compass_direction(start: list[float], end: list[float]) -> str:
    """Dominant travel axis start→end as north/south/east/west.

    Geographic truth, same convention as the Bulgarian pipeline: lat
    increasing = north, lng increasing = east (lng scaled by cos(lat)).
    """
    dlat = end[0] - start[0]
    dlng = (end[1] - start[1]) * math.cos(math.radians((start[0] + end[0]) / 2))
    if abs(dlat) >= abs(dlng):
        return "north" if dlat >= 0 else "south"
    return "east" if dlng >= 0 else "west"


def road_type(road: str | None) -> str:
    return "motorway" if road and re.fullmatch(r"A?M\d+[A-Z]?", road) else "road"


@dataclass
class Section:
    raw: dict
    centerline: list[list[float]]
    length_m: float

    @property
    def start(self) -> list[float]:
        return self.centerline[0]

    @property
    def end(self) -> list[float]:
        return self.centerline[-1]


def _in_uk(p: list[float]) -> bool:
    return UK_LAT[0] <= p[0] <= UK_LAT[1] and UK_LNG[0] <= p[1] <= UK_LNG[1]


def _is_duplicate(a: Section, b: Section) -> bool:
    return (
        haversine_m(*a.start, *b.start) <= DUP_ENDPOINT_M
        and haversine_m(*a.end, *b.end) <= DUP_ENDPOINT_M
        and abs(a.length_m - b.length_m) <= DUP_LENGTH_RATIO * max(a.length_m, b.length_m)
    )


def build_zones(sections_doc: dict, cameras_doc: dict | None) -> tuple[list[dict], list[str]]:
    """Convert sections to app zones. Returns ``(zones, notes)``.

    ``notes`` lists everything skipped or suspicious, for the run log.
    """
    notes: list[str] = []
    kept: list[Section] = []
    for raw in sorted(sections_doc["sections"], key=lambda s: (s["scheme"], s["id"])):
        sid = f"{raw['scheme']}#{raw['id']}"
        limit = raw.get("limit")
        if not isinstance(limit, int) or limit <= 0:
            notes.append(f"skip {sid}: no usable limit ({limit!r})")
            continue
        line = decode_polyline(raw.get("g") or "")
        if len(line) < 2:
            notes.append(f"skip {sid}: centerline has {len(line)} point(s)")
            continue
        if not all(_in_uk(p) for p in line):
            notes.append(f"skip {sid}: geometry outside the UK")
            continue
        length = polyline_length_m(line)
        if length < MIN_SECTION_M:
            notes.append(f"skip {sid}: {length:.0f} m is shorter than {MIN_SECTION_M} m")
            continue
        declared = raw.get("lengthM")
        if declared and abs(length - declared) > 0.1 * declared:
            notes.append(f"note {sid}: decoded length {length:.0f} m vs declared {declared} m")
        sec = Section(raw, line, length)
        dup = next((k for k in kept if _is_duplicate(k, sec)), None)
        if dup:
            notes.append(f"skip {sid}: duplicate of {dup.raw['scheme']}#{dup.raw['id']}")
            continue
        kept.append(sec)

    avg_cams: list[tuple[float, float]] = []
    if cameras_doc:
        kinds = cameras_doc["kinds"]
        avg_kind = kinds.index("average")
        avg_cams = [(r[0], r[1]) for r in cameras_doc["rows"] if r[2] == avg_kind]

    def nearest_cam_m(p: list[float]) -> float:
        return min((haversine_m(p[0], p[1], c[0], c[1]) for c in avg_cams), default=math.inf)

    zones: list[dict] = []
    per_scheme: dict[str, int] = {}
    for sec in kept:
        raw = sec.raw
        scheme = raw["scheme"]
        per_scheme[scheme] = per_scheme.get(scheme, 0) + 1
        direction = compass_direction(sec.start, sec.end)
        if avg_cams:
            for label, p in (("start", sec.start), ("end", sec.end)):
                d = nearest_cam_m(p)
                if d > CAMERA_CHECK_M:
                    notes.append(
                        f"note {scheme}#{raw['id']}: {label} is {d:.0f} m from the nearest average-speed camera"
                    )
        road = raw.get("road") or raw.get("street") or scheme
        street = raw.get("street")
        description = f"{road}, {street}" if street and street != road else road
        limit = raw["limit"]
        zones.append({
            "id": f"{scheme}-{per_scheme[scheme]:02d}-{direction}",
            "road": road,
            "road_latin": road,
            "direction": direction,
            "description": description,
            "start": {"lat": sec.start[0], "lng": sec.start[1], "km_marker": None,
                      "settlement": None, "settlement_latin": None},
            "end": {"lat": sec.end[0], "lng": sec.end[1], "km_marker": None,
                    "settlement": None, "settlement_latin": None},
            "distance_m": round(sec.length_m),
            # OSM tags the posted limit only. Lower national limits for goods
            # vehicles / coaches on single carriageways are not modelled, so
            # every class carries the posted limit.
            "speed_limits": {"car": limit, "truck": limit, "bus": limit, "motorcycle": None},
            "centerline": sec.centerline,
            "road_type": road_type(raw.get("road")),
            "source": SOURCE,
            "last_verified": sections_doc.get("updated", ""),
        })
    return zones, notes


def compute_hash(zones: list[dict]) -> str:
    """SHA-256 over the zones minus ``last_verified`` (as the BG pipeline does),
    so a monthly re-run with unchanged sections keeps the same hash."""
    payload = json.dumps(
        [{k: v for k, v in z.items() if k != "last_verified"} for z in zones],
        sort_keys=True,
        ensure_ascii=False,
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def build_document(sections_doc: dict, cameras_doc: dict | None) -> tuple[dict, list[str]]:
    zones, notes = build_zones(sections_doc, cameras_doc)
    updated = sections_doc.get("updated") or ""
    doc = {
        # The OSM extract date, so the Android build's freshness check measures
        # the age of the data rather than of this conversion run.
        "version": f"{updated}T00:00:00Z" if updated else "",
        "hash": compute_hash(zones),
        "speed_unit": "mph",
        "attribution": ATTRIBUTION,
        "licence": "ODbL-1.0",
        "zones": zones,
    }
    return doc, notes


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--offline", action="store_true", help="use the committed snapshot only")
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    sections_doc = fetch_json("sections.json", args.offline)
    try:
        cameras_doc = fetch_json("cameras.json", args.offline)
    except FileNotFoundError:
        logger.warning("no cameras.json; skipping the camera cross-check")
        cameras_doc = None

    doc, notes = build_document(sections_doc, cameras_doc)
    for n in notes:
        logger.info(n)
    if not doc["zones"]:
        logger.error("no usable zones; refusing to overwrite %s", args.output)
        return 1
    args.output.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    logger.info(
        "wrote %d zones from %d sections (%d notes) to %s",
        len(doc["zones"]), len(sections_doc["sections"]), len(notes), args.output,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
