#!/usr/bin/env python3
"""Cross-platform Xiaomiao adapter used by the macOS Cell_ppt workflow."""

from __future__ import annotations

import argparse
import json
import mimetypes
import platform
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


SERVICE = "cell-ppt-xiaomiao"


def get_token() -> str:
    if platform.system() != "Darwin":
        raise RuntimeError("Python credential lookup is supported on macOS; Windows uses xiaomiao.ps1 with DPAPI.")
    account = subprocess.run(["id", "-un"], check=True, text=True, capture_output=True).stdout.strip()
    proc = subprocess.run(
        ["security", "find-generic-password", "-s", SERVICE, "-a", account, "-w"],
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        raise RuntimeError("Xiaomiao API key is not configured. Codex must request it in chat and configure macOS Keychain automatically through standard input.")
    return proc.stdout.strip()


def request(method: str, url: str, *, token: str | None = None, data: bytes | None = None, content_type: str | None = None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            return response.status, response.read(), response.headers.get_content_type()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), exc.headers.get_content_type()


def json_body(body: bytes):
    try:
        return json.loads(body.decode("utf-8"))
    except Exception:
        return {"raw": body.decode("utf-8", errors="replace")}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["health", "verify", "upload", "status", "download"])
    parser.add_argument("--image-path", type=Path)
    parser.add_argument("--image-id")
    parser.add_argument("--output-path", type=Path)
    parser.add_argument("--base-url", default="https://xiaomiao-ai.com")
    args = parser.parse_args()
    root = args.base_url.rstrip("/")
    if args.action == "health":
        status, body, _ = request("GET", f"{root}/api/health")
        if status >= 400:
            raise SystemExit(f"Xiaomiao health check failed (HTTP {status}).")
        print(json.dumps(json_body(body), ensure_ascii=False))
        return 0

    token = get_token()
    try:
        if args.action == "verify":
            status, body, _ = request("GET", f"{root}/api/images/__codex_connection_probe__", token=token)
            if status == 404:
                print(json.dumps({"ok": True, "authenticated": True, "service": "xiaomiao", "credits_charged": 0}))
                return 0
            if status in (401, 403):
                raise SystemExit(f"Xiaomiao API-key authentication failed (HTTP {status}).")
            raise SystemExit(f"Unexpected authentication response (HTTP {status}): {json_body(body)}")

        if args.action == "upload":
            if not args.image_path:
                raise SystemExit("--image-path is required")
            image = args.image_path.expanduser().resolve()
            if image.stat().st_size > 10 * 1024 * 1024:
                raise SystemExit("The image exceeds Xiaomiao's 10 MB limit.")
            mime = mimetypes.guess_type(image.name)[0]
            if mime not in ("image/png", "image/jpeg", "image/webp"):
                raise SystemExit("Xiaomiao accepts PNG, JPEG, or WebP files.")
            boundary = f"cell-ppt-{uuid.uuid4().hex}"
            prefix = (
                f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{image.name}\"\r\n"
                f"Content-Type: {mime}\r\n\r\n"
            ).encode()
            payload = prefix + image.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
            status, body, _ = request(
                "POST",
                f"{root}/api/images",
                token=token,
                data=payload,
                content_type=f"multipart/form-data; boundary={boundary}",
            )
        elif args.action == "status":
            if not args.image_id:
                raise SystemExit("--image-id is required")
            safe_id = urllib.parse.quote(args.image_id, safe="")
            status, body, _ = request("GET", f"{root}/api/images/{safe_id}", token=token)
        else:
            if not args.image_id or not args.output_path:
                raise SystemExit("--image-id and --output-path are required")
            safe_id = urllib.parse.quote(args.image_id, safe="")
            status, body, content_type = request("GET", f"{root}/api/images/{safe_id}/file", token=token)
            if status == 410:
                status, body, content_type = request("GET", f"{root}/api/images/{safe_id}/result", token=token)
            if status >= 400:
                raise SystemExit(f"Download failed (HTTP {status}): {json_body(body)}")
            args.output_path.parent.mkdir(parents=True, exist_ok=True)
            args.output_path.write_bytes(body)
            print(json.dumps({"ok": True, "output_path": str(args.output_path.resolve()), "content_type": content_type}))
            return 0
        if status >= 400:
            raise SystemExit(f"Xiaomiao request failed (HTTP {status}): {json_body(body)}")
        print(json.dumps(json_body(body), ensure_ascii=False))
        return 0
    finally:
        token = ""


if __name__ == "__main__":
    raise SystemExit(main())
