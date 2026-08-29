"""Portable command-line client for an OpenAI-compatible Image 2 relay."""

from __future__ import annotations

import argparse
import base64
import http.client
import json
import mimetypes
import os
import secrets
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from queue import Empty, SimpleQueue


DEFAULT_MODEL = "gpt-image-2"
DEFAULT_SIZE = "1536x1024"
DEFAULT_QUALITY = "standard"
ALLOWED_MODELS = {"gpt-image-1", "gpt-image-1.5", "gpt-image-2"}
ALLOWED_SIZES = {"1024x1024", "1536x1024", "1024x1536"}
ALLOWED_QUALITIES = {"low", "standard", "high"}
MAX_REFERENCE_BYTES = 10 * 1024 * 1024
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_GENERATION_COUNT = 10
MAX_BATCH_PROMPT_COUNT = 4
MAX_RESPONSE_BYTES = MAX_IMAGE_BYTES * MAX_GENERATION_COUNT * 4 // 3 + 64 * 1024
TIMEOUT_SECONDS = 600
MAX_TASK_POLL_ATTEMPTS = 60
TASK_POLL_INTERVAL_SECONDS = 1
RETRYABLE_NETWORK_ERROR_CATEGORIES = {
    "DNS 解析失败",
    "TLS 连接失败",
    "连接被拒绝",
    "代理连接失败",
}
RETRY_NOTICE_PREFIX = "RETRY_NOTICE:"
_RETRY_NOTICES: SimpleQueue[str] = SimpleQueue()


class _RejectRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.URLError("unsafe redirect")


_NO_REDIRECT_OPENER = urllib.request.build_opener(_RejectRedirectHandler())


def _open_url(request: urllib.request.Request, timeout: int):
    return _NO_REDIRECT_OPENER.open(request, timeout=timeout)


class Settings:
    def __init__(self, api_key: str, base_url: str):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    @classmethod
    def from_environment(cls) -> "Settings":
        api_key = os.environ.get("CELL_LCT_IMAGE_API_KEY", "").strip()
        if not api_key:
            raise RuntimeError("未设置 CELL_LCT_IMAGE_API_KEY 环境变量。")
        base_url = os.environ.get("CELL_LCT_IMAGE_BASE_URL", "").strip()
        if not base_url:
            raise RuntimeError("未设置 CELL_LCT_IMAGE_BASE_URL 环境变量。")
        parsed = urllib.parse.urlsplit(base_url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc or parsed.query or parsed.fragment:
            raise RuntimeError("CELL_LCT_IMAGE_BASE_URL 必须是有效的 HTTP(S) 地址。")
        return cls(api_key, base_url)


@dataclass(frozen=True)
class BatchItemResult:
    path: Path | None = None
    error: str | None = None


def _select(value: str | None, allowed: set[str], default: str, label: str) -> str:
    selected = value or default
    if selected not in allowed:
        raise ValueError(f"不支持的{label}: {selected}")
    return selected


def _select_count(count: int) -> int:
    if not 1 <= count <= MAX_GENERATION_COUNT:
        raise ValueError("生成数量必须在 1 到 10 之间。")
    return count


def build_generation_request(
    prompt: str,
    model: str | None = None,
    size: str | None = None,
    quality: str | None = None,
    count: int = 1,
) -> dict[str, object]:
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("提示词不能为空。")
    return {
        "model": _select(model, ALLOWED_MODELS, DEFAULT_MODEL, "模型"),
        "prompt": prompt,
        "size": _select(size, ALLOWED_SIZES, DEFAULT_SIZE, "尺寸"),
        "quality": _select(quality, ALLOWED_QUALITIES, DEFAULT_QUALITY, "质量"),
        "n": _select_count(count),
        "stream": True,
        "partial_images": 1,
    }


def build_text_prompt(
    text: str,
    description: str,
    language: str | None = None,
    position: str | None = None,
    style: str | None = None,
) -> str:
    if not text or not text.strip() or not description or not description.strip():
        raise ValueError("指定文字和画面描述不能为空。")
    return (
        f"{description.strip()}\n\n"
        f'图片中必须完整呈现以下文字："{text.strip()}"。文字必须逐字准确、清晰可读、完整显示，'
        "不得添加未要求的文字。\n"
        f"文字语言：{language or '自动识别'}。\n"
        f"文字位置：{position or '由构图决定'}。\n"
        f"文字样式：{style or '与视觉主题协调'}。"
    )


def _headers(settings: Settings) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {settings.api_key}",
        "User-Agent": "CellLctImageSkill/1.0",
    }


