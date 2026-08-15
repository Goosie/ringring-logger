#!/usr/bin/env python3
"""Builds assets/registry/registry-v1.json for the quill corridor-matching
engine (see lib/quill/registry.dart for the schema this produces).

Primary path: fetch NWB wegvakken from the PDOK NWB WFS for the bbox below,
filter to gemeente-beheerde wegen (road types plausible for cycling — this
deliberately drops Rijk-beheerde wegen like the A10, which are frc/wegbehsrt
'R', and any tram-only entries), and write 1 wegvak = 1 corridor (no
chaining/merging in v1).

Fallback path: if the PDOK endpoint is unreachable, times out, or its
response doesn't parse the way this script expects, fall back to the
SYNTHETIC fixture at tool/fixtures/sample_wegvakken.geojson (~10 hand-drawn,
clearly-marked-fake corridor polylines in the same bbox) so the rest of the
pipeline (matcher, CLI, app) always has something to run against. The app
never needs to know which path produced the file — registry.dart just reads
whatever JSON lands at assets/registry/registry-v1.json.

Usage: python3 tool/build_registry.py
Requires: Python 3, the stdlib, and `requests` (pip install requests).
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import requests

# Nieuw-Vennep bbox: covers the two 2026-08-12 testdata/trips/ recordings
# (bike + walk, both ~lat 52.256-52.272 / lng 4.620-4.647), padded a bit so
# nearby streets aren't clipped. Picked so the bundled test registry can be
# scored against real, already-recorded ground-truth trips instead of only
# synthetic fixtures — swap these for wherever you actually want to test.
LAT_MIN, LAT_MAX = 52.254, 52.274
LNG_MIN, LNG_MAX = 4.618, 4.650

PDOK_WFS_URL = "https://service.pdok.nl/rws/nwbwegen/wfs/v1_0"
PDOK_TIMEOUT_S = 20

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_PATH = REPO_ROOT / "tool" / "fixtures" / "sample_wegvakken.geojson"
OUTPUT_PATH = REPO_ROOT / "assets" / "registry" / "registry-v1.json"

REGISTRY_VERSION = "v1"


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371000.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lng / 2) ** 2
    )
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def line_length_m(coords_lat_lng: list[list[float]]) -> float:
    total = 0.0
    for a, b in zip(coords_lat_lng, coords_lat_lng[1:]):
        total += haversine_m(a[0], a[1], b[0], b[1])
    return total


def fetch_pdok_wegvakken() -> list[dict]:
    """Raises on any failure — caller decides whether to fall back."""
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": "wegvakken",
        "outputFormat": "json",
        "srsName": "EPSG:4326",
        "bbox": f"{LAT_MIN},{LNG_MIN},{LAT_MAX},{LNG_MAX},EPSG:4326",
        "count": 5000,
    }
    resp = requests.get(PDOK_WFS_URL, params=params, timeout=PDOK_TIMEOUT_S)
    resp.raise_for_status()
    data = resp.json()
    features = data["features"]
    if not isinstance(features, list):
        raise ValueError("unexpected PDOK response shape: 'features' is not a list")
    return features


def pdok_feature_to_corridor(feature: dict) -> dict | None:
    props = feature["properties"]
    # Gemeente-beheerde wegen only: drops Rijk (motorways/trunk roads, e.g.
    # the A10) and the odd tram-only entry — not plausible cycling routes.
    if props.get("wegbehsrt") != "G":
        return None

    geom = feature["geometry"]
    if geom["type"] == "LineString":
        lines = [geom["coordinates"]]
    elif geom["type"] == "MultiLineString":
        lines = geom["coordinates"]
    else:
        return None

    # GeoJSON coordinates are [lng, lat]; registry.dart wants [lat, lng].
    # Concatenate every part in order — NWB wegvakken are effectively
    # single paths wrapped in MultiLineString by the WFS.
    coords = [[lat, lng] for line in lines for lng, lat in line]
    if len(coords) < 2:
        return None

    wvk_id = props.get("wvkId")
    corridor_id = str(int(wvk_id)) if wvk_id is not None else feature["id"]
    length_m = props.get("stLengthshape")
    if length_m is None:
        length_m = line_length_m(coords)

    return {
        "id": corridor_id,
        "name": props.get("sttNaam") or "",
        "coords": coords,
        "lengthM": round(float(length_m), 1),
    }


def build_from_pdok() -> list[dict]:
    features = fetch_pdok_wegvakken()
    corridors = []
    for feature in features:
        corridor = pdok_feature_to_corridor(feature)
        if corridor is not None:
            corridors.append(corridor)
    if not corridors:
        raise ValueError("PDOK returned no usable gemeente wegvakken for this bbox")
    return corridors


def build_from_fixture() -> list[dict]:
    data = json.loads(FIXTURE_PATH.read_text())
    corridors = []
    for feature in data["features"]:
        props = feature["properties"]
        coords = [[lat, lng] for lng, lat in feature["geometry"]["coordinates"]]
        corridors.append({
            "id": props["id"],
            "name": props["name"],
            "coords": coords,
            "lengthM": round(line_length_m(coords), 1),
        })
    return corridors


def main() -> None:
    try:
        corridors = build_from_pdok()
        source = "pdok"
    except Exception as exc:  # noqa: BLE001 - any failure means "use the fallback"
        print(f"PDOK NWB WFS unavailable or unexpected ({exc}); falling back to synthetic fixture.", file=sys.stderr)
        corridors = build_from_fixture()
        source = "synthetic-fixture"

    registry = {
        "version": REGISTRY_VERSION,
        "region": f"Nieuw-Vennep bbox lat {LAT_MIN}-{LAT_MAX} lng {LNG_MIN}-{LNG_MAX} (source: {source})",
        "corridors": corridors,
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(registry, indent=1))
    print(f"wrote {OUTPUT_PATH} — {len(corridors)} corridors (source: {source})")


if __name__ == "__main__":
    main()
