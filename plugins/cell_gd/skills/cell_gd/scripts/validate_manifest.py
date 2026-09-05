#!/usr/bin/env python3
"""Validate the core Scene Manifest contract for a Cell_ppt job."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


SEMANTIC_TYPES = {"semantic_asset", "asset", "subject"}
ARROW_TYPES = {"arrow", "ARROW"}
RULE_TYPES = {
    "text", "TEXT", "arrow", "ARROW", "frame", "FRAME", "heatmap", "HEATMAP",
    "gradient_legend", "GRADIENT_LEGEND", "axis", "AXIS", "label", "LABEL",
    "connector", "CONNECTOR", "background", "region",
}


def provider_of(obj: dict[str, Any]) -> str | None:
    source = obj.get("source")
    if isinstance(source, str):
        return source.lower()
    if isinstance(source, dict):
        provider = source.get("provider") or source.get("name")
        return str(provider).lower() if provider else None
    return None


def accepted_of(obj: dict[str, Any]) -> bool:
    values = [obj.get("api_status"), obj.get("status")]
    api = obj.get("api")
    if isinstance(api, dict):
        values.append(api.get("status"))
    return any(str(value).lower() in {"accepted", "pass", "passed", "success", "completed"} for value in values)


def vector_valid_of(obj: dict[str, Any]) -> bool:
    values = [obj.get("vector_valid"), obj.get("path_validation")]
    validation = obj.get("validation")
    if isinstance(validation, dict):
        values.extend([validation.get("vector_valid"), validation.get("path")])
    return any(value is True or str(value).lower() in {"pass", "passed", "valid"} for value in values)


def normalized_bbox(obj: dict[str, Any]) -> dict[str, Any] | None:
    value = obj.get("bbox_normalized") or obj.get("normalized_bbox")
    return value if isinstance(value, dict) else None


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def audit(path: Path) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return {"status": "FAIL", "file": str(path), "errors": [str(exc)], "warnings": []}
    if not isinstance(manifest, dict):
        return {"status": "FAIL", "file": str(path), "errors": ["Manifest must be a JSON object."], "warnings": []}

    if not isinstance(manifest.get("canvas_size") or manifest.get("canvas"), dict):
        errors.append("Manifest requires canvas_size or canvas object.")
    objects = manifest.get("objects")
    if not isinstance(objects, list) or not objects:
        errors.append("Manifest requires a non-empty objects list.")
        objects = []

    seen_ids: set[str] = set()
    draw_orders: dict[Any, str] = {}
    references: list[tuple[str, str, str]] = []
    semantic_count = 0
    rule_count = 0

    for index, obj in enumerate(objects):
        if not isinstance(obj, dict):
            errors.append(f"objects[{index}] is not an object.")
            continue
        object_id = obj.get("id")
        if not isinstance(object_id, str) or not object_id:
            errors.append(f"objects[{index}] lacks a stable id.")
            object_id = f"objects[{index}]"
        elif object_id in seen_ids:
            errors.append(f"Duplicate object id: {object_id}")
        else:
            seen_ids.add(object_id)

        object_type = obj.get("type")
        if not isinstance(object_type, str) or not object_type:
            errors.append(f"{object_id} lacks type.")
            object_type = ""

        bbox = normalized_bbox(obj)
        if bbox is None:
            errors.append(f"{object_id} lacks normalized bbox.")
        else:
            for key in ("x", "y", "width", "height"):
                if not finite_number(bbox.get(key)):
                    errors.append(f"{object_id} bbox.{key} is not finite numeric.")
            if all(finite_number(bbox.get(key)) for key in ("x", "y", "width", "height")):
                if bbox["width"] <= 0 or bbox["height"] <= 0:
                    errors.append(f"{object_id} bbox width/height must be positive.")
                if bbox["x"] < 0 or bbox["y"] < 0 or bbox["x"] + bbox["width"] > 1 or bbox["y"] + bbox["height"] > 1:
                    warnings.append(f"{object_id} normalized bbox extends outside the canvas.")

        draw_order = obj.get("draw_order", obj.get("z_index"))
        if draw_order is None:
            errors.append(f"{object_id} lacks draw_order or z_index.")
        elif draw_order in draw_orders:
            errors.append(f"Duplicate draw order {draw_order}: {draw_orders[draw_order]} and {object_id}")
        else:
            draw_orders[draw_order] = object_id

        if object_type in SEMANTIC_TYPES:
            semantic_count += 1
            if provider_of(obj) != "xiaomiao":
                errors.append(f"{object_id} semantic subject is not sourced from xiaomiao.")
            if not accepted_of(obj):
                errors.append(f"{object_id} lacks an accepted API status.")
            if not vector_valid_of(obj):
                errors.append(f"{object_id} lacks passing vector/path validation.")
        elif object_type in RULE_TYPES:
            rule_count += 1

        if object_type in ARROW_TYPES:
            arrow = obj.get("arrow") if isinstance(obj.get("arrow"), dict) else obj
            for key in ("tail", "shaft", "head"):
                if not arrow.get(key) and not arrow.get(f"{key}_path"):
                    errors.append(f"{object_id} arrow lacks {key}.")
            source = arrow.get("source_object") or obj.get("source_object")
            target = arrow.get("target_object") or obj.get("target_object")
            if not isinstance(source, str) or not source:
                errors.append(f"{object_id} arrow lacks source_object.")
            else:
                references.append((object_id, "source_object", source))
            if not isinstance(target, str) or not target:
                errors.append(f"{object_id} arrow lacks target_object.")
            else:
                references.append((object_id, "target_object", target))

    for object_id, field, reference in references:
        if reference not in seen_ids:
            errors.append(f"{object_id} {field} references missing object: {reference}")

    if not isinstance(manifest.get("file_mappings"), (dict, list)):
        warnings.append("Manifest has no file_mappings collection.")

    return {
        "schema_version": "1.0",
        "status": "PASS" if not errors else "FAIL",
        "file": str(path.resolve()),
        "object_count": len(objects),
        "semantic_asset_count": semantic_count,
        "rule_element_count": rule_count,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a Cell_ppt manifest.json.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = audit(args.manifest)
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered, encoding="utf-8")
    sys.stdout.write(rendered)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