def _network_error_category(reason: object) -> str:
    if isinstance(reason, socket.gaierror):
        return "DNS 解析失败"
    if isinstance(reason, ssl.SSLError):
        return "TLS 连接失败"
    if isinstance(reason, ConnectionRefusedError):
        return "连接被拒绝"
    if isinstance(reason, (TimeoutError, socket.timeout)):
        return "网络连接超时"

    text = str(reason).lower()
    if "proxy" in text:
        return "代理连接失败"
    if "tls" in text or "ssl" in text:
        return "TLS 连接失败"
    if "refused" in text:
        return "连接被拒绝"
    if "timeout" in text or "timed out" in text:
        return "网络连接超时"
    return "网络连接失败"


def _record_retry_notice(category: str) -> None:
    notice = f"{RETRY_NOTICE_PREFIX} 首次调用失败：{category}；已自动重试 1 次。"
    _RETRY_NOTICES.put(notice)
    print(notice, file=sys.stderr)


def _take_retry_notices() -> list[str]:
    notices: list[str] = []
    while True:
        try:
            notices.append(_RETRY_NOTICES.get_nowait())
        except Empty:
            return notices


def _send(method: str, url: str, headers: dict[str, str], body: bytes = b"") -> tuple[int, dict[str, str], bytes]:
    regular_headers = {
        key: value for key, value in headers.items() if key.lower() != "authorization"
    }
    request = urllib.request.Request(url=url, data=body, headers=regular_headers, method=method)
    for key, value in headers.items():
        if key.lower() == "authorization":
            request.add_unredirected_header(key, value)

    def read_response(response, status: int) -> tuple[int, dict[str, str], bytes]:
        geturl = getattr(response, "geturl", None)
        final_url = geturl() if callable(geturl) else request.full_url
        if isinstance(final_url, str) and final_url != request.full_url:
            raise urllib.error.URLError("unsafe redirect")
        try:
            body_bytes = response.read(MAX_RESPONSE_BYTES + 1)
        except (ConnectionError, OSError, TimeoutError, http.client.HTTPException) as error:
            raise urllib.error.URLError(error) from error
        return status, dict(response.headers.items()), body_bytes

    def send_once() -> tuple[int, dict[str, str], bytes]:
        try:
            with _open_url(request, timeout=TIMEOUT_SECONDS) as response:
                return read_response(response, response.status)
        except urllib.error.HTTPError as error:
            return read_response(error, error.code)
        except urllib.error.URLError:
            raise
        except (ConnectionError, OSError, TimeoutError, http.client.HTTPException) as error:
            raise urllib.error.URLError(error) from error

    try:
        return send_once()
    except urllib.error.URLError as first_error:
        first_category = _network_error_category(first_error.reason)
        if method.upper() != "GET":
            raise RuntimeError(
                f"调用图像服务时发生{first_category}，生成状态未知，创建请求未自动重试。"
            ) from first_error
        if first_category not in RETRYABLE_NETWORK_ERROR_CATEGORIES:
            raise RuntimeError(
                f"读取图像服务时发生{first_category}，读取失败，未自动重试。"
            ) from first_error

    try:
        result = send_once()
    except urllib.error.URLError as second_error:
        second_category = _network_error_category(second_error.reason)
        raise RuntimeError(
            f"读取图像服务首次发生{first_category}；自动重试后发生{second_category}，读取失败。"
        ) from second_error

    _record_retry_notice(first_category)
    return result


