#!/usr/bin/env python3
"""macOS Xiaomiao vectorization wrapper with pre-upload credit gate."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path


def call(adapter: Path, action: str, *extra: str):
    proc = subprocess.run([sys.executable, str(adapter), action, *extra], text=True, capture_output=True)
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"{action} failed")
    return json.loads(proc.stdout)



def balance_message(value):
    """Only display a non-negative finite server-provided credit balance."""
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0:
        return f"剩余额度：{value}"
    return "剩余额度：暂不可用"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-image", required=True, type=Path)
    parser.add_argument("--output-svg", required=True, type=Path)
    parser.add_argument("--estimated-credits", type=int, default=1)
    parser.add_argument("--approve-high-cost", action="store_true")
    parser.add_argument("--poll-seconds", type=int, default=5)
    parser.add_argument("--timeout-seconds", type=int, default=900)
    args = parser.parse_args()
    if args.estimated_credits > 1 and not args.approve_high_cost:
        raise SystemExit(f"CREDIT_CONFIRM_REQUIRED|estimated={args.estimated_credits}|threshold=1")
    adapter = Path(__file__).with_name("xiaomiao.py")
    verification = call(adapter, "verify")
    if not verification.get("authenticated"):
        raise SystemExit("Xiaomiao authentication could not be verified.")
    submission = call(adapter, "upload", "--image-path", str(args.input_image.resolve()))
    image_id = str(submission.get("image_id") or "")
    if not image_id:
        raise SystemExit("Xiaomiao did not return an image id.")
    deadline = time.monotonic() + args.timeout_seconds
    job = None
    while time.monotonic() < deadline:
        job = call(adapter, "status", "--image-id", image_id)
        status = str(job.get("status") or "")
        if status == "completed":
            break
        if status in {"failed", "expired", "rejected"}:
            raise SystemExit(f"Xiaomiao job ended with status: {status}")
        time.sleep(args.poll_seconds)
    if not job or job.get("status") != "completed":
        raise SystemExit("Xiaomiao job timed out.")
    print(balance_message(job.get("credits_left")), file=sys.stderr)
    args.output_svg.parent.mkdir(parents=True, exist_ok=True)
    call(adapter, "download", "--image-id", image_id, "--output-path", str(args.output_svg.resolve()))
    validator = Path(__file__).with_name("validate_vector_svg.py")
    subprocess.run([sys.executable, str(validator), "--svg", str(args.output_svg.resolve())], check=True)
    print(json.dumps({
        "ok": True,
        "image_id": image_id,
        "output_svg": str(args.output_svg.resolve()),
        "credits_left": job.get("credits_left"),
    }, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
