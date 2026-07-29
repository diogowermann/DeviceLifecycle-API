from __future__ import annotations

import csv
import hmac
import io
import json
import logging
import os
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path, PureWindowsPath
from typing import Annotated, Any

from fastapi import FastAPI, Header, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse, Response


API_VERSION = "1.0.0"
SERVICE_NAME = "DeviceLifecycle-API"
SOURCE_SERVICE = "DeviceLifecycle"
CONFIG_ENVIRONMENT_VARIABLE = "DEVICE_LIFECYCLE_API_CONFIG"
KEY_ENVIRONMENT_VARIABLE = "DEVICE_LIFECYCLE_API_KEY"
DEFAULT_CONFIG_PATH = Path(r"C:\ProgramData\DeviceLifecycleApi\Api.Config.json")


@dataclass(frozen=True)
class Settings:
    organization_name: str
    source_service: str
    extension_name: str
    data_root: Path
    report_path: Path
    log_directory: Path
    api_log_directory: Path
    task_name: str
    listen_address: str
    port: int
    max_log_lines: int
    health_requires_authentication: bool


def _relative_windows_path(value: str) -> Path:
    windows_path = PureWindowsPath(value)
    if windows_path.is_absolute() or windows_path.drive or ".." in windows_path.parts:
        raise RuntimeError(f"Configured path must be relative and safe: {value}")
    return Path(*windows_path.parts)


def _load_settings() -> Settings:
    config_path = Path(
        os.environ.get(CONFIG_ENVIRONMENT_VARIABLE, str(DEFAULT_CONFIG_PATH))
    )

    if not config_path.is_file():
        raise RuntimeError(f"API configuration file was not found: {config_path}")

    with config_path.open("r", encoding="utf-8-sig") as config_file:
        raw: dict[str, Any] = json.load(config_file)

    required = (
        "organizationName",
        "sourceService",
        "extensionName",
        "dataRoot",
        "reportRelativePath",
        "logDirectoryRelativePath",
        "apiLogDirectory",
        "taskName",
        "listenAddress",
        "port",
        "maxLogLines",
        "healthRequiresAuthentication",
    )

    missing = [name for name in required if name not in raw]
    if missing:
        raise RuntimeError(
            "Missing API configuration properties: " + ", ".join(missing)
        )

    organization_name = str(raw["organizationName"]).strip()
    source_service = str(raw["sourceService"]).strip()
    extension_name = str(raw["extensionName"]).strip()
    data_root = Path(str(raw["dataRoot"]))
    report_path = data_root / _relative_windows_path(
        str(raw["reportRelativePath"])
    )
    log_directory = data_root / _relative_windows_path(
        str(raw["logDirectoryRelativePath"])
    )
    api_log_directory = Path(str(raw["apiLogDirectory"]))
    task_name = str(raw["taskName"]).strip()
    listen_address = str(raw["listenAddress"]).strip()
    port = int(raw["port"])
    max_log_lines = int(raw["maxLogLines"])
    health_requires_authentication = bool(raw["healthRequiresAuthentication"])

    for name, value in (
        ("organizationName", organization_name),
        ("sourceService", source_service),
        ("extensionName", extension_name),
        ("taskName", task_name),
        ("listenAddress", listen_address),
    ):
        if not value:
            raise RuntimeError(f"{name} cannot be empty.")

    if port < 1 or port > 65535:
        raise RuntimeError("port must be between 1 and 65535.")
    if max_log_lines < 1 or max_log_lines > 100000:
        raise RuntimeError("maxLogLines must be between 1 and 100000.")

    api_log_directory.mkdir(parents=True, exist_ok=True)

    return Settings(
        organization_name=organization_name,
        source_service=source_service,
        extension_name=extension_name,
        data_root=data_root,
        report_path=report_path,
        log_directory=log_directory,
        api_log_directory=api_log_directory,
        task_name=task_name,
        listen_address=listen_address,
        port=port,
        max_log_lines=max_log_lines,
        health_requires_authentication=health_requires_authentication,
    )


