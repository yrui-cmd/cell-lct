#!/usr/bin/env python3
"""Cross-platform original-image-to-editable-PPTX wrapper for macOS."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def run(*args: str):
    subprocess.run([sys.executable, *args], check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-image", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--input-pptx", type=Path)
    parser.add_argument("--slide-index", type=int, default=0)
    parser.add_argument("--estimated-credits", type=int, default=1)
    parser.add_argument("--approve-high-cost", action="store_true")
    args = parser.parse_args()
    scripts = Path(__file__).resolve().parent
    allocator = scripts / "allocate_shibielujing_name.py"
    base_name = subprocess.check_output(
        [sys.executable, str(allocator), "--root", str(args.output_root.resolve())], text=True
    ).strip().splitlines()[-1]
    job = args.output_root.resolve() / base_name
    job.mkdir(parents=True, exist_ok=True)
    raw_svg = job / f"{base_name}-vector.svg"
    master_svg = job / f"{base_name}.svg"
    vector_command = [
        str(scripts / "vectorize_xiaomiao.py"),
        "--input-image", str(args.input_image.resolve()),
        "--output-svg", str(raw_svg),
        "--estimated-credits", str(args.estimated_credits),
    ]
    if args.approve_high_cost:
        vector_command.append("--approve-high-cost")
    run(*vector_command)
    shutil.copyfile(raw_svg, master_svg)
    command = [
        str(scripts / "run_from_svg.py"),
        "--input-svg", str(master_svg),
        "--output-root", str(args.output_root.resolve()),
        "--slide-index", str(args.slide_index),
        "--job-name", base_name,
    ]
    if args.input_pptx:
        command.extend(["--input-pptx", str(args.input_pptx.resolve())])
    run(*command)
    print(json.dumps({"ok": True, "base_name": base_name, "master_svg": str(master_svg)}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