def _extract_images(payload: object) -> list[dict[str, object]]:
    if isinstance(payload, list):
        images: list[dict[str, object]] = []
        for item in payload:
            images.extend(_extract_images(item))
        return images
    if not isinstance(payload, dict):
        return []
    if isinstance(payload.get("b64_json"), str) or isinstance(payload.get("url"), str):
        return [payload]
    images = _extract_images(payload.get("data"))
    for key in ("image", "result", "output"):
        images.extend(_extract_images(payload.get(key)))
    return images


def _decode_sse(body: bytes) -> list[dict[str, object]]:
    images: list[dict[str, object]] = []
    for event in body.decode("utf-8").replace("\r\n", "\n").split("\n\n"):
        data = "\n".join(line[5:].lstrip() for line in event.splitlines() if line.startswith("data:"))
        if not data or data == "[DONE]":
            continue
        try:
            payload = json.loads(data)
        except json.JSONDecodeError:
            continue
        event_type = str(payload.get("type", "")).lower() if isinstance(payload, dict) else ""
        if "partial" not in event_type:
            images.extend(_extract_images(payload))
    if not images:
        raise RuntimeError("图像服务的流式响应中没有最终图像。")
    return images


def _decode_images(body: bytes, content_type: str) -> list[dict[str, object]]:
    if content_type.lower().startswith("text/event-stream"):
        return _decode_sse(body)
    try:
        images = _extract_images(json.loads(body.decode("utf-8")))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("图像服务响应无法解析。") from error
    if not images:
        raise RuntimeError("图像服务响应中没有可保存的图像。")
    return images


def _save_png(image_bytes: bytes, output_dir: Path) -> Path:
    if not image_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("图像服务返回的内容不是 PNG 图像。")
    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise RuntimeError("生成图像文件过大。")
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"cell-lct-image-{secrets.token_hex(12)}.png"
    path.write_bytes(image_bytes)
    return path.resolve()


def _save_response_item(image: dict[str, object], output_dir: Path, settings: Settings | None) -> Path:
    encoded = image.get("b64_json")
    if isinstance(encoded, str):
        try:
            return _save_png(base64.b64decode(encoded, validate=True), output_dir)
        except (ValueError, TypeError) as error:
            raise RuntimeError("图像服务返回的 base64 数据无效。") from error
    url = image.get("url")
    if not isinstance(url, str) or settings is None:
        raise RuntimeError("图像服务响应中没有可保存的图像。")
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise RuntimeError("生成图像 URL 必须使用 HTTP(S)。")
    status, headers, image_bytes = _send("GET", url, {})
    if not 200 <= status < 300 or not headers.get("Content-Type", "").lower().startswith("image/png"):
        raise RuntimeError("下载生成图像失败。")
    return _save_png(image_bytes, output_dir)


def save_response_images(
    body: bytes,
    content_type: str,
    output_dir: Path,
    settings: Settings | None = None,
) -> list[Path]:
    return [_save_response_item(image, output_dir, settings) for image in _decode_images(body, content_type)]


def save_response_image(body: bytes, content_type: str, output_dir: Path, settings: Settings | None = None) -> Path:
    return save_response_images(body, content_type, output_dir, settings)[0]


