#!/usr/bin/env python3
"""Validate vector structure and raster contamination in a Cell_ppt master SVG."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


VECTOR_TAGS = {
    "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "use"
}
RASTER_TAGS = {"image"}
FORBIDDEN_TAGS = {"foreignObject", "script"}
NUMBER_RE = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")
NONFINITE_RE = re.compile(r"(?:^|[^A-Za-z])(?:nan|[-+]?inf(?:inity)?)(?:$|[^A-Za-z])", re.I)
HREF_NAMES = {"href", "{http://www.w3.org/1999/xlink}href"}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def parse_view_box(raw: str | None) -> list[float] | None:
    if not raw:
        return None
    values = [float(value) for value in NUMBER_RE.findall(raw)]
    if len(values) != 4 or not all(math.isfinite(value) for value in values):
        return None
    return values if values[2] > 0 and values[3] > 0 else None


def audit_svg(svg_path: Path, strict_ids: bool, allow_raster: bool) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    counts: Counter[str] = Counter()
    ids: list[str] = []
    missing_ids: list[str] = []
    external_references: list[str] = []

    try:
        payload = svg_path.read_bytes()
        root = ET.fromstring(payload)
    except (OSError, ET.ParseError) as exc:
        return {"status": "FAIL", "file": str(svg_path), "errors": [str(exc)], "warnings": []}

    if local_name(root.tag) != "svg":
        errors.append("Root element is not <svg>.")
    view_box = parse_view_box(root.attrib.get("viewBox"))
    if view_box is None:
        errors.append("A finite positive four-number viewBox is required.")

    for element in root.iter():
        tag = local_name(element.tag)
        counts[tag] += 1
        element_id = element.attrib.get("id")
        if element_id:
            ids.append(element_id)
        if tag in FORBIDDEN_TAGS:
            errors.append(f"Forbidden <{tag}> element: {element_id or '(no id)' }.")
        if tag in VECTOR_TAGS:
            if not element_id:
                missing_ids.append(tag)
            if tag == "path" and not element.attrib.get("d", "").strip():
                errors.append(f"Empty path data: {element_id or '(no id)' }.")
        for name, value in element.attrib.items():
            if NONFINITE_RE.search(value):
                errors.append(f"Non-finite numeric token in {element_id or tag}.{name}.")
            if name in HREF_NAMES and value and not value.startswith("#"):
                external_references.append(value[:120])

    duplicates = sorted(key for key, count in Counter(ids).items() if count > 1)
    if duplicates:
        errors.append("Duplicate element IDs: " + ", ".join(duplicates[:20]))

    vector_count = sum(counts[tag] for tag in VECTOR_TAGS)
    raster_count = sum(counts[tag] for tag in RASTER_TAGS)
    if vector_count == 0:
        errors.append("No editable vector/text elements were found.")
    if raster_count:
        message = f"Found {raster_count} raster <image> node(s)."
        (warnings if allow_raster else errors).append(message)
    if external_references:
        message = "External or embedded references: " + ", ".join(sorted(set(external_references))[:20])
        (warnings if allow_raster else errors).append(message)
    if missing_ids:
        message = f"{len(missing_ids)} editable element(s) lack stable IDs: " + ", ".join(
            f"{tag}={count}" for tag, count in sorted(Counter(missing_ids).items())
        )
        (errors if strict_ids else warnings).append(message)

    return {
        "schema_version": "1.0",
        "status": "PASS" if not errors else "FAIL",
        "file": str(svg_path.resolve()),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "view_box": view_box,
        "counts": dict(sorted(counts.items())),
        "vector_element_count": vector_count,
        "raster_node_count": raster_count,
        "stable_id_count": len(ids),
        "strict_ids": strict_ids,
        "allow_raster": allow_raster,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a Cell_ppt figure_master.svg.")
    parser.add_argument("--svg", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--strict-ids", action="store_true")
    parser.add_argument(
        "--allow-raster",
        action="store_true",
        help="Allow explicitly requested photo panels; raster nodes remain warnings.",
    )
    args = parser.parse_args()
    report = audit_svg(args.svg, args.strict_ids, args.allow_raster)
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered, encoding="utf-8")
    sys.stdout.write(rendered)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
