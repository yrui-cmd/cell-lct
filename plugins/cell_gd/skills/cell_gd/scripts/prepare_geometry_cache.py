#!/usr/bin/env python3
"""Parse one Cell_ppt SVG once and prepare resumable cached drawing batches."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
import xml.etree.ElementTree as ET

from fontTools.misc.transform import Transform
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path


ALLOWED_ATOMS = {"path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text"}
CONTAINERS = {"svg", "g", "a", "switch"}
FORBIDDEN = {
    "image", "tspan", "textPath", "clipPath", "mask", "filter",
    "linearGradient", "radialGradient", "pattern", "foreignObject", "script", "use",
}
INHERITED_PRESENTATION = {
    "color", "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity",
    "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
    "stroke-dasharray", "stroke-dashoffset", "vector-effect", "visibility",
    "font-family", "font-size", "font-style", "font-weight", "text-anchor",
    "dominant-baseline", "letter-spacing",
}
DEFAULT_PRESENTATION = {
    "color": "black",
    "fill": "black",
    "fill-opacity": "1",
    "fill-rule": "nonzero",
    "stroke": "none",
    "stroke-opacity": "1",
    "stroke-width": "1",
    "stroke-linecap": "butt",
    "stroke-linejoin": "miter",
    "stroke-miterlimit": "4",
    "stroke-dasharray": "none",
    "stroke-dashoffset": "0",
    "vector-effect": "none",
    "visibility": "visible",
    "font-family": "Arial",
    "font-size": "16",
    "font-style": "normal",
    "font-weight": "normal",
    "text-anchor": "start",
    "dominant-baseline": "alphabetic",
    "letter-spacing": "0",
}
NUMBER_RE = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?")
TRANSFORM_RE = re.compile(r"([A-Za-z]+)\s*\(([^)]*)\)")
NAMED_COLORS = {
    "black": (0, 0, 0), "silver": (192, 192, 192), "gray": (128, 128, 128),
    "white": (255, 255, 255), "maroon": (128, 0, 0), "red": (255, 0, 0),
    "purple": (128, 0, 128), "fuchsia": (255, 0, 255), "green": (0, 128, 0),
    "lime": (0, 255, 0), "olive": (128, 128, 0), "yellow": (255, 255, 0),
    "navy": (0, 0, 128), "blue": (0, 0, 255), "teal": (0, 128, 128),
    "aqua": (0, 255, 255), "orange": (255, 165, 0),
}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json_atomic(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    temporary.replace(path)


def safe_job_id(value: str) -> str:
    result = re.sub(r"[^A-Za-z0-9_-]+", "_", value).strip("_")
    if not result:
        raise ValueError("job-id must contain at least one letter or number")
    return result[:48]


def parse_canvas(root: ET.Element) -> list[float]:
    view_box = root.get("viewBox")
    if view_box:
        values = [float(value) for value in re.split(r"[\s,]+", view_box.strip())]
        if len(values) != 4 or values[2] <= 0 or values[3] <= 0:
            raise ValueError(f"Invalid SVG viewBox: {view_box}")
        return values
    width = parse_number(root.get("width"), None)
    height = parse_number(root.get("height"), None)
    if width is None or height is None or width <= 0 or height <= 0:
        raise ValueError("SVG needs a valid viewBox or numeric width and height")
    return [0.0, 0.0, width, height]


def parse_number(value: str | None, default: float | None = 0.0) -> float | None:
    if value is None:
        return default
    match = NUMBER_RE.search(value.strip())
    if not match:
        return default
    return float(match.group(0))


def parse_style_attribute(value: str | None) -> dict[str, str]:
    result: dict[str, str] = {}
    if not value:
        return result
    for declaration in value.split(";"):
        if ":" not in declaration:
            continue
        key, raw = declaration.split(":", 1)
        key = key.strip().lower()
        raw = raw.strip()
        if key:
            result[key] = raw
    return result


def local_presentation(element: ET.Element) -> dict[str, str]:
    result: dict[str, str] = {}
    for key in INHERITED_PRESENTATION | {"display", "opacity"}:
        if element.get(key) is not None:
            result[key] = element.get(key, "")
    result.update(parse_style_attribute(element.get("style")))
    return result


def parse_transform(value: str | None) -> Transform:
    if not value or not value.strip():
        return Transform()
    result = Transform()
    position = 0
    for match in TRANSFORM_RE.finditer(value):
        between = value[position:match.start()]
        if between.strip(" \t\r\n,"):
            raise ValueError(f"Invalid transform syntax: {value}")
        name = match.group(1).lower()
        values = [float(number) for number in NUMBER_RE.findall(match.group(2))]
        if name == "matrix" and len(values) == 6:
            operation = Transform(*values)
        elif name == "translate" and len(values) in {1, 2}:
            operation = Transform().translate(values[0], values[1] if len(values) == 2 else 0.0)
        elif name == "scale" and len(values) in {1, 2}:
            operation = Transform().scale(values[0], values[1] if len(values) == 2 else values[0])
        elif name == "rotate" and len(values) in {1, 3}:
            angle = math.radians(values[0])
            if len(values) == 3:
                operation = Transform().translate(values[1], values[2]).rotate(angle).translate(-values[1], -values[2])
            else:
                operation = Transform().rotate(angle)
        elif name == "skewx" and len(values) == 1:
            operation = Transform(1, 0, math.tan(math.radians(values[0])), 1, 0, 0)
        elif name == "skewy" and len(values) == 1:
            operation = Transform(1, math.tan(math.radians(values[0])), 0, 1, 0, 0)
        else:
            raise ValueError(f"Unsupported transform function: {match.group(0)}")
        result = result.transform(operation)
        position = match.end()
    if value[position:].strip(" \t\r\n,"):
        raise ValueError(f"Invalid transform syntax: {value}")
    return result


def validate_tree(root: ET.Element) -> None:
    for element in root.iter():
        name = local_name(element.tag)
        if name in FORBIDDEN:
            raise ValueError(f"Unsupported SVG element <{name}>; expand it to solid-color paths first")
        if name == "style" or element.get("class"):
            raise ValueError("Embedded or class-dependent CSS is unsupported; inline all presentation attributes")
        for attr_name, attr_value in element.attrib.items():
            lowered = attr_value.lower()
            attr = local_name(attr_name)
            if attr in {"clip-path", "mask", "filter"} and attr_value not in {"", "none"}:
                raise ValueError(f"Unsupported {attr} on {element.get('id', name)}")
            if "url(" in lowered or (attr.endswith("href") and attr_value):
                raise ValueError(f"Unsupported linked paint or resource on {element.get('id', name)}")
            if attr == "vector-effect" and attr_value not in {"", "none", "non-scaling-stroke"}:
                raise ValueError("Unsupported vector-effect; expand it before cached drawing")


def element_path_data(element: ET.Element) -> str:
    name = local_name(element.tag)
    if name == "path":
        value = element.get("d", "").strip()
        if not value:
            raise ValueError(f"Empty path data on {element.get('id', 'path')}")
        # fontTools' arc tokenizer recognizes spaces and tabs but not SVG's
        # equally valid CR/LF separators. Normalize XML whitespace once before
        # parsing so multiline arc commands remain standards-compliant input.
        return re.sub(r"[\t\r\n ]+", " ", value)
    if name == "line":
        return f"M {parse_number(element.get('x1'))} {parse_number(element.get('y1'))} L {parse_number(element.get('x2'))} {parse_number(element.get('y2'))}"
    if name in {"polyline", "polygon"}:
        values = [float(number) for number in NUMBER_RE.findall(element.get("points", ""))]
        if len(values) < 4 or len(values) % 2:
            raise ValueError(f"Invalid points on <{name}>")
        commands = [f"M {values[0]} {values[1]}"]
        commands.extend(f"L {values[index]} {values[index + 1]}" for index in range(2, len(values), 2))
        if name == "polygon":
            commands.append("Z")
        return " ".join(commands)
    if name == "rect":
        x = parse_number(element.get("x")) or 0.0
        y = parse_number(element.get("y")) or 0.0
        width = parse_number(element.get("width")) or 0.0
        height = parse_number(element.get("height")) or 0.0
        if width <= 0 or height <= 0:
            raise ValueError("Rectangle width and height must be positive")
        rx_value = parse_number(element.get("rx"), None)
        ry_value = parse_number(element.get("ry"), None)
        rx = max(0.0, rx_value if rx_value is not None else (ry_value or 0.0))
        ry = max(0.0, ry_value if ry_value is not None else (rx_value or 0.0))
        rx = min(rx, width / 2.0)
        ry = min(ry, height / 2.0)
        if rx == 0 or ry == 0:
            return f"M {x} {y} H {x + width} V {y + height} H {x} Z"
        return (
            f"M {x + rx} {y} H {x + width - rx} A {rx} {ry} 0 0 1 {x + width} {y + ry} "
            f"V {y + height - ry} A {rx} {ry} 0 0 1 {x + width - rx} {y + height} "
            f"H {x + rx} A {rx} {ry} 0 0 1 {x} {y + height - ry} "
            f"V {y + ry} A {rx} {ry} 0 0 1 {x + rx} {y} Z"
        )
    if name in {"circle", "ellipse"}:
        cx = parse_number(element.get("cx")) or 0.0
        cy = parse_number(element.get("cy")) or 0.0
        rx = parse_number(element.get("r" if name == "circle" else "rx")) or 0.0
        ry = rx if name == "circle" else (parse_number(element.get("ry")) or 0.0)
        if rx <= 0 or ry <= 0:
            raise ValueError(f"<{name}> radii must be positive")
        return (
            f"M {cx + rx} {cy} A {rx} {ry} 0 1 1 {cx - rx} {cy} "
            f"A {rx} {ry} 0 1 1 {cx + rx} {cy} Z"
        )
    raise ValueError(f"Unsupported vector atom <{name}>")


def rounded(value: float) -> float:
    result = round(float(value), 6)
    return 0.0 if result == -0.0 else result


def same_point(first: list[float], second: list[float], tolerance: float = 1e-6) -> bool:
    return abs(first[0] - second[0]) <= tolerance and abs(first[1] - second[1]) <= tolerance


def recording_to_subpaths(recording: list[tuple[str, tuple]]) -> list[dict]:
    subpaths: list[dict] = []
    points: list[dict] = []

    def new_point(anchor: tuple[float, float]) -> dict:
        value = [rounded(anchor[0]), rounded(anchor[1])]
        return {"a": value[:], "l": value[:], "r": value[:], "t": "corner"}

    def flush(closed: bool) -> None:
        nonlocal points
        if not points:
            return
        if closed and len(points) > 1 and same_point(points[0]["a"], points[-1]["a"]):
            duplicate = points.pop()
            points[0]["l"] = duplicate["l"]
        if len(points) >= 2:
            subpaths.append({"closed": closed, "points": points})
        points = []

    for operation, arguments in recording:
        if operation == "moveTo":
            flush(False)
            points = [new_point(arguments[0])]
        elif operation == "lineTo":
            if not points:
                raise ValueError("Path lineTo appeared before moveTo")
            for endpoint in arguments:
                points[-1]["r"] = points[-1]["a"][:]
                points.append(new_point(endpoint))
        elif operation == "curveTo":
            if not points or len(arguments) % 3:
                raise ValueError("Invalid cubic path operation")
            for index in range(0, len(arguments), 3):
                control_one, control_two, endpoint = arguments[index:index + 3]
                points[-1]["r"] = [rounded(control_one[0]), rounded(control_one[1])]
                created = new_point(endpoint)
                created["l"] = [rounded(control_two[0]), rounded(control_two[1])]
                points.append(created)
        elif operation == "closePath":
            flush(True)
        elif operation == "endPath":
            flush(False)
        else:
            raise ValueError(f"Unsupported parsed path operation: {operation}")
    flush(False)
    if not subpaths:
        raise ValueError("Vector atom produced no drawable subpaths")
    return subpaths


def parse_color(value: str, current_color: str) -> tuple[list[int] | None, float]:
    raw = value.strip().lower()
    if raw == "currentcolor":
        raw = current_color.strip().lower()
    if raw in {"none", "transparent"}:
        return None, 0.0
    if raw.startswith("#"):
        digits = raw[1:]
        if len(digits) in {3, 4}:
            digits = "".join(character * 2 for character in digits)
        if len(digits) not in {6, 8}:
            raise ValueError(f"Unsupported hex color: {value}")
        rgb = [int(digits[index:index + 2], 16) for index in (0, 2, 4)]
        alpha = int(digits[6:8], 16) / 255.0 if len(digits) == 8 else 1.0
        return rgb, alpha
    rgb_match = re.fullmatch(r"rgba?\((.*)\)", raw)
    if rgb_match:
        components = [part.strip() for part in re.split(r"[,\s/]+", rgb_match.group(1)) if part.strip()]
        if len(components) not in {3, 4}:
            raise ValueError(f"Unsupported RGB color: {value}")
        rgb: list[int] = []
        for component in components[:3]:
            numeric = float(component[:-1]) * 2.55 if component.endswith("%") else float(component)
            rgb.append(max(0, min(255, int(round(numeric)))))
        alpha = 1.0
        if len(components) == 4:
            alpha = float(components[3][:-1]) / 100.0 if components[3].endswith("%") else float(components[3])
        return rgb, max(0.0, min(1.0, alpha))
    if raw in NAMED_COLORS:
        return list(NAMED_COLORS[raw]), 1.0
    raise ValueError(f"Unsupported solid color: {value}")


def opacity_value(value: str | None, default: float = 1.0) -> float:
    if value is None:
        return default
    parsed = parse_number(value, default)
    return max(0.0, min(1.0, float(parsed if parsed is not None else default)))


def paint_parts(presentation: dict[str, str], accumulated_opacity: float, stroke_scale: float) -> list[dict]:
    dash = presentation.get("stroke-dasharray", "none").strip().lower()
    if dash not in {"", "none"}:
        raise ValueError("Dashed strokes must be expanded to solid paths before cached drawing")
    current_color = presentation.get("color", "black")
    fill_color, fill_alpha = parse_color(presentation.get("fill", "black"), current_color)
    stroke_color, stroke_alpha = parse_color(presentation.get("stroke", "none"), current_color)
    fill_opacity = accumulated_opacity * opacity_value(presentation.get("fill-opacity")) * fill_alpha
    stroke_opacity = accumulated_opacity * opacity_value(presentation.get("stroke-opacity")) * stroke_alpha
    filled = fill_color is not None and fill_opacity > 0
    stroked = stroke_color is not None and stroke_opacity > 0
    if not filled and not stroked:
        return []
    non_scaling_stroke = presentation.get("vector-effect", "none").strip().lower() == "non-scaling-stroke"
    common = {
        "fillRule": "evenodd" if presentation.get("fill-rule", "nonzero").strip().lower() == "evenodd" else "nonzero",
        "strokeWidth": rounded((parse_number(presentation.get("stroke-width"), 1.0) or 1.0) * (1.0 if non_scaling_stroke else stroke_scale)),
        "nonScalingStroke": non_scaling_stroke,
        "strokeCap": presentation.get("stroke-linecap", "butt").strip().lower(),
        "strokeJoin": presentation.get("stroke-linejoin", "miter").strip().lower(),
        "strokeMiterLimit": rounded(parse_number(presentation.get("stroke-miterlimit"), 4.0) or 4.0),
    }

    def part(use_fill: bool, use_stroke: bool, opacity: float) -> dict:
        result = dict(common)
        result.update({
            "filled": use_fill,
            "fillColor": fill_color if use_fill else None,
            "stroked": use_stroke,
            "strokeColor": stroke_color if use_stroke else None,
            "opacity": rounded(opacity * 100.0),
        })
        return result

    if filled and stroked and abs(fill_opacity - stroke_opacity) <= 1e-9:
        return [part(True, True, fill_opacity)]
    result = []
    if filled:
        result.append(part(True, False, fill_opacity))
    if stroked:
        result.append(part(False, True, stroke_opacity))
    return result


def parse_atom(element: ET.Element, transform: Transform, presentation: dict[str, str], opacity: float, index: int) -> dict | None:
    if local_name(element.tag) == "text":
        content = "".join(element.itertext())
        if not content:
            return None
        current_color = presentation.get("color", "black")
        fill_color, fill_alpha = parse_color(presentation.get("fill", "black"), current_color)
        text_opacity = opacity * opacity_value(presentation.get("fill-opacity")) * fill_alpha
        if fill_color is None or text_opacity <= 0:
            return None
        x = parse_number(element.get("x"), 0.0) or 0.0
        y = parse_number(element.get("y"), 0.0) or 0.0
        mapped_x, mapped_y = transform.transformPoint((x, y))
        determinant = transform.xx * transform.yy - transform.xy * transform.yx
        text_scale = math.sqrt(abs(determinant)) if determinant else 1.0
        font_size = (parse_number(presentation.get("font-size"), 16.0) or 16.0) * text_scale
        letter_spacing = (parse_number(presentation.get("letter-spacing"), 0.0) or 0.0) * text_scale
        font_family = presentation.get("font-family", "Arial").split(",", 1)[0].strip().strip("'\"") or "Arial"
        source_id = element.get("id") or f"source_atom_{index:06d}"
        return {
            "kind": "text",
            "index": index,
            "sourceId": source_id,
            "objectName": f"CELL_PPT_CACHE_ATOM_{index:06d}",
            "text": {
                "contents": content,
                "position": [rounded(mapped_x), rounded(mapped_y)],
                "fontSize": rounded(font_size),
                "fontFamily": font_family,
                "fontWeight": presentation.get("font-weight", "normal").strip().lower(),
                "fontStyle": presentation.get("font-style", "normal").strip().lower(),
                "textAnchor": presentation.get("text-anchor", "start").strip().lower(),
                "dominantBaseline": presentation.get("dominant-baseline", "alphabetic").strip().lower(),
                "letterSpacing": rounded(letter_spacing),
                "rotationDegrees": rounded(math.degrees(math.atan2(transform.xy, transform.xx))),
                "fillColor": fill_color,
                "opacity": rounded(text_opacity * 100.0),
            },
            "paintParts": [],
            "complexity": 1,
        }

    determinant = transform.xx * transform.yy - transform.xy * transform.yx
    stroke_scale = math.sqrt(abs(determinant)) if determinant else 1.0
    parts = paint_parts(presentation, opacity, stroke_scale)
    if not parts:
        return None
    recording = RecordingPen()
    transformed_pen = TransformPen(recording, transform)
    cubic_pen = Qu2CuPen(transformed_pen, max_err=0.001, all_cubic=True)
    parse_path(element_path_data(element), cubic_pen)
    subpaths = recording_to_subpaths(recording.value)
    complexity = sum(len(subpath["points"]) for subpath in subpaths)
    source_id = element.get("id") or f"source_atom_{index:06d}"
    return {
        "kind": "path",
        "index": index,
        "sourceId": source_id,
        "objectName": f"CELL_PPT_CACHE_ATOM_{index:06d}",
        "subpaths": subpaths,
        "paintParts": parts,
        "complexity": complexity,
    }


def collect_atoms(root: ET.Element) -> list[dict]:
    atoms: list[dict] = []

    def walk(parent: ET.Element, inherited: dict[str, str], opacity: float, transform: Transform, hidden: bool) -> None:
        for child in list(parent):
            name = local_name(child.tag)
            if name in {"title", "desc", "metadata", "defs"}:
                continue
            local = local_presentation(child)
            child_presentation = dict(inherited)
            for key in INHERITED_PRESENTATION:
                if key in local and local[key].strip().lower() != "inherit":
                    child_presentation[key] = local[key]
            child_hidden = hidden or local.get("display", "inline").strip().lower() == "none"
            child_hidden = child_hidden or child_presentation.get("visibility", "visible").strip().lower() in {"hidden", "collapse"}
            child_opacity = opacity * opacity_value(local.get("opacity"))
            child_transform = transform.transform(parse_transform(child.get("transform")))
            if name in ALLOWED_ATOMS:
                if not child_hidden:
                    atom = parse_atom(child, child_transform, child_presentation, child_opacity, len(atoms))
                    if atom is not None:
                        atoms.append(atom)
            elif name in CONTAINERS:
                walk(child, child_presentation, child_opacity, child_transform, child_hidden)
            else:
                raise ValueError(f"Unsupported rendered SVG element <{name}>; expand it to a path")

    root_local = local_presentation(root)
    inherited = dict(DEFAULT_PRESENTATION)
    for key in INHERITED_PRESENTATION:
        if key in root_local:
            inherited[key] = root_local[key]
    root_hidden = root_local.get("display", "inline").strip().lower() == "none"
    root_opacity = opacity_value(root_local.get("opacity"))
    root_transform = parse_transform(root.get("transform"))
    walk(root, inherited, root_opacity, root_transform, root_hidden)
    if not atoms:
        raise ValueError("SVG contains no visible supported vector atoms")
    return atoms


def build_batches(atoms: list[dict], job_id: str, min_size: int, max_size: int, complex_threshold: int, max_points: int) -> list[dict]:
    total_atoms = len(atoms)
    if total_atoms < min_size:
        planned = [("normal", list(range(total_atoms)))]
    else:
        point_prefix = [0]
        complex_prefix = [0]
        for atom in atoms:
            complexity = int(atom["complexity"])
            point_prefix.append(point_prefix[-1] + complexity)
            complex_prefix.append(complex_prefix[-1] + int(complexity >= complex_threshold))

        # Dynamic programming keeps source order while enforcing 20-50 atoms
        # for every ordinary transfer. Complex atoms are isolated whenever the
        # surrounding sequence remains partitionable; otherwise they stay in
        # an ordinary 20-50 batch instead of creating a tiny ordinary batch.
        scores: list[tuple[int, int, int] | None] = [None] * (total_atoms + 1)
        previous: list[tuple[int, str] | None] = [None] * (total_atoms + 1)
        scores[0] = (0, 0, 0)

        def relax(end: int, score: tuple[int, int, int], start: int, kind: str) -> None:
            if scores[end] is None or score < scores[end]:
                scores[end] = score
                previous[end] = (start, kind)

        for start in range(total_atoms):
            current_score = scores[start]
            if current_score is None:
                continue
            if int(atoms[start]["complexity"]) >= complex_threshold:
                relax(start + 1, (current_score[0], current_score[1], current_score[2] + 1), start, "complex")
            for count in range(min_size, max_size + 1):
                end = start + count
                if end > total_atoms:
                    break
                embedded_complex = complex_prefix[end] - complex_prefix[start]
                point_count = point_prefix[end] - point_prefix[start]
                overflow = max(0, point_count - max_points)
                relax(
                    end,
                    (
                        current_score[0] + embedded_complex,
                        current_score[1] + overflow,
                        current_score[2] + 1,
                    ),
                    start,
                    "normal",
                )

        if scores[total_atoms] is None:
            raise ValueError("Could not partition SVG atoms into the required 20-50 drawing batches")
        reversed_plan: list[tuple[str, list[int]]] = []
        end = total_atoms
        while end > 0:
            step = previous[end]
            if step is None:
                raise ValueError("Incomplete drawing batch plan")
            start, kind = step
            reversed_plan.append((kind, list(range(start, end))))
            end = start
        planned = list(reversed(reversed_plan))

    batches: list[dict] = []
    for kind, indices in planned:
        batch_index = len(batches)
        batches.append({
            "index": batch_index,
            "kind": kind,
            "group_name": f"CELL_PPT_CACHE_{job_id}_{batch_index:04d}",
            "atom_indices": indices,
            "atomic_count": len(indices),
            "complexity": sum(atoms[index]["complexity"] for index in indices),
        })
    return batches


def validate_batch_contract(batches: list[dict], atoms: list[dict], min_size: int, max_size: int, complex_threshold: int) -> None:
    """Prevent accidental regression to tiny ordinary batches."""
    total_atoms = len(atoms)
    if total_atoms < min_size:
        if len(batches) != 1 or batches[0]["kind"] != "normal" or batches[0]["atomic_count"] != total_atoms:
            raise ValueError("A sub-minimum whole job must remain one ordinary drawing batch")
        return
    for batch in batches:
        count = int(batch["atomic_count"])
        kind = batch["kind"]
        if kind == "complex":
            if count != 1:
                raise ValueError("A complex batch must contain exactly one atom")
            atom_index = int(batch["atom_indices"][0])
            if int(atoms[atom_index]["complexity"]) < complex_threshold:
                raise ValueError("Only a genuinely complex atom may be a singleton batch")
            continue
        if not min_size <= count <= max_size:
            raise ValueError(f"Ordinary batch size {count} is outside {min_size}..{max_size}")


def prepare(input_svg: Path, output_dir: Path, job_id: str, min_size: int, max_size: int, complex_threshold: int, max_points: int) -> tuple[dict, dict]:
    input_svg = input_svg.resolve(strict=True)
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    job_id = safe_job_id(job_id)
    source_hash = sha256_file(input_svg)
    cache_path = output_dir / "geometry-cache.json"
    state_path = output_dir / "drawing-state.json"

    if cache_path.exists() or state_path.exists():
        if not cache_path.exists() or not state_path.exists():
            raise ValueError("Cached drawing state is incomplete; use a new work directory")
        cache = json.loads(cache_path.read_text(encoding="utf-8-sig"))
        state = json.loads(state_path.read_text(encoding="utf-8-sig"))
        compatible = (
            cache.get("schema_version") == 3
            and cache.get("source_sha256") == source_hash
            and cache.get("job_id") == job_id
            and cache.get("min_batch_size") == min_size
            and cache.get("max_batch_size") == max_size
            and cache.get("complex_point_threshold") == complex_threshold
            and cache.get("max_batch_points") == max_points
            and state.get("cache_sha256") == sha256_file(cache_path)
        )
        if not compatible:
            raise ValueError("Existing geometry cache belongs to different input or batch settings; use a new work directory")
        return cache, state

    tree = ET.parse(input_svg)
    root = tree.getroot()
    if local_name(root.tag) != "svg":
        raise ValueError("Input root must be <svg>")
    validate_tree(root)
    view_box = parse_canvas(root)
    atoms = collect_atoms(root)
    batches = build_batches(atoms, job_id, min_size, max_size, complex_threshold, max_points)
    validate_batch_contract(batches, atoms, min_size, max_size, complex_threshold)
    cache = {
        "schema_version": 3,
        "created_at": utc_now(),
        "source_svg": str(input_svg),
        "source_sha256": source_hash,
        "job_id": job_id,
        "view_box": [rounded(value) for value in view_box],
        "min_batch_size": min_size,
        "max_batch_size": max_size,
        "complex_point_threshold": complex_threshold,
        "max_batch_points": max_points,
        "total_atoms": len(atoms),
        "atoms": atoms,
        "batches": batches,
    }
    write_json_atomic(cache_path, cache)
    cache_hash = sha256_file(cache_path)
    state = {
        "schema_version": 3,
        "created_at": utc_now(),
        "updated_at": utc_now(),
        "source_svg": str(input_svg),
        "source_sha256": source_hash,
        "cache_file": str(cache_path),
        "cache_sha256": cache_hash,
        "job_id": job_id,
        "root_group_name": f"CELL_PPT_CACHE_JOB_{job_id}",
        "total_atoms": len(atoms),
        "batches": [
            {
                "index": batch["index"],
                "group_name": batch["group_name"],
                "atom_indices": batch["atom_indices"],
                "atomic_count": batch["atomic_count"],
                "kind": batch["kind"],
                "completed": False,
                "completed_at": None,
                "attempts": 0,
                "last_error": None,
            }
            for batch in batches
        ],
    }
    write_json_atomic(state_path, state)
    return cache, state


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--job-id", required=True)
    parser.add_argument("--min-batch-size", type=int, default=20)
    parser.add_argument("--max-batch-size", type=int, default=50)
    parser.add_argument("--complex-point-threshold", type=int, default=320)
    parser.add_argument("--max-batch-points", type=int, default=2200)
    args = parser.parse_args()
    if not 1 <= args.min_batch_size <= args.max_batch_size <= 50:
        parser.error("batch sizes must satisfy 1 <= min <= max <= 50")
    if args.complex_point_threshold < 20 or args.max_batch_points < 100:
        parser.error("complexity thresholds are too small")
    try:
        cache, state = prepare(
            args.input, args.output_dir, args.job_id,
            args.min_batch_size, args.max_batch_size,
            args.complex_point_threshold, args.max_batch_points,
        )
    except (OSError, ET.ParseError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR|{error}", file=sys.stderr)
        return 1
    completed = sum(1 for item in state["batches"] if item.get("completed"))
    print(
        f"OK|cache={Path(args.output_dir).resolve() / 'geometry-cache.json'}|"
        f"state={Path(args.output_dir).resolve() / 'drawing-state.json'}|"
        f"atoms={cache['total_atoms']}|batches={len(cache['batches'])}|completed={completed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