def _task_location(headers: dict[str, str], settings: Settings) -> str:
    location = next((value for key, value in headers.items() if key.lower() == "location"), None)
    if not isinstance(location, str) or not location.strip():
        raise RuntimeError("图像服务返回了异步任务，但没有任务地址。")
    location = location.strip()
    if location.startswith("//"):
        raise RuntimeError("图像服务返回了不安全的任务地址。")

    task_url = urllib.parse.urljoin(f"{settings.base_url.rstrip('/')}/", location)
    try:
        parsed = urllib.parse.urlsplit(task_url)
        base = urllib.parse.urlsplit(settings.base_url)
    except ValueError as error:
        raise RuntimeError("图像服务返回了不安全的任务地址。") from error

    decoded_path = urllib.parse.unquote(parsed.path)
    namespace = f"{urllib.parse.unquote(base.path).rstrip('/')}/"
    base_scheme = base.scheme
    default_port = 443 if base_scheme == "https" else 80
    task_port = parsed.port if parsed.port is not None else (443 if parsed.scheme == "https" else 80)
    base_port = base.port if base.port is not None else default_port
    if (
        parsed.scheme != base_scheme
        or parsed.hostname != base.hostname
        or task_port != base_port
        or parsed.username is not None
        or parsed.password is not None
        or bool(parsed.fragment)
        or "\\" in decoded_path
        or any(segment in {".", ".."} for segment in decoded_path.split("/"))
        or not decoded_path.startswith(namespace)
    ):
        raise RuntimeError("图像服务返回了不安全的任务地址。")
    return task_url


def _task_status(body: bytes) -> str:
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return ""
    if not isinstance(payload, dict):
        return ""
    if isinstance(payload.get("status"), str):
        return payload["status"].lower()
    data = payload.get("data")
    if isinstance(data, dict) and isinstance(data.get("status"), str):
        return data["status"].lower()
    return ""


def _wait_for_task(task_url: str, settings: Settings, output_dir: Path) -> list[Path]:
    pending_statuses = {"queued", "pending", "processing", "running", "in_progress"}
    failed_statuses = {"failure", "failed", "error", "cancelled"}
    for attempt in range(MAX_TASK_POLL_ATTEMPTS):
        status, headers, response = _send("GET", task_url, _headers(settings))
        if not 200 <= status < 300:
            raise RuntimeError(f"图像任务查询返回 HTTP {status}。")
        try:
            return save_response_images(response, headers.get("Content-Type", ""), output_dir, settings)
        except RuntimeError as error:
            task_status = _task_status(response)
            if task_status in failed_statuses:
                raise RuntimeError(f"图像任务失败: {task_status}。") from error
            if task_status not in pending_statuses:
                raise
        if attempt + 1 < MAX_TASK_POLL_ATTEMPTS:
            time.sleep(TASK_POLL_INTERVAL_SECONDS)
    raise RuntimeError("图像任务在等待期间未完成。")


def _is_supported_image(path: Path) -> bool:
    signature = path.read_bytes()[:12]
    return signature.startswith(b"\x89PNG\r\n\x1a\n") or signature.startswith(b"\xff\xd8\xff") or signature.startswith((b"GIF87a", b"GIF89a")) or (signature.startswith(b"RIFF") and signature[8:12] == b"WEBP")


def build_edit_request(
    prompt: str,
    references: list[Path],
    model: str | None,
    size: str | None,
    quality: str | None,
    count: int = 1,
) -> tuple[bytes, str]:
    payload = build_generation_request(prompt, model, size, quality, count)
    payload.pop("stream")
    payload.pop("partial_images")
    if not references:
        raise ValueError("至少需要提供一张参考图。")
    boundary = f"----CellLctImage{secrets.token_hex(16)}"
    chunks: list[bytes] = []
    for name, value in payload.items():
        chunks.extend([f"--{boundary}\r\n".encode(), f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(), str(value).encode("utf-8"), b"\r\n"])
    for path in references:
        if not path.is_absolute() or not path.is_file():
            raise ValueError(f"参考图必须是存在的绝对路径: {path}")
        if path.stat().st_size > MAX_REFERENCE_BYTES or not _is_supported_image(path):
            raise ValueError(f"参考图格式不支持或文件过大: {path}")
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        chunks.extend([f"--{boundary}\r\n".encode(), f'Content-Disposition: form-data; name="image[]"; filename="{path.name}"\r\n'.encode(), f"Content-Type: {mime}\r\n\r\n".encode(), path.read_bytes(), b"\r\n"])
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def _request_images(endpoint: str, body: bytes, content_type: str, settings: Settings, output_dir: Path) -> list[Path]:
    status, headers, response = _send("POST", f"{settings.base_url}{endpoint}", {**_headers(settings), "Content-Type": content_type}, body)
    if not 200 <= status < 300:
        raise RuntimeError(f"图像服务返回 HTTP {status}。")
    if status == 202:
        return _wait_for_task(_task_location(headers, settings), settings, output_dir)
    return save_response_images(response, headers.get("Content-Type", ""), output_dir, settings)


