import argparse
import base64
import contextlib
import hashlib
import html
import json
import logging
import mimetypes
import os
import signal
import secrets as secretlib
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlencode, urlparse

import requests


LOG = logging.getLogger("immich-nsfw-guard")
SCAN_POLICY_VERSION = 4
ACTIVE_REVIEW_STATES = (
    "pending",
    "quarantining",
    "quarantine_failed",
    "moving",
    "move_failed",
    "locking",
    "lock_failed",
    "keeping",
    "keep_failed",
    "undoing",
)
ACTIONABLE_REVIEW_STATES = (
    "pending",
    "move_failed",
    "lock_failed",
    "keep_failed",
)
HISTORY_REVIEW_STATES = (
    "kept",
    "moved",
    "locked",
    "undone",
    "undo_failed",
)
FAVICON_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="108 70 592 592"><path fill="#FA2921" d="M375.48,267.63c38.64,34.21,69.78,70.87,89.82,105.42c34.42-61.56,57.42-134.71,57.71-181.3c0-0.33,0-0.63,0-0.91c0-68.94-68.77-95.77-128.01-95.77s-128.01,26.83-128.01,95.77c0,0.94,0,2.2,0,3.72C300.01,209.24,339.15,235.47,375.48,267.63z"/><path fill="#ED79B5" d="M164.7,455.63c24.15-26.87,61.2-55.99,103.01-80.61c44.48-26.18,88.97-44.47,128.02-52.84c-47.91-51.76-110.37-96.24-154.6-110.91c-0.31-0.1-0.6-0.19-0.86-0.28c-65.57-21.3-112.34,35.81-130.64,92.15c-18.3,56.34-14.04,130.04,51.53,151.34C162.05,454.77,163.25,455.16,164.7,455.63z"/><path fill="#FFB400" d="M681.07,302.19c-18.3-56.34-65.07-113.45-130.64-92.15c-0.9,0.29-2.1,0.68-3.54,1.15c-3.75,35.93-16.6,81.27-35.96,125.76c-20.59,47.32-45.84,88.27-72.51,118c69.18,13.72,145.86,12.98,190.26-1.14c0.31-0.1,0.6-0.2,0.86-0.28C695.11,432.22,699.37,358.52,681.07,302.19z"/><path fill="#1E83F7" d="M336.54,510.71c-11.15-50.39-14.8-98.36-10.7-138.08c-64.03,29.57-125.63,75.23-153.26,112.76c-0.19,0.26-0.37,0.51-0.53,0.73c-40.52,55.78-0.66,117.91,47.27,152.72c47.92,34.82,119.33,53.54,159.86-2.24c0.56-0.76,1.3-1.78,2.19-3.01C363.28,602.32,347.02,558.08,336.54,510.71z"/><path fill="#18C249" d="M617.57,482.52c-35.33,7.54-82.42,9.33-130.72,4.66c-51.37-4.96-98.11-16.32-134.63-32.5c8.33,70.03,32.73,142.73,59.88,180.6c0.19,0.26,0.37,0.51,0.53,0.73c40.52,55.78,111.93,37.06,159.86,2.24c47.92-34.82,87.79-96.95,47.27-152.72C619.2,484.77,618.46,483.75,617.57,482.52z"/><path fill="#FFFFFF" d="M206,396c61-91,319-91,380,0c-61,91-319,91-380,0z"/><circle cx="396" cy="396" r="58" fill="#101014"/><circle cx="396" cy="396" r="24" fill="#1E83F7"/></svg>"""
FAVICON_HREF = "data:image/svg+xml," + quote(FAVICON_SVG)


def utc_now():
    return datetime.now(timezone.utc)


def iso_now():
    return utc_now().isoformat().replace("+00:00", "Z")


def read_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def read_secret(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def safe_filename(name, fallback):
    name = Path(name or fallback).name.replace("\x00", "")
    return name or fallback


def clamp_score(value):
    score = float(value)
    if score < 0 or score > 1:
        raise ValueError(f"classifier score must be between 0 and 1, got {score}")
    return score


def normalize_box(box):
    if not isinstance(box, list) or len(box) != 4:
        return None
    with contextlib.suppress(TypeError, ValueError):
        return [max(0, int(float(value))) for value in box]
    return None


def normalize_detection(detection):
    if not isinstance(detection, dict):
        return None
    label = detection.get("class") or detection.get("label") or detection.get("name")
    if not label:
        return None
    with contextlib.suppress(TypeError, ValueError):
        score = clamp_score(detection.get("score", 0))
        box = normalize_box(detection.get("box"))
        normalized = {
            "label": str(label),
            "score": score,
        }
        if box:
            normalized["box"] = box
        return normalized
    return None


def unique_labels(detections):
    labels = []
    for detection in detections:
        label = detection["label"]
        if label not in labels:
            labels.append(label)
    return labels


class ImmichClient:
    def __init__(self, base_url, api_key):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({"x-api-key": api_key})

    def request(self, method, path, **kwargs):
        timeout = kwargs.pop("timeout", (10, 300))
        response = self.session.request(
            method,
            f"{self.base_url}{path}",
            timeout=timeout,
            **kwargs,
        )
        if response.status_code >= 400:
            detail = response.text[:500].replace("\n", " ")
            raise RuntimeError(f"{method} {path} failed with HTTP {response.status_code}: {detail}")
        return response

    def json(self, method, path, **kwargs):
        response = self.request(method, path, **kwargs)
        if not response.content:
            return None
        return response.json()

    def download(self, path, destination, params=None):
        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        tmp = destination.with_suffix(destination.suffix + ".tmp")
        with self.session.get(
            f"{self.base_url}{path}",
            params=params,
            stream=True,
            timeout=(10, 900),
        ) as response:
            if response.status_code >= 400:
                detail = response.text[:500].replace("\n", " ")
                raise RuntimeError(f"GET {path} failed with HTTP {response.status_code}: {detail}")
            with open(tmp, "wb") as handle:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        handle.write(chunk)
        tmp.replace(destination)
        return destination

    def upload_asset(self, path, asset, visibility="timeline"):
        path = Path(path)
        filename = safe_filename(asset.get("originalFileName"), path.name)
        data = {
            "deviceAssetId": f"immich-nsfw-guard:{asset.get('id') or path.name}",
            "deviceId": "immich-nsfw-guard",
            "filename": filename,
            "fileCreatedAt": asset.get("fileCreatedAt") or iso_now(),
            "fileModifiedAt": asset.get("fileModifiedAt") or asset.get("fileCreatedAt") or iso_now(),
            "isFavorite": "true" if asset.get("isFavorite") else "false",
            "visibility": visibility,
        }
        if asset.get("duration"):
            data["duration"] = asset["duration"]
        mime_type = asset.get("originalMimeType") or mimetypes.guess_type(filename)[0] or "application/octet-stream"
        headers = {}
        if asset.get("checksum"):
            headers["x-immich-checksum"] = asset["checksum"]
        with open(path, "rb") as handle:
            response = self.request(
                "POST",
                "/assets",
                data=data,
                files={"assetData": (filename, handle, mime_type)},
                headers=headers,
                timeout=(10, 3600),
            )
        return response.json()

    def get_asset(self, asset_id):
        try:
            return self.json("GET", f"/assets/{asset_id}")
        except RuntimeError as error:
            if "HTTP 404" in str(error):
                return None
            raise

    def asset_exists(self, asset_id):
        return self.get_asset(asset_id) is not None

    def restore_assets(self, asset_ids):
        return self.json("POST", "/trash/restore/assets", json={"ids": list(asset_ids)})

    def current_user_id(self):
        user = self.json("GET", "/users/me")
        user_id = (user or {}).get("id")
        if not user_id:
            raise RuntimeError(f"GET /users/me did not return a user id: {user}")
        return user_id


def open_db(config):
    state_dir = Path(config["state_dir"])
    state_dir.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(state_dir / "queue.db", check_same_thread=False)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA busy_timeout=30000")
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS scanned_assets (
          asset_id TEXT PRIMARY KEY,
          checksum TEXT,
          score REAL,
          status TEXT NOT NULL,
          scanned_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS review_queue (
          asset_id TEXT PRIMARY KEY,
          checksum TEXT,
          score REAL NOT NULL,
          state TEXT NOT NULL,
          source_visibility TEXT,
          quarantine_visibility TEXT,
          original_filename TEXT,
          original_mime_type TEXT,
          original_path TEXT NOT NULL,
          thumbnail_path TEXT NOT NULL,
          asset_json TEXT NOT NULL,
          target_asset_id TEXT,
          error TEXT,
          created_at TEXT NOT NULL,
          decided_at TEXT
        );

        CREATE TABLE IF NOT EXISTS scanner_state (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS review_queue_state_idx
          ON review_queue(state, created_at);

        CREATE INDEX IF NOT EXISTS review_queue_checksum_idx
          ON review_queue(checksum, state);
        """
    )
    ensure_columns(
        db,
        "scanned_assets",
        {
            "policy_hash": "TEXT NOT NULL DEFAULT ''",
            "failure_count": "INTEGER NOT NULL DEFAULT 0",
            "retry_after": "TEXT",
            "error": "TEXT",
        },
    )
    ensure_columns(
        db,
        "review_queue",
        {
            "detections_json": "TEXT NOT NULL DEFAULT '[]'",
            "flagged_labels_json": "TEXT NOT NULL DEFAULT '[]'",
            "image_width": "INTEGER",
            "image_height": "INTEGER",
            "queue_reason": "TEXT NOT NULL DEFAULT 'classifier'",
        },
    )
    return db


