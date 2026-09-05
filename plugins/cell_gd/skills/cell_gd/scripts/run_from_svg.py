#!/usr/bin/env python3
"""Cross-platform SVG-to-editable-PPTX wrapper for macOS."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run(*args: str):
    subprocess.run([sys.executable, *args], check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-svg", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--input-pptx", type=Path)
    parser.add_argument("--slide-index", type=int, default=0)
    parser.add_argument("--job-name")
    args = parser.parse_args()
    scripts = Path(__file__).resolve().parent
    allocator = scripts / "allocate_shibielujing_name.py"
    base_name = args.job_name or subprocess.check_output(
        [sys.executable, str(allocator), "--root", str(args.output_root.resolve())], text=True
    ).strip().splitlines()[-1]
    if not base_name.startswith("shibielujing") or not base_name[len("shibielujing"):].isdigit():
        raise SystemExit("job-name must use shibielujingN")
    job = args.output_root.resolve() / base_name
    cache_dir = job / ".cell-ppt-cache"
    output = job / f"{base_name}.pptx"
    job.mkdir(parents=True, exist_ok=True)
    run(str(scripts / "validate_vector_svg.py"), "--svg", str(args.input_svg.resolve()))
    run(
        str(scripts / "prepare_geometry_cache.py"),
        "--input", str(args.input_svg.resolve()),
        "--output-dir", str(cache_dir),
        "--job-id", base_name,
    )
    run(
        str(scripts / "cull_hidden_geometry.py"),
        "--cache", str(cache_dir / "geometry-cache.json"),
        "--state", str(cache_dir / "drawing-state.json"),
    )
    command = [
        str(scripts / "run_cell_ppt_ooxml.py"),
        "--geometry-cache", str(cache_dir / "geometry-cache.json"),
        "--output-pptx", str(output),
        "--slide-index", str(args.slide_index),
    ]
    if args.input_pptx:
        command.extend(["--input-pptx", str(args.input_pptx.resolve())])
    run(*command)
    print(json.dumps({"ok": True, "base_name": base_name, "pptx": str(output)}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