def _request_image(endpoint: str, body: bytes, content_type: str, settings: Settings, output_dir: Path) -> Path:
    return _request_images(endpoint, body, content_type, settings, output_dir)[0]


def generate(prompt: str, model: str | None, size: str | None, quality: str | None, count: int, output_dir: Path) -> list[Path]:
    settings = Settings.from_environment()
    payload = build_generation_request(prompt, model, size, quality, count)
    return _request_images("/images/generations", json.dumps(payload, ensure_ascii=False).encode("utf-8"), "application/json", settings, output_dir)


def edit(prompt: str, references: list[Path], model: str | None, size: str | None, quality: str | None, count: int, output_dir: Path) -> list[Path]:
    settings = Settings.from_environment()
    body, content_type = build_edit_request(prompt, references, model, size, quality, count)
    return _request_images("/images/edits", body, content_type, settings, output_dir)


def generate_batch(
    prompts: list[str],
    model: str | None,
    size: str | None,
    quality: str | None,
    output_dir: Path,
) -> list[BatchItemResult]:
    if not 2 <= len(prompts) <= MAX_BATCH_PROMPT_COUNT:
        raise ValueError("批量提示词数量必须在 2 到 4 之间。")
    if any(not isinstance(prompt, str) or not prompt.strip() for prompt in prompts):
        raise ValueError("批量提示词不能为空。")

    def run(prompt: str) -> BatchItemResult:
        try:
            paths = generate(prompt, model, size, quality, 1, output_dir)
            if not paths:
                return BatchItemResult(error="图像服务未返回图片。")
            return BatchItemResult(path=paths[0])
        except (OSError, RuntimeError, ValueError) as error:
            return BatchItemResult(error=str(error))

    with ThreadPoolExecutor(max_workers=len(prompts)) as executor:
        futures = [executor.submit(run, prompt) for prompt in prompts]
        return [future.result() for future in futures]


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Cell-lct Image 2 绘图客户端")
    subcommands = parser.add_subparsers(dest="command", required=True)
    for command in ("generate", "edit", "text"):
        current = subcommands.add_parser(command)
        current.add_argument("--model", choices=sorted(ALLOWED_MODELS))
        current.add_argument("--size", choices=sorted(ALLOWED_SIZES))
        current.add_argument("--quality", choices=sorted(ALLOWED_QUALITIES))
        current.add_argument("--output-dir", type=Path, default=Path.cwd() / "output")
        current.add_argument("--result-file", type=Path)
        current.add_argument("--count", type=int, choices=range(1, MAX_GENERATION_COUNT + 1), default=1)
    subcommands.choices["generate"].add_argument("--prompt", required=True)
    subcommands.choices["edit"].add_argument("--prompt", required=True)
    subcommands.choices["edit"].add_argument("--reference", type=Path, action="append", required=True)
    subcommands.choices["text"].add_argument("--text", required=True)
    subcommands.choices["text"].add_argument("--description", required=True)
    subcommands.choices["text"].add_argument("--language")
    subcommands.choices["text"].add_argument("--position")
    subcommands.choices["text"].add_argument("--style")
    batch_parser = subcommands.add_parser("batch")
    batch_parser.add_argument("--model", choices=sorted(ALLOWED_MODELS))
    batch_parser.add_argument("--size", choices=sorted(ALLOWED_SIZES))
    batch_parser.add_argument("--quality", choices=sorted(ALLOWED_QUALITIES))
    batch_parser.add_argument("--output-dir", type=Path, default=Path.cwd() / "output")
    batch_parser.add_argument("--result-file", type=Path)
    batch_parser.add_argument("--prompt", action="append", required=True)
    return parser