def ensure_columns(db, table, columns):
    for name, definition in columns.items():
        existing = {row["name"] for row in db.execute(f"PRAGMA table_info({table})")}
        if name not in existing:
            try:
                db.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")
            except sqlite3.OperationalError as error:
                if "duplicate column name" not in str(error).lower():
                    raise
    db.commit()


def get_state(db, key):
    row = db.execute("SELECT value FROM scanner_state WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else None


def set_state(db, key, value):
    db.execute(
        """
        INSERT INTO scanner_state(key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
        (key, value),
    )
    db.commit()


def delete_state(db, key):
    db.execute("DELETE FROM scanner_state WHERE key = ?", (key,))
    db.commit()


def parse_iso(value):
    if not value:
        return None
    with contextlib.suppress(ValueError, TypeError):
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return None


def scan_record(db, asset_id):
    return db.execute(
        "SELECT * FROM scanned_assets WHERE asset_id = ?",
        (asset_id,),
    ).fetchone()


def scan_policy_hash(config):
    payload = {
        "version": SCAN_POLICY_VERSION,
        "classifier_command": config.get("classifier_command") or [],
        "label_thresholds": config.get("label_thresholds") or {},
        "review_threshold": config.get("review_threshold", 0.6),
        "scan_asset_types": config.get("scan_asset_types") or [],
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def scan_record_is_current(row, checksum, policy_hash):
    if not row:
        return False
    return row["checksum"] == checksum and row["policy_hash"] == policy_hash


def retry_due(row):
    retry_after = parse_iso(row["retry_after"])
    return retry_after is None or retry_after <= utc_now()


def should_skip_current_scan(row, checksum, policy_hash):
    if not scan_record_is_current(row, checksum, policy_hash):
        return False
    if row["status"] == "failed":
        return not retry_due(row)
    return True


def queue_row(db, asset_id):
    return db.execute(
        "SELECT * FROM review_queue WHERE asset_id = ?",
        (asset_id,),
    ).fetchone()


def queued_state(db, asset_id):
    row = queue_row(db, asset_id)
    return row["state"] if row else None


def is_active_state(state):
    return state in ACTIVE_REVIEW_STATES


def checksum_marked_sfw(db, checksum):
    if not checksum:
        return False
    row = db.execute(
        "SELECT 1 FROM review_queue WHERE checksum = ? AND state = 'kept' LIMIT 1",
        (checksum,),
    ).fetchone()
    return row is not None


def record_scan(db, asset_id, checksum, score, status, policy_hash):
    db.execute(
        """
        INSERT OR REPLACE INTO scanned_assets(
          asset_id, checksum, score, status, scanned_at, policy_hash, failure_count, retry_after, error
        ) VALUES (?, ?, ?, ?, ?, ?, 0, NULL, NULL)
        """,
        (asset_id, checksum, score, status, iso_now(), policy_hash),
    )
    db.commit()


def record_scan_failure(db, asset_id, checksum, policy_hash, error, config):
    row = scan_record(db, asset_id)
    previous_count = row["failure_count"] if scan_record_is_current(row, checksum, policy_hash) else 0
    failure_count = int(previous_count or 0) + 1
    base_minutes = int(config.get("scan_failure_retry_base_minutes", 15))
    max_hours = int(config.get("scan_failure_retry_max_hours", 24))
    delay_minutes = min(base_minutes * (2 ** min(failure_count - 1, 8)), max_hours * 60)
    retry_at = (utc_now() + timedelta(minutes=delay_minutes)).isoformat().replace("+00:00", "Z")
    db.execute(
        """
        INSERT INTO scanned_assets(
          asset_id, checksum, score, status, scanned_at, policy_hash, failure_count, retry_after, error
        ) VALUES (?, ?, NULL, 'failed', ?, ?, ?, ?, ?)
        ON CONFLICT(asset_id) DO UPDATE SET
          checksum = excluded.checksum,
          score = excluded.score,
          status = excluded.status,
          scanned_at = excluded.scanned_at,
          policy_hash = excluded.policy_hash,
          failure_count = excluded.failure_count,
          retry_after = excluded.retry_after,
          error = excluded.error
        """,
        (asset_id, checksum, iso_now(), policy_hash, failure_count, retry_at, str(error)[:1000]),
    )
    db.commit()
    return retry_at, failure_count


def upsert_queue_item(
    db,
    asset,
    result,
    source_visibility,
    quarantine_visibility,
    original_path,
    thumbnail_path,
    state="pending",
    error=None,
    queue_reason="classifier",
):
    db.execute(
        """
        INSERT INTO review_queue(
          asset_id, checksum, score, state, source_visibility, quarantine_visibility,
          original_filename, original_mime_type, original_path, thumbnail_path,
          asset_json, detections_json, flagged_labels_json, image_width,
          image_height, error, queue_reason, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(asset_id) DO UPDATE SET
          checksum = excluded.checksum,
          score = excluded.score,
          state = excluded.state,
          source_visibility = excluded.source_visibility,
          quarantine_visibility = excluded.quarantine_visibility,
          original_filename = excluded.original_filename,
          original_mime_type = excluded.original_mime_type,
          original_path = excluded.original_path,
          thumbnail_path = excluded.thumbnail_path,
          asset_json = excluded.asset_json,
          detections_json = excluded.detections_json,
          flagged_labels_json = excluded.flagged_labels_json,
          image_width = excluded.image_width,
          image_height = excluded.image_height,
          error = excluded.error,
          queue_reason = excluded.queue_reason,
          target_asset_id = NULL,
          decided_at = NULL
        """,
        (
            asset["id"],
            asset.get("checksum"),
            result["score"],
            state,
            source_visibility,
            quarantine_visibility,
            asset.get("originalFileName"),
            asset.get("originalMimeType"),
            str(original_path),
            str(thumbnail_path),
            json.dumps(asset, sort_keys=True),
            json.dumps(result.get("detections") or [], sort_keys=True),
            json.dumps(result.get("flagged_labels") or [], sort_keys=True),
            result.get("image_width"),
            result.get("image_height"),
            error,
            queue_reason,
            iso_now(),
        ),
    )
    db.commit()


def reactivate_queue_item(db, asset, row, queue_reason="archive"):
    db.execute(
        """
        UPDATE review_queue
        SET state = 'pending',
            source_visibility = 'archive',
            quarantine_visibility = 'archive',
            asset_json = ?,
            target_asset_id = NULL,
            error = NULL,
            queue_reason = ?,
            created_at = ?,
            decided_at = NULL
        WHERE asset_id = ?
        """,
        (json.dumps(asset, sort_keys=True), queue_reason, iso_now(), row["asset_id"]),
    )
    db.commit()


def set_queue_state(db, asset_id, state, error=None, target_asset_id=None):
    db.execute(
        """
        UPDATE review_queue
        SET state = ?,
            error = ?,
            target_asset_id = COALESCE(?, target_asset_id)
        WHERE asset_id = ?
        """,
        (state, error, target_asset_id, asset_id),
    )
    db.commit()


def set_queue_quarantine(db, asset_id, quarantine_visibility, error=None):
    db.execute(
        """
        UPDATE review_queue
        SET quarantine_visibility = ?, error = ?
        WHERE asset_id = ?
        """,
        (quarantine_visibility, error, asset_id),
    )
    db.commit()


def parse_classifier_result(config, output):
    threshold = float(config.get("review_threshold", 0.6))
    label_thresholds = config.get("label_thresholds") or {}
    detections = []
    image_width = None
    image_height = None
    explicit_flagged = None
    explicit_score = None

    parsed = parse_classifier_json(output)
    if parsed is not None:
        if isinstance(parsed, dict):
            explicit_flagged = parsed.get("flagged")
            for key in ("score", "nsfw", "unsafe", "probability"):
                if key in parsed:
                    explicit_score = clamp_score(parsed[key])
                    break
            image_width = parsed.get("image_width") or parsed.get("width")
            image_height = parsed.get("image_height") or parsed.get("height")
            raw_detections = parsed.get("detections") or parsed.get("labels") or []
            prediction = parsed.get("prediction")
            if not raw_detections and isinstance(prediction, list):
                raw_detections = prediction[0] if prediction and isinstance(prediction[0], list) else prediction
            detections = [normalized for item in raw_detections if (normalized := normalize_detection(item))]
        elif isinstance(parsed, list):
            detections = [normalized for item in parsed if (normalized := normalize_detection(item))]
        elif isinstance(parsed, (int, float)):
            explicit_score = clamp_score(parsed)

    if parsed is None and explicit_score is None and not detections:
        explicit_score = clamp_score(output.splitlines()[-1].strip())

    flagged_detections = []
    for detection in detections:
        label = detection["label"]
        if label in label_thresholds and detection["score"] >= float(label_thresholds[label]):
            flagged_detections.append(detection)

    if flagged_detections:
        score = max(detection["score"] for detection in flagged_detections)
        flagged = True
    elif explicit_score is not None:
        score = explicit_score
        flagged = bool(explicit_flagged) if explicit_flagged is not None else score >= threshold
    elif detections:
        score = max(detection["score"] for detection in detections)
        flagged = False
    else:
        score = 0.0
        flagged = False

    return {
        "score": score,
        "flagged": flagged,
        "detections": detections,
        "flagged_labels": unique_labels(flagged_detections),
        "image_width": image_width,
        "image_height": image_height,
    }


def parse_classifier_json(output):
    output = output.strip()
    if not output:
        return None
    with contextlib.suppress(json.JSONDecodeError, TypeError, ValueError):
        return json.loads(output)
    for line in reversed([line.strip() for line in output.splitlines() if line.strip()]):
        with contextlib.suppress(json.JSONDecodeError, TypeError, ValueError):
            return json.loads(line)
    return None


def try_parse_classifier_result(config, output):
    with contextlib.suppress(Exception):
        return parse_classifier_result(config, output)
    return None


def run_classifier_batch(config, image_paths):
    command = list(config.get("classifier_command") or [])
    if not command:
        raise RuntimeError("classifier_command is empty")
    image_paths = [str(path) for path in image_paths]
    timeout = int(config.get("classifier_timeout_seconds", 120)) * max(1, len(image_paths))
    completed = subprocess.run(
        command + image_paths,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()[:500]
        raise RuntimeError(f"classifier exited with {completed.returncode}: {stderr}")

    output = completed.stdout.strip()
    if not output:
        raise RuntimeError("classifier produced no output")
    if len(image_paths) == 1:
        return [parse_classifier_result(config, output)]

    parsed = parse_classifier_json(output)
    if isinstance(parsed, list) and len(parsed) == len(image_paths):
        return [parse_classifier_result(config, json.dumps(item)) for item in parsed]

    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if len(lines) == len(image_paths):
        return [parse_classifier_result(config, line) for line in lines]
    parsed_lines = [result for line in lines if (result := try_parse_classifier_result(config, line))]
    if len(parsed_lines) == len(image_paths):
        return parsed_lines

    raise RuntimeError(
        f"classifier output for {len(image_paths)} images must be a JSON array or one result per line"
    )


def run_classifier(config, image_path):
    return run_classifier_batch(config, [image_path])[0]


def watermark_created_after(value, overlap_minutes):
    if not value:
        return None
    with contextlib.suppress(ValueError):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return (parsed - timedelta(minutes=overlap_minutes)).isoformat().replace("+00:00", "Z")
    return value


def list_config(config, key, default):
    values = config.get(key, default)
    if isinstance(values, str):
        values = [values]
    return [value for value in (values or []) if value]


def scan_query_specs(config):
    visibilities = ["timeline", "archive"]
    asset_types = list_config(config, "scan_asset_types", ["IMAGE"])
    specs = []
    for visibility in visibilities:
        for asset_type in asset_types:
            specs.append(
                {
                    "key": f"{visibility}:{asset_type}",
                    "visibility": visibility,
                    "type": asset_type,
                }
            )
    return specs


def metadata_search_body(config, spec, created_after=None):
    body = {
        "order": "desc",
        "page": 1,
        "size": int(config.get("scan_page_size", 100)),
        "withExif": False,
        "withStacked": False,
        "visibility": spec["visibility"],
        "type": spec["type"],
    }
    if created_after:
        body["createdAfter"] = created_after
    return body


def backfill_page_key(query_key):
    return f"all_unscanned_page:{query_key}"


def backfill_done_key(query_key):
    return f"all_unscanned_done:{query_key}"


def clear_backfill_state(db, config):
    for spec in scan_query_specs(config):
        delete_state(db, backfill_page_key(spec["key"]))
        delete_state(db, backfill_done_key(spec["key"]))
    delete_state(db, "all_unscanned_max_created_at")


def reset_backfill_state(db, config):
    clear_backfill_state(db, config)
    delete_state(db, "all_unscanned_watermark")


def delete_stale_scan_records(db, policy_hash):
    cursor = db.execute("DELETE FROM scanned_assets WHERE policy_hash != ?", (policy_hash,))
    db.commit()
    return cursor.rowcount


def reconcile_scan_policy(db, config, policy_hash):
    stored_policy_hash = get_state(db, "scan_policy_hash")
    if stored_policy_hash == policy_hash:
        return

    reset_backfill_state(db, config)
    deleted = delete_stale_scan_records(db, policy_hash)
    if stored_policy_hash:
        LOG.info(
            "scan policy changed from %s to %s; reset backfill progress and deleted %s stale scan record(s)",
            stored_policy_hash,
            policy_hash,
            deleted,
        )
    else:
        LOG.info(
            "initialized scan policy %s; reset backfill progress and deleted %s stale scan record(s)",
            policy_hash,
            deleted,
        )
    set_state(db, "scan_policy_hash", policy_hash)


def search_assets(client, config, db, stats):
    mode = config.get("scan_mode", "all-unscanned")
    watermark = get_state(db, "all_unscanned_watermark") if mode == "all-unscanned" else None
    page_size = int(config.get("scan_page_size", 100))
    max_pages = int(config.get("max_search_pages_per_run", 25))
    specs = scan_query_specs(config)
    seen = set()
    max_created_at = get_state(db, "all_unscanned_max_created_at") if mode == "all-unscanned" and not watermark else None
    stats["reached_end"] = False
    stats["max_created_at"] = max_created_at
    stats["page_limited"] = False

    def yield_query(kind, spec, created_after=None, start_page=1, persist_progress=False, page_limit=None):
        nonlocal max_created_at
        page_limit = page_limit or max_pages
        page = start_page
        pages = 0
        body = metadata_search_body(config, spec, created_after)
        while True:
            if pages >= page_limit:
                stats["page_limited"] = True
                stats["current_kind"] = kind
                stats["current_query_key"] = spec["key"]
                stats["current_page"] = page
                return False

            body["page"] = page
            stats["current_kind"] = kind
            stats["current_query_key"] = spec["key"]
            stats["current_page"] = page
            response = client.json(
                "POST",
                "/search/metadata",
                json=body,
            )
            assets = ((response or {}).get("assets") or {}).get("items") or []
            if not assets:
                if persist_progress:
                    set_state(db, backfill_done_key(spec["key"]), "1")
                    delete_state(db, backfill_page_key(spec["key"]))
                return True

            for asset in assets:
                asset_id = asset.get("id")
                created_at = asset.get("createdAt")
                if created_at and (max_created_at is None or created_at > max_created_at):
                    max_created_at = created_at
                    stats["max_created_at"] = max_created_at
                    if mode == "all-unscanned" and not watermark:
                        set_state(db, "all_unscanned_max_created_at", max_created_at)
                if asset_id and asset_id not in seen:
                    seen.add(asset_id)
                    yield asset

            pages += 1
            if len(assets) < page_size:
                if persist_progress:
                    set_state(db, backfill_done_key(spec["key"]), "1")
                    delete_state(db, backfill_page_key(spec["key"]))
                return True

            page += 1
            if persist_progress:
                set_state(db, backfill_page_key(spec["key"]), str(page))

    if mode == "recent":
        since = utc_now() - timedelta(hours=float(config.get("scan_lookback_hours", 24)))
        created_after = since.isoformat().replace("+00:00", "Z")
        reached = True
        for spec in specs:
            reached = (yield from yield_query("recent", spec, created_after)) and reached
        stats["reached_end"] = reached
        return

    if watermark:
        created_after = watermark_created_after(
            watermark,
            int(config.get("watermark_overlap_minutes", 60)),
        )
        reached = True
        for spec in specs:
            reached = (yield from yield_query("watermark", spec, created_after)) and reached
        stats["reached_end"] = reached
        return

    # During the initial backfill, always scan a recent upload window first so
    # new old-dated imports are not hidden behind a large historical cursor.
    since = utc_now() - timedelta(hours=float(config.get("scan_lookback_hours", 24)))
    recent_after = since.isoformat().replace("+00:00", "Z")
    for spec in specs:
        yield from yield_query("recent", spec, recent_after, page_limit=min(max_pages, 3))
    stats["page_limited"] = False

    for spec in specs:
        if get_state(db, backfill_done_key(spec["key"])):
            continue
        start_page = int(get_state(db, backfill_page_key(spec["key"])) or "1")
        yield from yield_query("backfill", spec, start_page=start_page, persist_progress=True)
        if stats.get("page_limited"):
            return

    stats["reached_end"] = all(get_state(db, backfill_done_key(spec["key"])) for spec in specs)


def quarantine_asset(client, config, asset_id):
    visibility = "archive"
    try:
        client.json("PUT", f"/assets/{asset_id}", json={"visibility": visibility})
        return visibility, None
    except Exception as error:
        return "none", str(error)


def source_owner_id(client, config):
    configured = config.get("source_user_id")
    if configured:
        return configured
    if not config.get("scan_own_assets_only", True):
        return None
    return client.current_user_id()


def scan(config):
    db = open_db(config)
    policy_hash = scan_policy_hash(config)
    reconcile_scan_policy(db, config, policy_hash)
    source = ImmichClient(config["immich_url"], read_secret(config["source_api_key_file"]))
    owner_id = source_owner_id(source, config)
    max_assets = int(config.get("max_assets_per_run", 100))
    batch_size = int(config.get("classifier_batch_size", 1))
    assets_root = Path(config["state_dir"]) / "assets"
    attempted = 0
    scanned = 0
    queued = 0
    skipped = 0
    had_errors = False
    stopped_by_limit = False
    batch = []
    stats = {}
    if owner_id:
        LOG.info("scanning only source owner %s", owner_id)
    LOG.info("scan policy hash %s", policy_hash)

    def handle_classification(item, result):
        nonlocal scanned, queued
        asset = item["asset"]
        asset_id = asset["id"]
        checksum = asset.get("checksum")
        asset_dir = item["asset_dir"]
        original_path = item["original_path"]
        thumbnail_path = item["thumbnail_path"]
        scanned += 1
        score = result["score"]
        source_visibility = asset.get("visibility") or "timeline"
        is_archived = source_visibility == "archive"
        LOG.info(
            "asset %s classifier score %.4f flagged=%s labels=%s",
            asset_id,
            score,
            result["flagged"],
            ",".join(result.get("flagged_labels") or []),
        )

        if not result["flagged"] and not is_archived:
            record_scan(db, asset_id, checksum, score, "safe", policy_hash)
            shutil.rmtree(asset_dir, ignore_errors=True)
            return

        upsert_queue_item(
            db,
            asset,
            result,
            source_visibility,
            "archive" if is_archived else "none",
            original_path,
            thumbnail_path,
            state="pending" if is_archived else "quarantining",
            queue_reason="archive" if is_archived and not result["flagged"] else "classifier",
        )
        if is_archived:
            record_scan(db, asset_id, checksum, score, "queued_archive", policy_hash)
            queued += 1
            LOG.info("archived asset %s queued for review", asset_id)
            return

        quarantine_visibility, quarantine_error = quarantine_asset(source, config, asset_id)
        set_queue_quarantine(db, asset_id, quarantine_visibility, quarantine_error)
        queue_state = "quarantine_failed" if quarantine_error else "pending"
        set_queue_state(db, asset_id, queue_state, quarantine_error)
        record_scan(db, asset_id, checksum, score, queue_state if quarantine_error else "queued", policy_hash)
        queued += 1
        if quarantine_error:
            LOG.error("asset %s was flagged but quarantine failed: %s", asset_id, quarantine_error)
        else:
            LOG.info("asset %s queued for review", asset_id)

    def flush_batch():
        nonlocal had_errors
        if not batch:
            return
        pending = list(batch)
        batch.clear()
        downloaded = []
        for item in pending:
            asset = item["asset"]
            asset_id = asset["id"]
            try:
                source.download(f"/assets/{asset_id}/thumbnail", item["thumbnail_path"], params={"size": "preview"})
                downloaded.append(item)
            except Exception as error:
                had_errors = True
                retry_at, failure_count = record_scan_failure(
                    db,
                    asset_id,
                    asset.get("checksum"),
                    policy_hash,
                    error,
                    config,
                )
                LOG.exception(
                    "failed to download thumbnail for asset %s; retry %s scheduled at %s",
                    asset_id,
                    failure_count,
                    retry_at,
                )

        if not downloaded:
            return

        try:
            results = run_classifier_batch(config, [item["thumbnail_path"] for item in downloaded])
        except Exception as error:
            had_errors = True
            for item in downloaded:
                asset = item["asset"]
                retry_at, failure_count = record_scan_failure(
                    db,
                    asset["id"],
                    asset.get("checksum"),
                    policy_hash,
                    error,
                    config,
                )
                LOG.exception(
                    "failed to classify asset %s; retry %s scheduled at %s",
                    asset["id"],
                    failure_count,
                    retry_at,
                )
            return

        for item, result in zip(downloaded, results):
            try:
                handle_classification(item, result)
            except Exception as error:
                had_errors = True
                asset = item["asset"]
                retry_at, failure_count = record_scan_failure(
                    db,
                    asset["id"],
                    asset.get("checksum"),
                    policy_hash,
                    error,
                    config,
                )
                LOG.exception(
                    "failed to process classifier result for asset %s; retry %s scheduled at %s",
                    asset["id"],
                    failure_count,
                    retry_at,
                )

    for asset in search_assets(source, config, db, stats):
        asset_id = asset.get("id")
        if not asset_id:
            continue
        if owner_id and asset.get("ownerId") != owner_id:
            skipped += 1
            continue
        if asset.get("isTrashed"):
            continue
        checksum = asset.get("checksum")
        source_visibility = asset.get("visibility") or "timeline"
        existing_row = queue_row(db, asset_id)
        existing_state = existing_row["state"] if existing_row else None
        if existing_state:
            if existing_state == "quarantine_failed":
                quarantine_visibility, quarantine_error = quarantine_asset(source, config, asset_id)
                set_queue_quarantine(db, asset_id, quarantine_visibility, quarantine_error)
                if quarantine_error:
                    LOG.warning("asset %s quarantine retry failed: %s", asset_id, quarantine_error)
                    skipped += 1
                    continue
                set_queue_state(db, asset_id, "pending")
                existing_state = "pending"
                LOG.info("asset %s quarantine retry succeeded", asset_id)
            if not is_active_state(existing_state) and source_visibility == "archive":
                reactivate_queue_item(db, asset, existing_row, queue_reason="archive")
                record_scan(db, asset_id, checksum, existing_row["score"], "queued_archive", policy_hash)
                queued += 1
                LOG.info("archived asset %s requeued with existing labels", asset_id)
                continue
            record_scan(db, asset_id, checksum, None, existing_state, policy_hash)
            skipped += 1
            continue

        asset_dir = assets_root / asset_id
        thumbnail_path = asset_dir / "thumbnail.jpg"
        original_path = asset_dir / safe_filename(asset.get("originalFileName"), asset_id)

        current_scan = scan_record(db, asset_id)
        if source_visibility != "archive" and should_skip_current_scan(current_scan, checksum, policy_hash):
            skipped += 1
            continue

        if source_visibility != "archive" and checksum_marked_sfw(db, checksum):
            record_scan(db, asset_id, checksum, None, "known_sfw", policy_hash)
            skipped += 1
            continue

        if attempted >= max_assets:
            LOG.info("max_assets_per_run=%s reached; stopping this scan", max_assets)
            stopped_by_limit = True
            break
        attempted += 1

        batch.append(
            {
                "asset": asset,
                "asset_dir": asset_dir,
                "original_path": original_path,
                "thumbnail_path": thumbnail_path,
            }
        )
        if len(batch) >= batch_size:
            flush_batch()

    flush_batch()

    if stopped_by_limit and stats.get("current_kind") == "backfill" and stats.get("current_query_key"):
        set_state(
            db,
            backfill_page_key(stats["current_query_key"]),
            str(stats.get("current_page") or 1),
        )

    if (
        config.get("scan_mode", "all-unscanned") == "all-unscanned"
        and stats.get("reached_end")
        and stats.get("max_created_at")
        and not had_errors
    ):
        set_state(db, "all_unscanned_watermark", stats["max_created_at"])
        clear_backfill_state(db, config)

    LOG.info("scan complete: attempted=%s scanned=%s queued=%s skipped=%s", attempted, scanned, queued, skipped)


def get_csrf_token(state_dir):
    token_path = Path(state_dir) / "csrf_token"
    if token_path.exists():
        return token_path.read_text(encoding="utf-8").strip()
    token = secretlib.token_urlsafe(32)
    token_path.write_text(token, encoding="utf-8")
    os.chmod(token_path, 0o600)
    return token


class ReviewApp:
    def __init__(self, config):
        self.config = config
        self.db = open_db(config)
        self.db_lock = threading.RLock()
        self.action_lock = threading.Lock()
        self.mode = config.get("mode", "dual-account")
        self.source = ImmichClient(config["immich_url"], read_secret(config["source_api_key_file"]))
        self.target = None
        if self.mode == "dual-account":
            self.target = ImmichClient(config["immich_url"], read_secret(config["target_api_key_file"]))
        self.username = config.get("review_username", "admin")
        self.password = read_secret(config["review_password_file"])
        self.csrf_token = get_csrf_token(config["state_dir"])
        self.recover_transient_states()

    def rows_by_states(self, states):
        placeholders = ", ".join("?" for _ in states)
        with self.db_lock:
            return self.db.execute(
                f"""
                SELECT * FROM review_queue
                WHERE state IN ({placeholders})
                ORDER BY score DESC, created_at ASC
                """,
                tuple(states),
            ).fetchall()

    def pending_rows(self):
        return self.rows_by_states(ACTIVE_REVIEW_STATES)

    def history_rows(self):
        placeholders = ", ".join("?" for _ in HISTORY_REVIEW_STATES)
        with self.db_lock:
            return self.db.execute(
                f"""
                SELECT * FROM review_queue
                WHERE state IN ({placeholders})
                ORDER BY decided_at DESC
                LIMIT 100
                """,
                HISTORY_REVIEW_STATES,
            ).fetchall()

    def row(self, asset_id):
        with self.db_lock:
            return self.db.execute(
                "SELECT * FROM review_queue WHERE asset_id = ?",
                (asset_id,),
            ).fetchone()

    def ensure_actionable(self, row):
        if row["state"] not in ACTIONABLE_REVIEW_STATES:
            raise RuntimeError(f"asset is in state {row['state']} and cannot be actioned")

    def set_error(self, asset_id, error):
        with self.db_lock:
            self.db.execute(
                "UPDATE review_queue SET error = ? WHERE asset_id = ?",
                (str(error)[:1000], asset_id),
            )
            self.db.commit()

    def set_action_state(self, asset_id, state, error=None, target_asset_id=None):
        with self.db_lock:
            self.db.execute(
                """
                UPDATE review_queue
                SET state = ?,
                    error = ?,
                    target_asset_id = COALESCE(?, target_asset_id)
                WHERE asset_id = ?
                """,
                (state, str(error)[:1000] if error else None, target_asset_id, asset_id),
            )
            self.db.commit()

    def set_quarantine_visibility(self, asset_id, quarantine_visibility, error=None):
        with self.db_lock:
            self.db.execute(
                """
                UPDATE review_queue
                SET quarantine_visibility = ?, error = ?
                WHERE asset_id = ?
                """,
                (quarantine_visibility, str(error)[:1000] if error else None, asset_id),
            )
            self.db.commit()

    def mark_decided(self, asset_id, state, target_asset_id=None):
        with self.db_lock:
            self.db.execute(
                """
                UPDATE review_queue
                SET state = ?, target_asset_id = COALESCE(?, target_asset_id), error = NULL, decided_at = ?
                WHERE asset_id = ?
                """,
                (state, target_asset_id, iso_now(), asset_id),
            )
            self.db.commit()

    def mark_failed(self, asset_id, state, error):
        self.set_action_state(asset_id, state, error)

    def cleanup_local_files(self, row):
        if self.config.get("keep_local_copies", False):
            return
        with contextlib.suppress(FileNotFoundError):
            Path(row["original_path"]).unlink()
        parent = Path(row["original_path"]).parent
        with contextlib.suppress(OSError):
            parent.rmdir()

    def requarantine(self, row):
        with contextlib.suppress(Exception):
            self.source.json("PUT", f"/assets/{row['asset_id']}", json={"visibility": "archive"})

    def delete_source_asset(self, asset_id):
        try:
            self.source.json(
                "DELETE",
                "/assets",
                json={"ids": [asset_id], "force": bool(self.config.get("force_delete_source", False))},
            )
        except RuntimeError as error:
            asset = self.source.get_asset(asset_id)
            if asset is None or asset.get("isTrashed"):
                return
            raise error

    def delete_target_asset(self, asset_id):
        if not self.target:
            raise RuntimeError("target Immich API key is only configured in dual-account mode")
        try:
            self.target.json(
                "DELETE",
                "/assets",
                json={"ids": [asset_id], "force": bool(self.config.get("force_delete_source", False))},
            )
        except RuntimeError as error:
            asset = self.target.get_asset(asset_id)
            if asset is None or asset.get("isTrashed"):
                return
            raise error

    def recover_transient_states(self):
        for row in self.rows_by_states(("quarantining", "quarantine_failed", "moving", "locking", "keeping", "undoing")):
            asset_id = row["asset_id"]
            state = row["state"]
            LOG.info("recovering interrupted %s action for asset %s", state, asset_id)
            try:
                if state in ("quarantining", "quarantine_failed"):
                    visibility, error = quarantine_asset(self.source, self.config, asset_id)
                    self.set_quarantine_visibility(asset_id, visibility, error)
                    self.set_action_state(asset_id, "quarantine_failed" if error else "pending", error)
                elif state == "moving":
                    target_asset_id = row["target_asset_id"]
                    if not target_asset_id:
                        self.requarantine(row)
                        self.mark_failed(
                            asset_id,
                            "move_failed",
                            "interrupted before target upload id was recorded; retry Move to NSFW Account",
                        )
                        continue
                    if not self.target:
                        self.mark_failed(asset_id, "move_failed", "target API key is not configured in same-account mode")
                        continue
                    if not self.target.asset_exists(target_asset_id):
                        self.mark_failed(asset_id, "move_failed", f"target asset {target_asset_id} no longer exists")
                        continue
                    self.delete_source_asset(asset_id)
                    self.mark_decided(asset_id, "moved", target_asset_id)
                    self.cleanup_local_files(row)
                elif state == "locking":
                    self.source.json("PUT", f"/assets/{asset_id}", json={"visibility": "locked"})
                    self.mark_decided(asset_id, "locked")
                    self.cleanup_local_files(row)
                elif state == "keeping":
                    self.source.json("PUT", f"/assets/{asset_id}", json={"visibility": "timeline"})
                    self.mark_decided(asset_id, "kept")
                    self.cleanup_local_files(row)
                elif state == "undoing":
                    self.mark_failed(asset_id, "undo_failed", "interrupted while undoing; retry Undo")
            except Exception as error:
                LOG.exception("failed to recover %s action for asset %s", state, asset_id)
                failed_state = {
                    "moving": "move_failed",
                    "locking": "lock_failed",
                    "keeping": "keep_failed",
                    "undoing": "undo_failed",
                }.get(state, state)
                self.mark_failed(asset_id, failed_state, error)

    def ensure_original(self, row, client=None, asset_id=None):
        client = client or self.source
        asset_id = asset_id or row["asset_id"]
        original_path = Path(row["original_path"])
        if original_path.exists():
            return original_path

        original_path.parent.mkdir(parents=True, exist_ok=True)
        client.download(f"/assets/{asset_id}/original", original_path)
        return original_path

    def download_thumbnail(self, client, asset_id, thumbnail_path):
        thumbnail_path = Path(thumbnail_path)
        with contextlib.suppress(Exception):
            client.download(f"/assets/{asset_id}/thumbnail", thumbnail_path, params={"size": "preview"})

    def asset_from_row(self, row, asset_id=None, visibility="archive"):
        asset = json.loads(row["asset_json"])
        asset["id"] = asset_id or row["asset_id"]
        asset["visibility"] = visibility
        return asset

    def queue_archive_from_row(self, row, asset_id=None, asset=None, queue_reason="undo"):
        asset_id = asset_id or row["asset_id"]
        old_asset = self.asset_from_row(row, asset_id=asset_id, visibility="archive")
        asset = {**old_asset, **(asset or {})}
        asset["id"] = asset_id
        asset["visibility"] = "archive"

        asset_dir = Path(self.config["state_dir"]) / "assets" / asset_id
        filename = safe_filename(asset.get("originalFileName") or row["original_filename"], asset_id)
        original_path = asset_dir / filename
        thumbnail_path = asset_dir / "thumbnail.jpg"
        asset_dir.mkdir(parents=True, exist_ok=True)

        previous_original = Path(row["original_path"])
        if previous_original.exists() and previous_original != original_path:
            shutil.copy2(previous_original, original_path)
        self.download_thumbnail(self.source, asset_id, thumbnail_path)

        result = {
            "score": float(row["score"] or 0.0),
            "flagged": True,
            "detections": json.loads(row["detections_json"] or "[]"),
            "flagged_labels": json.loads(row["flagged_labels_json"] or "[]"),
            "image_width": row["image_width"],
            "image_height": row["image_height"],
        }
        upsert_queue_item(
            self.db,
            asset,
            result,
            "archive",
            "archive",
            original_path,
            thumbnail_path,
            state="pending",
            queue_reason=queue_reason,
        )
        record_scan(self.db, asset_id, asset.get("checksum") or row["checksum"], result["score"], "queued_archive", scan_policy_hash(self.config))

    def keep_family(self, asset_id):
        with self.action_lock:
            row = self.row(asset_id)
            if not row:
                raise RuntimeError("asset is not in the review queue")
            self.ensure_actionable(row)
            self.set_action_state(asset_id, "keeping")
            try:
                self.source.json("PUT", f"/assets/{asset_id}", json={"visibility": "timeline"})
                self.mark_decided(asset_id, "kept")
                self.cleanup_local_files(row)
            except Exception as error:
                self.mark_failed(asset_id, "keep_failed", error)
                raise

    def move_to_target(self, asset_id):
        if self.mode != "dual-account" or not self.target:
            raise RuntimeError("Move to NSFW account is only available in dual-account mode")
        with self.action_lock:
            row = self.row(asset_id)
            if not row:
                raise RuntimeError("asset is not in the review queue")
            self.ensure_actionable(row)
            asset = json.loads(row["asset_json"])
            self.set_action_state(asset_id, "moving")
            try:
                target_asset_id = row["target_asset_id"]
                if not target_asset_id or not self.target.asset_exists(target_asset_id):
                    original_path = self.ensure_original(row)
                    upload = self.target.upload_asset(original_path, asset)
                    target_asset_id = upload.get("id")
                    if not target_asset_id:
                        raise RuntimeError(f"target upload did not return an asset id: {upload}")
                    self.set_action_state(asset_id, "moving", target_asset_id=target_asset_id)
                self.delete_source_asset(asset_id)
                self.mark_decided(asset_id, "moved", target_asset_id)
                self.cleanup_local_files(row)
            except Exception as error:
                self.requarantine(row)
                self.mark_failed(asset_id, "move_failed", error)
                raise

    def lock_source(self, asset_id):
        if self.mode != "same-account":
            raise RuntimeError("Move to Locked is only available in same-account mode")
        with self.action_lock:
            row = self.row(asset_id)
            if not row:
                raise RuntimeError("asset is not in the review queue")
            self.ensure_actionable(row)
            self.set_action_state(asset_id, "locking")
            try:
                self.source.json("PUT", f"/assets/{asset_id}", json={"visibility": "locked"})
                self.mark_decided(asset_id, "locked")
                self.cleanup_local_files(row)
            except Exception as error:
                self.requarantine(row)
                self.mark_failed(asset_id, "lock_failed", error)
                raise

    def undo_decision(self, asset_id):
        with self.action_lock:
            row = self.row(asset_id)
            if not row:
                raise RuntimeError("asset is not in the review history")
            if row["state"] not in HISTORY_REVIEW_STATES:
                raise RuntimeError(f"asset is in state {row['state']} and cannot be undone")
            if row["state"] == "locked":
                raise RuntimeError(
                    "Immich API keys cannot unlock locked assets; unlock it manually in Immich if this was a false positive"
                )

            self.set_action_state(asset_id, "undoing")
            try:
                target_asset_id = row["target_asset_id"]
                if target_asset_id:
                    if not self.target:
                        raise RuntimeError("target API key is not configured in same-account mode")
                    restored_asset = None
                    try:
                        self.source.restore_assets([asset_id])
                        self.source.json("PUT", f"/assets/{asset_id}", json={"visibility": "archive"})
                        restored_asset = self.source.get_asset(asset_id) or self.asset_from_row(row, visibility="archive")
                    except Exception as restore_error:
                        LOG.info("could not restore source asset %s from trash during undo: %s", asset_id, restore_error)

                    if restored_asset:
                        self.delete_target_asset(target_asset_id)
                        self.queue_archive_from_row(row, asset_id=asset_id, asset=restored_asset)
                    else:
                        original_path = self.ensure_original(row, client=self.target, asset_id=target_asset_id)
                        upload = self.source.upload_asset(original_path, self.asset_from_row(row), visibility="archive")
                        new_asset_id = upload.get("id")
                        if not new_asset_id:
                            raise RuntimeError(f"source upload did not return an asset id: {upload}")
                        asset = self.source.get_asset(new_asset_id) or self.asset_from_row(row, asset_id=new_asset_id)
                        self.delete_target_asset(target_asset_id)
                        self.mark_decided(asset_id, "undone", target_asset_id)
                        self.queue_archive_from_row(row, asset_id=new_asset_id, asset=asset)
                else:
                    self.source.json("PUT", f"/assets/{asset_id}", json={"visibility": "archive"})
                    asset = self.source.get_asset(asset_id) or self.asset_from_row(row, visibility="archive")
                    self.queue_archive_from_row(row, asset_id=asset_id, asset=asset)
            except Exception as error:
                self.mark_failed(asset_id, "undo_failed", error)
                raise


def html_page(app, params=None):
    params = params or {}
    pending_all = app.pending_rows()
    history_all = app.history_rows()
    token = html.escape(app.csrf_token)

    def qvalue(name, default=""):
        value = params.get(name, [default])
        return value[0] if value else default

    def row_json(row, column, default):
        with contextlib.suppress(json.JSONDecodeError, TypeError):
            value = json.loads(row[column] or "")
            if isinstance(value, type(default)):
                return value
        return default

    def asset_json(row):
        return row_json(row, "asset_json", {})

    def asset_type(row):
        return str(asset_json(row).get("type") or "unknown").lower()

    def row_labels(row):
        labels = []
        for detection in row_json(row, "detections_json", []):
            label = str(detection.get("label") or "")
            if label and label not in labels:
                labels.append(label)
        return labels

    def row_reason(row):
        return row["queue_reason"] or "classifier"

    active_tab = qvalue("tab", "queue")
    if active_tab not in ("queue", "history"):
        active_tab = "queue"
    gallery = qvalue("view", "") == "gallery"
    selected_asset = qvalue("asset", "")
    media_filter = qvalue("media", "all")
    label_filter = qvalue("label", "")
    min_score_raw = qvalue("min_score", "")
    min_score = None
    with contextlib.suppress(ValueError):
        if min_score_raw:
            min_score = float(min_score_raw)
    default_sort = "date_newest" if active_tab == "history" else "score_desc"
    active_sort = qvalue("sort", default_sort)
    date_label = "Decided" if active_tab == "history" else "Queued"
    sort_options = (
        ("score_desc", "Score: high to low"),
        ("score_asc", "Score: low to high"),
        ("date_newest", f"{date_label}: newest first"),
        ("date_oldest", f"{date_label}: oldest first"),
        ("filename_asc", "Filename: A to Z"),
        ("filename_desc", "Filename: Z to A"),
    )
    if active_sort not in {key for key, _label in sort_options}:
        active_sort = default_sort

    all_rows = pending_all + history_all
    labels = sorted({label for row in all_rows for label in row_labels(row)})

    def row_score(row):
        return float(row["score"] or 0.0)

    def row_filename(row):
        return str(row["original_filename"] or row["asset_id"] or "").casefold()

    def row_date(row):
        column = "decided_at" if active_tab == "history" else "created_at"
        return str(row[column] or "")

    def sort_rows(rows):
        if active_sort == "score_asc":
            return sorted(rows, key=lambda row: (row_score(row), row_date(row), row_filename(row)))
        if active_sort == "date_newest":
            return sorted(rows, key=lambda row: (row_date(row), row_filename(row)), reverse=True)
        if active_sort == "date_oldest":
            return sorted(rows, key=lambda row: (row_date(row), row_filename(row)))
        if active_sort == "filename_asc":
            return sorted(rows, key=lambda row: (row_filename(row), -row_score(row), row_date(row)))
        if active_sort == "filename_desc":
            return sorted(rows, key=lambda row: (row_filename(row), row_score(row), row_date(row)), reverse=True)
        return sorted(rows, key=lambda row: (-row_score(row), row_date(row), row_filename(row)))

    def matches_filters(row, include_media=True):
        media_type = asset_type(row)
        if include_media and media_filter in ("image", "video") and media_type != media_filter:
            return False
        if label_filter and label_filter not in row_labels(row):
            return False
        if min_score is not None and float(row["score"] or 0) < min_score:
            return False
        return True

    tab_rows_all = history_all if active_tab == "history" else pending_all
    media_count_rows = [row for row in tab_rows_all if matches_filters(row, include_media=False)]
    active_rows = sort_rows([row for row in media_count_rows if matches_filters(row)])
    pending = active_rows if active_tab == "queue" else []
    history_rows_filtered = active_rows if active_tab == "history" else []

    counts = {
        "all": len(pending_all),
        "history": len(history_all),
    }
    media_counts = {
        "all": len(media_count_rows),
        "image": sum(1 for row in media_count_rows if asset_type(row) == "image"),
        "video": sum(1 for row in media_count_rows if asset_type(row) == "video"),
    }

    def query_link(**overrides):
        values = {
            "tab": active_tab,
            "media": media_filter,
            "label": label_filter,
            "min_score": min_score_raw,
            "sort": active_sort,
            "view": "gallery" if gallery else "",
            "asset": selected_asset if gallery else "",
        }
        values.update(overrides)
        target_tab = values.get("tab") or "queue"
        target_default_sort = "date_newest" if target_tab == "history" else "score_desc"
        clean = {
            key: value
            for key, value in values.items()
            if value
            and not (key == "media" and value == "all")
            and not (key == "tab" and value == "queue")
            and not (key == "sort" and value == target_default_sort)
        }
        query = urlencode(clean)
        return "/" + (f"?{query}" if query else "")

    def with_fragment(url, fragment):
        return f"{url}#{fragment}"

    list_url = query_link(view="", asset="")
    gallery_base_url = query_link(view="gallery", asset=active_rows[0]["asset_id"] if active_rows else "")
    gallery_url = with_fragment(gallery_base_url, "gallery-image") if active_rows else gallery_base_url
    current_url = query_link()
    list_active = " active" if not gallery else ""
    gallery_active = " active" if gallery else ""

    def top_tab(tab, label, count):
        active = " active" if active_tab == tab else ""
        return f'<a class="tab{active}" href="{html.escape(query_link(tab=tab, sort="", view="", asset=""))}">{label} <span>{count}</span></a>'

    def media_tab(media, label, count):
        active = " active" if media_filter == media else ""
        return f'<a class="pill{active}" href="{html.escape(query_link(media=media, view="", asset=""))}">{label} <span>{count}</span></a>'

    label_options = ['<option value="">All labels</option>']
    for label in labels:
        selected = " selected" if label == label_filter else ""
        label_options.append(f'<option value="{html.escape(label)}"{selected}>{html.escape(label)}</option>')
    sort_options_markup = []
    for value, label in sort_options:
        selected = " selected" if value == active_sort else ""
        sort_options_markup.append(f'<option value="{html.escape(value)}"{selected}>{html.escape(label)}</option>')
    gallery_hidden = (
        '<input type="hidden" name="view" value="gallery">'
        f'<input type="hidden" name="asset" value="{html.escape(selected_asset)}">'
        if gallery
        else ""
    )
    filters = (
        '<form class="filters" method="get" action="/">'
        f'<input type="hidden" name="tab" value="{html.escape(active_tab)}">'
        f'<input type="hidden" name="media" value="{html.escape(media_filter)}">'
        f"{gallery_hidden}"
        '<label>Sort '
        f'<select name="sort">{"".join(sort_options_markup)}</select>'
        '</label>'
        '<label>Label '
        f'<select name="label">{"".join(label_options)}</select>'
        '</label>'
        '<label>Min score '
        f'<input name="min_score" inputmode="decimal" placeholder="0.60" value="{html.escape(min_score_raw)}">'
        '</label>'
        '<button class="filter" type="submit">Apply</button>'
        f'<a class="clear" href="{html.escape(query_link(tab=active_tab, media="all", label="", min_score="", sort="", view="", asset=""))}">Clear</a>'
        '</form>'
    )
    sidebar = f"""
      <aside class="sidebar">
        <section class="panel">
          <h2>View</h2>
          <nav class="view-switch stack">
            <a class="view-link{list_active}" href="{html.escape(list_url)}">List</a>
            <a class="view-link{gallery_active}" href="{html.escape(gallery_url)}">Gallery</a>
          </nav>
        </section>
        <section class="panel">
          <h2>Review</h2>
          <nav class="tabs stack">
            {top_tab("queue", "Queue", counts["all"])}
            {top_tab("history", "History", counts["history"])}
          </nav>
        </section>
        <section class="panel">
          <h2>Filters & Sort</h2>
          {filters}
        </section>
        <section class="panel">
          <h2>Media</h2>
          <nav class="tabs stack">
            {media_tab("all", "All", media_counts["all"])}
            {media_tab("image", "Images", media_counts["image"])}
            {media_tab("video", "Videos", media_counts["video"])}
          </nav>
        </section>
      </aside>
    """

    def action_form(asset_id, action, label, css_class, next_url=None, disabled=False, title=""):
        disabled_attr = " disabled" if disabled else ""
        title_attr = f' title="{html.escape(title)}"' if title else ""
        return (
            f'<form method="post" action="/action/{html.escape(asset_id)}/{action}">'
            f'<input type="hidden" name="csrf" value="{token}">'
            f'<input type="hidden" name="next" value="{html.escape(next_url or current_url)}">'
            f'<button class="{css_class}" type="submit"{disabled_attr}{title_attr}>{label}</button>'
            "</form>"
        )

    def detection_markup(row, asset_id, filename, link=True, large=False):
        detections = row_json(row, "detections_json", [])
        flagged_labels = set(row_json(row, "flagged_labels_json", []))
        width = row["image_width"] or 1
        height = row["image_height"] or 1
        label_size = max(18, min(48, int(min(width, height) * (0.07 if large else 0.055))))
        label_offset = max(6, int(label_size * 0.35))
        boxes = []
        chips = []
        if row_reason(row) == "archive":
            chips.append('<span class="chip archive">archived</span>')
        if row_reason(row) == "undo":
            chips.append('<span class="chip archive">undo</span>')
        for detection in detections:
            label = str(detection.get("label") or "unknown")
            score = float(detection.get("score") or 0)
            css = "flagged" if label in flagged_labels else "detected"
            chips.append(f'<span class="chip {css}">{html.escape(label)} {score:.2f}</span>')
            box = detection.get("box")
            if isinstance(box, list) and len(box) == 4:
                x, y, w, h = [html.escape(str(int(value))) for value in box]
                boxes.append(
                    f'<rect class="box {css}" x="{x}" y="{y}" width="{w}" height="{h}"></rect>'
                    f'<text class="box-label {css}" x="{x}" y="{y}" '
                    f'style="font-size: {label_size}px; transform: translateY(-{label_offset}px);">'
                    f'{html.escape(label)} {score:.2f}</text>'
                )
        chips_markup = "".join(chips) if chips else '<span class="chip">no labels</span>'
        media_class = "media large" if large else "media"
        open_tag = (
            f'<a class="{media_class}" href="{html.escape(with_fragment(query_link(view="gallery", asset=asset_id), "gallery-image"))}">'
            if link
            else f'<div class="{media_class}">'
        )
        close_tag = "</a>" if link else "</div>"
        return (
            f"{open_tag}"
            f'<img src="/thumb/{html.escape(asset_id)}" alt="{filename}">'
            f'<svg viewBox="0 0 {int(width)} {int(height)}" preserveAspectRatio="xMidYMid meet">'
            f'{"".join(boxes)}'
            '</svg>'
            f"{close_tag}"
            f'<div class="chips">{chips_markup}</div>'
        )

    def queue_actions(row, next_url=None):
        asset_id = row["asset_id"]
        if row["state"] not in ACTIONABLE_REVIEW_STATES:
            return f'<p class="meta">Action in progress: {html.escape(row["state"])}. Refresh shortly.</p>'
        unsafe_action = "move" if app.mode == "dual-account" else "lock"
        unsafe_label = "Move to NSFW Account" if app.mode == "dual-account" else "Move to Locked"
        return (
            f'{action_form(asset_id, "keep", "Keep in Timeline", "safe", next_url)} '
            f'{action_form(asset_id, unsafe_action, unsafe_label, "danger", next_url)}'
        )

    def history_actions(row):
        locked = row["state"] == "locked"
        title = "Immich API keys cannot unlock locked assets; unlock manually in Immich." if locked else ""
        return action_form(row["asset_id"], "undo", "Undo to Archive", "neutral", query_link(tab="history"), disabled=locked, title=title)

    pending_rows = []
    for row in pending:
        asset_id = row["asset_id"]
        filename = html.escape(row["original_filename"] or asset_id)
        state = html.escape(row["state"])
        media_type = html.escape(asset_type(row))
        reason = html.escape(row_reason(row).replace("_", " "))
        error = f'<p class="error">{html.escape(row["error"])}</p>' if row["error"] else ""
        media = detection_markup(row, asset_id, filename)
        pending_rows.append(
            "<article>"
            f'<div>{media}</div>'
            "<div>"
            f"<h2>{filename}</h2>"
            f'<p class="meta">state {state} | score {row["score"]:.3f} | queued {html.escape(row["created_at"])} | '
            f"type {media_type} | reason {reason} | inbox archive</p>"
            f"{error}"
            '<div class="actions">'
            f"{queue_actions(row)}"
            "</div>"
            "</div>"
            "</article>"
        )

    history_rows = []
    for row in history_rows_filtered:
        asset_id = row["asset_id"]
        filename = html.escape(row["original_filename"] or asset_id)
        error = f'<p class="error">{html.escape(row["error"])}</p>' if row["error"] else ""
        history_rows.append(
            '<article class="history-row">'
            f'<div>{detection_markup(row, asset_id, filename)}</div>'
            "<div>"
            f"<h2>{filename}</h2>"
            f'<p class="meta">decision {html.escape(row["state"])} | score {row["score"]:.3f} | decided {html.escape(row["decided_at"] or "")} | type {html.escape(asset_type(row))}</p>'
            f"{error}"
            f'<div class="actions">{history_actions(row)}</div>'
            "</div>"
            "</article>"
        )

    gallery_markup = ""
    if gallery and active_rows:
        selected_index = 0
        for index, row in enumerate(active_rows):
            if row["asset_id"] == selected_asset:
                selected_index = index
                break
        row = active_rows[selected_index]
        asset_id = row["asset_id"]
        filename = html.escape(row["original_filename"] or asset_id)
        previous_row = active_rows[(selected_index - 1) % len(active_rows)]
        next_row = active_rows[(selected_index + 1) % len(active_rows)]
        previous_url = with_fragment(query_link(view="gallery", asset=previous_row["asset_id"]), "gallery-image")
        next_url = with_fragment(query_link(view="gallery", asset=next_row["asset_id"]), "gallery-image")
        actions = queue_actions(row, next_url) if active_tab == "queue" else history_actions(row)
        error = f'<p class="error">{html.escape(row["error"])}</p>' if row["error"] else ""
        gallery_markup = f"""
        <section class="gallery-view">
          <div class="gallery-nav">
            <a href="{html.escape(previous_url)}">Previous</a>
            <span>{selected_index + 1} / {len(active_rows)}</span>
            <a href="{html.escape(next_url)}">Next</a>
          </div>
          <div id="gallery-image" class="gallery-anchor">
            {detection_markup(row, asset_id, filename, link=False, large=True)}
          </div>
          <div class="gallery-info">
            <h2>{filename}</h2>
            <p class="meta">state {html.escape(row["state"])} | score {row["score"]:.3f} | type {html.escape(asset_type(row))} | reason {html.escape(row_reason(row).replace("_", " "))}</p>
            {error}
            <div class="actions">{actions}</div>
          </div>
        </section>
        <script>
          const previousUrl = {json.dumps(previous_url)};
          const nextUrl = {json.dumps(next_url)};
          document.addEventListener('keydown', (event) => {{
            if (event.key === 'ArrowLeft') window.location.href = previousUrl;
            if (event.key === 'ArrowRight') window.location.href = nextUrl;
            if (event.key === 'Escape') window.location.href = {json.dumps(list_url)};
          }});
        </script>
        """

    if gallery:
        body_rows = gallery_markup or "<p>No assets for this view.</p>"
    elif active_tab == "history":
        body_rows = "".join(history_rows) if history_rows else "<p>No history yet.</p>"
    else:
        body_rows = "".join(pending_rows) if pending_rows else "<p>No pending assets.</p>"

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="icon" type="image/svg+xml" href="{html.escape(FAVICON_HREF, quote=True)}">
  <title>Immich NSFW Review</title>
  <style>
    :root {{ color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; }}
    body {{ margin: 0; background: #101014; color: #f3f3f7; }}
    main {{ max-width: 1440px; margin: 0 auto; padding: 32px 18px 56px; }}
    h1 {{ margin: 0; font-size: clamp(1.35rem, 2vw, 2rem); letter-spacing: -0.035em; }}
    h1 a {{ color: #f3f3f7; text-decoration: none; }}
    .page-header {{ margin-bottom: 24px; }}
    .review-layout {{ display: grid; grid-template-columns: minmax(0, 1fr) 280px; gap: 24px; align-items: start; }}
    .content {{ grid-column: 1; grid-row: 1; min-width: 0; }}
    .sidebar {{ grid-column: 2; grid-row: 1; position: sticky; top: 18px; display: grid; gap: 14px; }}
    .panel {{ border: 1px solid #2a2a36; border-radius: 22px; background: #15151d; padding: 16px; }}
    .panel h2 {{ margin: 0 0 12px; font-size: 0.9rem; color: #aaaabb; text-transform: uppercase; letter-spacing: 0.08em; }}
    .tabs, .view-switch {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 0; }}
    .stack {{ display: grid; gap: 9px; }}
    .tab, .pill, .view-link {{ color: #ccccd6; text-decoration: none; border: 1px solid #343442; background: #171720; border-radius: 999px; padding: 9px 13px; font-weight: 700; }}
    .stack .tab, .stack .pill, .stack .view-link {{ display: flex; justify-content: space-between; align-items: center; }}
    .tab span, .pill span {{ color: #858598; margin-left: 4px; }}
    .tab.active, .pill.active, .view-link.active {{ color: #ffffff; border-color: #7166ff; background: #25213e; }}
    .filters {{ display: grid; gap: 12px; }}
    .filters label {{ display: grid; gap: 6px; color: #aaaabb; font-size: 0.85rem; }}
    select, input {{ width: 100%; box-sizing: border-box; border: 1px solid #373746; border-radius: 12px; background: #0d0d12; color: #f3f3f7; padding: 9px 10px; }}
    article {{ display: grid; grid-template-columns: minmax(180px, 420px) 1fr; gap: 22px; align-items: stretch; padding: 18px; border: 1px solid #2a2a36; border-radius: 24px; background: #171720; margin: 0 0 18px; }}
    article.history-row {{ background: #15151c; }}
    .media {{ position: relative; display: block; width: 100%; height: 320px; border-radius: 18px; background: #08080a; overflow: hidden; }}
    .media.large {{ height: min(74vh, 820px); border-radius: 26px; }}
    .media img, .media svg {{ position: absolute; inset: 0; width: 100%; height: 100%; }}
    .media img {{ object-fit: contain; }}
    .media svg {{ pointer-events: none; }}
    .box {{ fill: transparent; stroke-width: 4; vector-effect: non-scaling-stroke; }}
    .box.flagged {{ stroke: #ff4d68; }}
    .box.detected {{ stroke: #f6c85f; opacity: 0.75; }}
    .box-label {{ paint-order: stroke; stroke: #08080a; stroke-width: 6px; font-weight: 900; }}
    .box-label.flagged {{ fill: #ffccd4; }}
    .box-label.detected {{ fill: #ffe6a6; }}
    .chips {{ display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }}
    .chip {{ display: inline-flex; border: 1px solid #373746; border-radius: 999px; padding: 5px 9px; color: #ccccd6; background: #20202a; font-size: 0.82rem; }}
    .chip.flagged {{ border-color: #8f3042; color: #ffd6dd; background: #3a1821; }}
    .chip.detected {{ border-color: #725e2d; color: #ffe6a6; background: #302718; }}
    .chip.archive {{ border-color: #6161a8; color: #ddd9ff; background: #242345; }}
    h2 {{ margin: 4px 0 8px; overflow-wrap: anywhere; }}
    .meta {{ color: #aaaabb; }}
    .error {{ color: #ffb0b0; background: #351d24; border: 1px solid #6b2d3d; padding: 10px 12px; border-radius: 12px; }}
    .actions {{ display: flex; flex-wrap: wrap; gap: 10px; margin-top: 20px; }}
    form {{ margin: 0; }}
    button {{ border: 0; border-radius: 999px; padding: 11px 16px; font-weight: 700; cursor: pointer; color: white; }}
    button.danger {{ background: #d64550; }}
    button.safe {{ background: #2f8f5b; }}
    button.neutral {{ background: #56566a; }}
    button.filter {{ background: #6257e8; }}
    button:disabled {{ opacity: 0.45; cursor: not-allowed; }}
    .clear {{ color: #aaaabb; text-decoration: none; padding: 4px 0; }}
    .gallery-view {{ display: grid; gap: 16px; }}
    .gallery-nav {{ display: flex; justify-content: space-between; align-items: center; color: #aaaabb; }}
    .gallery-nav a {{ color: #f3f3f7; text-decoration: none; border: 1px solid #343442; border-radius: 999px; padding: 9px 13px; }}
    .gallery-anchor {{ scroll-margin-top: 16px; }}
    .gallery-info {{ border: 1px solid #2a2a36; border-radius: 22px; background: #171720; padding: 18px; }}
    @media (max-width: 900px) {{ .review-layout {{ grid-template-columns: 1fr; }} .sidebar, .content {{ grid-column: auto; grid-row: auto; }} .sidebar {{ position: static; }} }}
    @media (max-width: 760px) {{ article {{ grid-template-columns: 1fr; }} .media {{ height: 260px; }} .media.large {{ height: 68vh; }} }}
  </style>
</head>
<body>
<main>
  <header class="page-header">
    <h1><a href="/">Immich NSFW Review</a></h1>
  </header>
  <div class="review-layout">
    {sidebar}
    <section class="content">
      {body_rows}
    </section>
  </div>
</main>
</body>
</html>"""


def make_handler(app):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ImmichNsfwGuard/1.0"

        def log_message(self, fmt, *args):
            LOG.info("%s - %s", self.address_string(), fmt % args)

        def authenticated(self):
            header = self.headers.get("Authorization", "")
            if not header.startswith("Basic "):
                return False
            try:
                decoded = base64.b64decode(header[6:]).decode("utf-8")
            except Exception:
                return False
            username, separator, password = decoded.partition(":")
            if not separator:
                return False
            return secretlib.compare_digest(username, app.username) and secretlib.compare_digest(password, app.password)

        def require_auth(self):
            if self.authenticated():
                return True
            self.send_response(HTTPStatus.UNAUTHORIZED)
            self.send_header("WWW-Authenticate", 'Basic realm="Immich NSFW Review"')
            self.end_headers()
            return False

        def send_text(self, status, text, content_type="text/plain; charset=utf-8"):
            body = text.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path == "/healthz":
                self.send_text(HTTPStatus.OK, "ok\n")
                return
            if not self.require_auth():
                return
            if parsed.path == "/":
                self.send_text(HTTPStatus.OK, html_page(app, parse_qs(parsed.query)), "text/html; charset=utf-8")
                return
            if parsed.path.startswith("/thumb/"):
                self.serve_asset_file(parsed.path.removeprefix("/thumb/"), "thumbnail_path")
                return
            if parsed.path.startswith("/original/"):
                self.serve_asset_file(parsed.path.removeprefix("/original/"), "original_path")
                return
            self.send_error(HTTPStatus.NOT_FOUND)

        def serve_asset_file(self, asset_id, column):
            row = app.row(asset_id)
            if not row:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            path = Path(row[column])
            if not path.exists():
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            mime_type = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", mime_type)
            self.send_header("Content-Length", str(path.stat().st_size))
            self.end_headers()
            with open(path, "rb") as handle:
                shutil.copyfileobj(handle, self.wfile)

        def do_POST(self):
            if not self.require_auth():
                return
            parsed = urlparse(self.path)
            parts = [part for part in parsed.path.split("/") if part]
            if len(parts) != 3 or parts[0] != "action":
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            asset_id, action = parts[1], parts[2]
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8")
            form = parse_qs(body)
            if form.get("csrf", [""])[0] != app.csrf_token:
                self.send_error(HTTPStatus.FORBIDDEN)
                return
            redirect = form.get("next", ["/"])[0]
            if not redirect.startswith("/") or redirect.startswith("//"):
                redirect = "/"
            try:
                if action == "keep":
                    app.keep_family(asset_id)
                elif action == "move":
                    app.move_to_target(asset_id)
                elif action == "lock":
                    app.lock_source(asset_id)
                elif action == "undo":
                    app.undo_decision(asset_id)
                else:
                    self.send_error(HTTPStatus.NOT_FOUND)
                    return
            except Exception as error:
                LOG.exception("review action failed: %s %s", action, asset_id)
                app.set_error(asset_id, error)
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", redirect)
            self.end_headers()

    return Handler


def review(config):
    app = ReviewApp(config)
    host = config.get("review_bind", "127.0.0.1")
    port = int(config.get("review_port", 2284))
    server = ThreadingHTTPServer((host, port), make_handler(app))
    server.daemon_threads = False
    server.block_on_close = True

    def shutdown(signum, _frame):
        LOG.info("received signal %s; stopping review UI", signum)
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    LOG.info("review UI listening on %s:%s", host, port)
    try:
        server.serve_forever()
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description="Immich NSFW guard")
    parser.add_argument("mode", choices=["scan", "review"])
    parser.add_argument("--config", required=True)
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    config = read_json(args.config)
    start = time.monotonic()
    if args.mode == "scan":
        scan(config)
    else:
        review(config)
    LOG.info("%s finished in %.2fs", args.mode, time.monotonic() - start)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