def _load_api_key() -> str:
    api_key = os.environ.get(KEY_ENVIRONMENT_VARIABLE, "").strip()
    if not api_key:
        raise RuntimeError(
            f"Environment variable {KEY_ENVIRONMENT_VARIABLE} is not configured."
        )
    if len(api_key) < 32:
        raise RuntimeError("The configured API key must contain at least 32 characters.")
    return api_key


SETTINGS = _load_settings()
API_KEY = _load_api_key()

LOGGER = logging.getLogger("device_lifecycle_api")
LOGGER.setLevel(logging.INFO)
LOGGER.propagate = False

if not LOGGER.handlers:
    log_handler = RotatingFileHandler(
        SETTINGS.api_log_directory / "DeviceLifecycleApi.log",
        maxBytes=5 * 1024 * 1024,
        backupCount=5,
        encoding="utf-8",
    )
    log_handler.setFormatter(
        logging.Formatter(
            "%(asctime)s [%(levelname)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )
    LOGGER.addHandler(log_handler)


app = FastAPI(
    title=f"{SETTINGS.organization_name} Device Lifecycle API",
    description=(
        "Read-only HTTP extension for reports and logs produced by "
        f"{SETTINGS.source_service}."
    ),
    version=API_VERSION,
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


def _utc_iso(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()


def _verify_api_key(received_key: str | None) -> None:
    if not received_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="X-API-Key header was not provided.",
        )

    if not hmac.compare_digest(received_key, API_KEY):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid API key.",
        )


def _read_stable_bytes(path: Path, attempts: int = 4) -> bytes:
    if not path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"File was not found: {path.name}",
        )

    last_error: OSError | None = None

    for attempt in range(attempts):
        try:
            before = path.stat()
            content = path.read_bytes()
            after = path.stat()

            if (
                before.st_size == after.st_size
                and before.st_mtime_ns == after.st_mtime_ns
            ):
                return content
        except OSError as error:
            last_error = error

        if attempt < attempts - 1:
            time.sleep(0.1)

    detail = (
        str(last_error)
        if last_error is not None
        else "The file changed while it was being read."
    )

    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=f"Unable to read a stable file snapshot: {detail}",
    )


def _latest_log_path() -> Path:
    if not SETTINGS.log_directory.is_dir():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="DeviceLifecycle log directory was not found.",
        )

    candidates = [
        item for item in SETTINGS.log_directory.glob("*.log") if item.is_file()
    ]

    if not candidates:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No DeviceLifecycle log file was found.",
        )

    return max(candidates, key=lambda item: item.stat().st_mtime_ns)


def _file_metadata(path: Path) -> dict[str, Any]:
    metadata = path.stat()
    return {
        "fileName": path.name,
        "sizeBytes": metadata.st_size,
        "lastModifiedUtc": _utc_iso(metadata.st_mtime),
    }


def _service_metadata() -> dict[str, Any]:
    return {
        "service": SETTINGS.extension_name,
        "apiVersion": API_VERSION,
        "extensionOf": SETTINGS.source_service,
        "organizationName": SETTINGS.organization_name,
        "readOnly": True,
    }


