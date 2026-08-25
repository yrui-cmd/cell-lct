#!/usr/bin/env python3
"""Merge a recorded text manifest into a vector SVG as live editable text."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)


def finite(value: object, name: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{name} must be finite")
    return number


def parse_viewbox(root: ET.Element) -> tuple[float, float, float, float]:
    raw = root.get("viewBox")
    if raw:
        parts = [float(item) for item in re.split(r"[\s,]+", raw.strip()) if item]
        if len(parts) == 4 and parts[2] > 0 and parts[3] > 0:
            return parts[0], parts[1], parts[2], parts[3]
    width = float(re.sub(r"[^0-9.+-]", "", root.get("width", "0")) or 0)
    height = float(re.sub(r"[^0-9.+-]", "", root.get("height", "0")) or 0)
    if width <= 0 or height <= 0:
        raise ValueError("SVG requires a valid viewBox or numeric width and height")
    root.set("viewBox", f"0 0 {width:g} {height:g}")
    return 0.0, 0.0, width, height


def color(value: object) -> str:
    text = str(value or "#000000").strip()
    if not re.fullmatch(r"#[0-9A-Fa-f]{3,8}|[A-Za-z]+|none", text):
        raise ValueError(f"unsupported color: {text}")
    return text


def coordinate(item: dict, key: str, origin: float, extent: float, normalized: bool) -> float:
    value = finite(item[key], key)
    return origin + value * extent if normalized else value


def add_text(root: ET.Element, item: dict, viewbox: tuple[float, float, float, float]) -> ET.Element:
    for required in ("id", "content", "x", "y"):
        if required not in item:
            raise ValueError(f"text element is missing {required}")
    x0, y0, width, height = viewbox
    normalized = item.get("coordinate_space", "normalized") == "normalized"
    x = coordinate(item, "x", x0, width, normalized)
    y = coordinate(item, "y", y0, height, normalized)
    font_size_raw = finite(item.get("font_size", 12), "font_size")
    font_size = font_size_raw * height if normalized and item.get("font_size_space") == "normalized" else font_size_raw

    attributes = {
        "id": str(item["id"]),
        "x": f"{x:g}",
        "y": f"{y:g}",
        "fill": color(item.get("fill", "#000000")),
        "font-family": str(item.get("font_family", "Arial")),
        "font-size": f"{font_size:g}",
        "font-weight": str(item.get("font_weight", "normal")),
        "font-style": str(item.get("font_style", "normal")),
        "text-anchor": str(item.get("text_anchor", "start")),
        "opacity": f"{finite(item.get('opacity', 1), 'opacity'):g}",
        "data-z-index": str(int(item.get("z_index", item.get("paint_order", len(root))))),
        "data-paint-order": str(int(item.get("paint_order", len(root)))),
    }
    rotation = finite(item.get("rotation", 0), "rotation")
    if rotation:
        attributes["transform"] = f"rotate({rotation:g} {x:g} {y:g})"
    if item.get("alignment_baseline"):
        attributes["alignment-baseline"] = str(item["alignment_baseline"])

    lines = str(item["content"]).splitlines() or [""]
    line_height = finite(item.get("line_height", 1.2), "line_height") * font_size
    if len(lines) == 1:
        element = ET.Element(f"{{{SVG_NS}}}text", attributes)
        element.text = lines[0]
        return element

    group_attributes = {
        "id": attributes["id"],
        "data-z-index": attributes["data-z-index"],
        "data-paint-order": attributes["data-paint-order"],
    }
    group = ET.Element(f"{{{SVG_NS}}}g", group_attributes)
    for index, line in enumerate(lines):
        line_attributes = dict(attributes)
        line_attributes["id"] = f"{attributes['id']}-line-{index + 1}"
        line_attributes["y"] = f"{y + index * line_height:g}"
        if rotation:
            line_y = y + index * line_height
            line_attributes["transform"] = f"rotate({rotation:g} {x:g} {line_y:g})"
        line_element = ET.SubElement(group, f"{{{SVG_NS}}}text", line_attributes)
        line_element.text = line
    return group


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge live text into a Cell-lct Master SVG.")
    parser.add_argument("--input-svg", required=True)
    parser.add_argument("--text-manifest", required=True)
    parser.add_argument("--output-svg", required=True)
    args = parser.parse_args()

    input_svg = Path(args.input_svg).resolve()
    manifest_path = Path(args.text_manifest).resolve()
    output_svg = Path(args.output_svg).resolve()
    tree = ET.parse(input_svg)
    root = tree.getroot()
    if root.tag.split("}")[-1] != "svg":
        raise ValueError("input root is not svg")
    if any(node.tag.split("}")[-1] == "image" for node in root.iter()):
        raise ValueError("input SVG contains a raster image node")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if manifest.get("schema_version") != "1.0":
        raise ValueError("text manifest schema_version must be 1.0")
    items = manifest.get("text_elements")
    if not isinstance(items, list):
        raise ValueError("text_elements must be an array")

    viewbox = parse_viewbox(root)
    existing_ids = {node.get("id") for node in root.iter() if node.get("id")}
    additions: list[tuple[int, ET.Element]] = []
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("each text element must be an object")
        if str(item.get("id", "")) in existing_ids:
            raise ValueError(f"duplicate SVG id: {item.get('id')}")
        additions.append((int(item.get("paint_order", len(root))), add_text(root, item, viewbox)))

    for paint_order, element in sorted(additions, key=lambda pair: pair[0]):
        root.insert(max(0, min(paint_order, len(root))), element)

    root.set("data-cell-lct-text-manifest", manifest_path.name)
    output_svg.parent.mkdir(parents=True, exist_ok=True)
    tree.write(output_svg, encoding="utf-8", xml_declaration=True)
    print(json.dumps({"ok": True, "output_svg": str(output_svg), "live_text_count": len(additions)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"TEXT_MERGE_ERROR|{exc}", file=sys.stderr)
        raise SystemExit(1)