def _missing_result_errors(paths: list[Path], expected_count: int) -> list[str]:
    return [
        f"批次项 {index} 失败: 图像服务未返回该图片。"
        for index in range(len(paths) + 1, expected_count + 1)
    ]


def _result_errors(paths: list[Path], expected_count: int) -> list[str]:
    errors = _missing_result_errors(paths, expected_count)
    if len(paths) > expected_count:
        errors.append(
            f"图像服务返回了超出请求数量的图片：请求 {expected_count} 张，实际 {len(paths)} 张。"
        )
    return errors


def _batch_result_data(results: list[BatchItemResult]) -> tuple[list[Path], list[str]]:
    paths: list[Path] = []
    errors: list[str] = []
    for index, result in enumerate(results, start=1):
        if result.path is not None:
            paths.append(result.path)
        else:
            errors.append(f"批次项 {index} 失败: {result.error or '未知错误'}")
    return paths, errors


def _print_results(paths: list[Path], expected_count: int) -> int:
    for path in paths:
        print(path)
    errors = _result_errors(paths, expected_count)
    for error in errors:
        print(error, file=sys.stderr)
    return 0 if len(paths) == expected_count else 1


def _print_batch_results(results: list[BatchItemResult]) -> int:
    paths, errors = _batch_result_data(results)
    for path in paths:
        print(path)
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


def _write_result_receipt(
    result_file: Path | None,
    exit_code: int,
    paths: list[Path],
    errors: list[str],
) -> None:
    if result_file is None:
        return
    if not result_file.is_absolute():
        raise ValueError("结果回执文件必须使用绝对路径。")
    status = "success" if exit_code == 0 else "partial" if paths else "error"
    payload = {
        "version": 1,
        "status": status,
        "exit_code": exit_code,
        "paths": [str(path) for path in paths],
        "errors": errors,
    }
    result_file.parent.mkdir(parents=True, exist_ok=True)
    temporary = result_file.with_name(f".{result_file.name}.{secrets.token_hex(4)}.tmp")
    try:
        temporary.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        temporary.replace(result_file)
    finally:
        temporary.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    _take_retry_notices()
    if arguments.result_file is not None and not arguments.result_file.is_absolute():
        print("结果回执文件必须使用绝对路径。", file=sys.stderr)
        return 1
    paths: list[Path] = []
    errors: list[str] = []
    try:
        if arguments.command == "batch":
            results = generate_batch(arguments.prompt, arguments.model, arguments.size, arguments.quality, arguments.output_dir)
            paths, errors = _batch_result_data(results)
            errors = _take_retry_notices() + errors
            exit_code = _print_batch_results(results)
        else:
            if arguments.command == "generate":
                paths = generate(arguments.prompt, arguments.model, arguments.size, arguments.quality, arguments.count, arguments.output_dir)
            elif arguments.command == "edit":
                paths = edit(arguments.prompt, arguments.reference, arguments.model, arguments.size, arguments.quality, arguments.count, arguments.output_dir)
            else:
                prompt = build_text_prompt(arguments.text, arguments.description, arguments.language, arguments.position, arguments.style)
                paths = generate(prompt, arguments.model, arguments.size, arguments.quality, arguments.count, arguments.output_dir)
            errors = _take_retry_notices() + _result_errors(paths, arguments.count)
            exit_code = _print_results(paths, arguments.count)
    except (OSError, RuntimeError, ValueError) as error:
        errors = _take_retry_notices() + [str(error)]
        print(str(error), file=sys.stderr)
        exit_code = 1
    try:
        _write_result_receipt(arguments.result_file, exit_code, paths, errors)
    except (OSError, ValueError) as error:
        print(f"写入结果回执失败: {error}", file=sys.stderr)
        return 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