@app.middleware("http")
async def request_logging(request: Request, call_next):
    started = time.perf_counter()
    client_host = request.client.host if request.client else "unknown"

    try:
        response = await call_next(request)
    except Exception:
        elapsed_ms = (time.perf_counter() - started) * 1000
        LOGGER.exception(
            "%s %s client=%s status=500 durationMs=%.2f",
            request.method,
            request.url.path,
            client_host,
            elapsed_ms,
        )
        raise

    elapsed_ms = (time.perf_counter() - started) * 1000
    LOGGER.info(
        "%s %s client=%s status=%s durationMs=%.2f",
        request.method,
        request.url.path,
        client_host,
        response.status_code,
        elapsed_ms,
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-DeviceLifecycle-API-Version"] = API_VERSION
    return response


@app.exception_handler(HTTPException)
async def http_exception_handler(
    request: Request,
    exception: HTTPException,
) -> JSONResponse:
    return JSONResponse(
        status_code=exception.status_code,
        content={"detail": exception.detail},
        headers=exception.headers,
    )


@app.get("/api/v1/health")
def health(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> dict[str, Any]:
    if SETTINGS.health_requires_authentication:
        _verify_api_key(x_api_key)

    report_available = SETTINGS.report_path.is_file()

    try:
        log_path = _latest_log_path()
        log_available = True
    except HTTPException:
        log_path = None
        log_available = False

    return {
        **_service_metadata(),
        "status": "ok",
        "serverTimeUtc": datetime.now(timezone.utc).isoformat(),
        "reportAvailable": report_available,
        "latestLogAvailable": log_available,
        "latestLogName": log_path.name if log_path else None,
    }


@app.get("/api/v1/report.csv")
def report_csv(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> Response:
    _verify_api_key(x_api_key)
    content = _read_stable_bytes(SETTINGS.report_path)
    metadata = _file_metadata(SETTINGS.report_path)

    return Response(
        content=content,
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": (
                f'inline; filename="{SETTINGS.report_path.name}"'
            ),
            "X-File-Name": metadata["fileName"],
            "X-File-Size": str(metadata["sizeBytes"]),
            "X-File-Last-Modified-Utc": metadata["lastModifiedUtc"],
        },
    )


@app.get("/api/v1/report")
def report_json(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> dict[str, Any]:
    _verify_api_key(x_api_key)
    raw_content = _read_stable_bytes(SETTINGS.report_path)

    try:
        text = raw_content.decode("utf-8-sig")
        records = list(csv.DictReader(io.StringIO(text, newline="")))
    except (UnicodeDecodeError, csv.Error) as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unable to parse the current CSV report: {error}",
        ) from error

    metadata = _file_metadata(SETTINGS.report_path)
    return {
        **_service_metadata(),
        **metadata,
        "recordCount": len(records),
        "records": records,
    }


@app.get("/api/v1/log")
def log_tail(
    lines: Annotated[int, Query(ge=1)] = 500,
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> Response:
    _verify_api_key(x_api_key)

    if lines > SETTINGS.max_log_lines:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"lines cannot exceed {SETTINGS.max_log_lines}.",
        )

    log_path = _latest_log_path()
    content = _read_stable_bytes(log_path)
    text = content.decode("utf-8-sig", errors="replace")
    selected = text.splitlines()[-lines:]
    metadata = _file_metadata(log_path)

    return Response(
        content="\n".join(selected),
        media_type="text/plain; charset=utf-8",
        headers={
            "X-Log-File": metadata["fileName"],
            "X-File-Size": str(metadata["sizeBytes"]),
            "X-File-Last-Modified-Utc": metadata["lastModifiedUtc"],
        },
    )


@app.get("/api/v1/log/file")
def log_file(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> Response:
    _verify_api_key(x_api_key)
    log_path = _latest_log_path()
    content = _read_stable_bytes(log_path)
    metadata = _file_metadata(log_path)

    return Response(
        content=content,
        media_type="text/plain; charset=utf-8",
        headers={
            "Content-Disposition": f'inline; filename="{log_path.name}"',
            "X-Log-File": metadata["fileName"],
            "X-File-Size": str(metadata["sizeBytes"]),
            "X-File-Last-Modified-Utc": metadata["lastModifiedUtc"],
        },
    )


@app.get("/api/v1/metadata")
def metadata(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> dict[str, Any]:
    _verify_api_key(x_api_key)

    report_metadata = (
        _file_metadata(SETTINGS.report_path)
        if SETTINGS.report_path.is_file()
        else None
    )

    try:
        latest_log = _latest_log_path()
        log_metadata = _file_metadata(latest_log)
    except HTTPException:
        log_metadata = None

    return {
        **_service_metadata(),
        "report": report_metadata,
        "latestLog": log_metadata,
    }
