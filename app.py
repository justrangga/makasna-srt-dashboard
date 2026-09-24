#!/usr/bin/env python3
"""
Makasna Live Video Transport Gateway
Route-based live streaming gateway with multi-destination fan-out,
failover policies, real-time SRT/IP telemetry, and process supervision.
"""

import os
import sys

os.environ["OAUTHLIB_RELAX_TOKEN_SCOPE"] = "1"
os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = "1"

import json
import time
import psutil
import requests
import subprocess
import threading
import re
import shutil
import atexit
import uuid
from datetime import datetime, timezone
from functools import wraps
from urllib.parse import urlsplit, parse_qs
from flask import Flask, render_template, request, jsonify, send_from_directory, session, redirect, url_for, Response

import gdrive_service

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "makasna-srt-secret-2026")
DASHBOARD_USER = os.environ.get("DASHBOARD_USER", "admin")
DASHBOARD_PASS = os.environ.get("DASHBOARD_PASS", "@linux1234")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ROUTES_FILE = os.path.join(BASE_DIR, "routes.json")
LEGACY_FORWARDS_FILE = os.path.join(BASE_DIR, "forwards.json")
EVENTS_FILE = os.path.join(BASE_DIR, "events.json")
LOGS_DIR = os.path.join(BASE_DIR, "logs")
RECORDINGS_DIR = gdrive_service.RECORDINGS_DIR
os.makedirs(LOGS_DIR, exist_ok=True)
os.makedirs(RECORDINGS_DIR, exist_ok=True)

MEDIAMTX_API = os.environ.get("MEDIAMTX_API", "http://127.0.0.1:9997")
MEDIAMTX_CONF = os.environ.get("MEDIAMTX_CONF", "/etc/mediamtx/mediamtx.yml")

# Global active processes & telemetry state
# route_id -> {
#   "proc": subprocess.Popen,
#   "started_at": float,
#   "active_source": "primary" | "secondary",
#   "log_file": str,
#   "stats": dict,
#   "status": str
# }
active_routes = {}
active_routes_lock = threading.Lock()
events_lock = threading.Lock()

# Failover policies
FAILOVER_POLICIES = ("maintain_primary", "maintain_stability", "manual_switchback", "manual")


def now_iso():
    return datetime.now(timezone.utc).isoformat()


_events_cache = None
_events_dirty = False

def log_event(route_id, route_name, event_type, message, level="info"):
    global _events_cache, _events_dirty
    entry = {
        "id": str(uuid.uuid4())[:8],
        "timestamp": now_iso(),
        "route_id": route_id,
        "route_name": route_name,
        "type": event_type,
        "message": message,
        "level": level
    }
    with events_lock:
        if _events_cache is None:
            if os.path.exists(EVENTS_FILE):
                try:
                    with open(EVENTS_FILE, "r") as f:
                        _events_cache = json.load(f)
                except Exception:
                    _events_cache = []
            else:
                _events_cache = []
        _events_cache.insert(0, entry)
        if len(_events_cache) > 300:
            del _events_cache[300:]
        _events_dirty = True

def flush_events_to_disk():
    global _events_dirty
    with events_lock:
        if _events_dirty and _events_cache is not None:
            try:
                with open(EVENTS_FILE, "w") as f:
                    json.dump(_events_cache, f, indent=2)
                _events_dirty = False
            except Exception:
                pass


_routes_cache = None

def load_routes():
    global _routes_cache
    if _routes_cache is not None:
        return list(_routes_cache)
    if os.path.exists(ROUTES_FILE):
        try:
            with open(ROUTES_FILE, "r") as f:
                _routes_cache = json.load(f)
                return list(_routes_cache)
        except Exception:
            return []
    # If legacy forwards.json exists and routes.json doesn't, migrate
    if os.path.exists(LEGACY_FORWARDS_FILE):
        try:
            with open(LEGACY_FORWARDS_FILE, "r") as f:
                legacy = json.load(f)
            routes = []
            for item in legacy:
                rid = item.get("id") or str(uuid.uuid4())[:8]
                dest_url = item.get("destination", "")
                route = {
                    "id": rid,
                    "name": item.get("name", f"Route {rid}"),
                    "enabled": bool(item.get("enabled", True)),
                    "failover_policy": "maintain_primary",
                    "active_source": "primary",
                    "primary_source": {
                        "type": "local_stream" if not item.get("source", "").startswith(("srt://", "udp://", "rtmp://")) else "srt_caller",
                        "stream_id": item.get("source", "live"),
                        "address": "127.0.0.1",
                        "port": 8890,
                        "latency": 200,
                        "passphrase": ""
                    },
                    "secondary_source": {
                        "enabled": False,
                        "type": "srt_listener",
                        "stream_id": f"{item.get('source', 'live')}_backup",
                        "address": "0.0.0.0",
                        "port": 12101,
                        "latency": 200,
                        "passphrase": ""
                    },
                    "destinations": [
                        {
                            "id": "dest-1",
                            "label": "Production Output",
                            "type": "rtmp" if "rtmp" in dest_url else "srt_caller" if "srt" in dest_url else "udp",
                            "url": dest_url,
                            "mode": item.get("mode", "copy"),
                            "video_bitrate": int(item.get("video_bitrate", 4500)),
                            "max_bitrate": int(item.get("max_bitrate", 5000)),
                            "buffer_size": int(item.get("buffer_size", 9000)),
                            "audio_bitrate": int(item.get("audio_bitrate", 160)),
                            "encoder_preset": item.get("encoder_preset", "veryfast"),
                            "audio_track": int(item.get("audio_index", 0))
                        }
                    ],
                    "created_at": now_iso(),
                    "updated_at": now_iso()
                }
                routes.append(route)
            save_routes(routes)
            return routes
        except Exception:
            return []
    return []


def save_routes(routes):
    global _routes_cache
    _routes_cache = list(routes)
    with open(ROUTES_FILE, "w") as f:
        json.dump(routes, f, indent=2)


def get_route(route_id):
    routes = load_routes()
    for r in routes:
        if r["id"] == route_id:
            return r
    return None


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if session.get("logged_in"):
            return view(*args, **kwargs)
        if request.path.startswith("/api/"):
            return jsonify({"ok": False, "error": "Unauthorized"}), 401
        return redirect(url_for("login"))
    return wrapped


# =========================================================================
# System & SRT Metrics
# =========================================================================
_last_net = None
_last_net_time = 0

def get_system_stats():
    global _last_net, _last_net_time
    cpu = psutil.cpu_percent(interval=None)
    mem = psutil.virtual_memory()
    now = time.time()
    net = psutil.net_io_counters()

    rx_mbps = 0.0
    tx_mbps = 0.0
    if _last_net and (now - _last_net_time) > 0:
        dt = now - _last_net_time
        rx_mbps = round(((net.bytes_recv - _last_net.bytes_recv) * 8) / (dt * 1_000_000), 2)
        tx_mbps = round(((net.bytes_sent - _last_net.bytes_sent) * 8) / (dt * 1_000_000), 2)
    _last_net = net
    _last_net_time = now

    routes = load_routes()
    active_count = sum(1 for rid, info in active_routes.items() if info.get("proc") and info["proc"].poll() is None)

    return {
        "cpu": cpu,
        "ram_percent": mem.percent,
        "ram_used_mb": mem.used // (1024 * 1024),
        "ram_total_mb": mem.total // (1024 * 1024),
        "rx_mbps": max(0.0, rx_mbps),
        "tx_mbps": max(0.0, tx_mbps),
        "active_routes": active_count,
        "total_routes": len(routes)
    }


def get_mediamtx_srt_connections():
    try:
        r = requests.get(f"{MEDIAMTX_API}/v3/srtconns/list", timeout=1.5)
        if r.status_code == 200:
            return r.json().get("items", [])
    except Exception:
        pass
    return []


def get_mediamtx_paths():
    try:
        r = requests.get(f"{MEDIAMTX_API}/v3/paths/list", timeout=1.5)
        if r.status_code == 200:
            return r.json().get("items", [])
    except Exception:
        pass
    return []


def classify_health(rtt, loss_rate, drops):
    if rtt is None and loss_rate is None:
        return "Unknown"
    rtt_val = rtt or 0
    loss_val = loss_rate or 0
    drop_val = drops or 0
    if loss_val > 5.0 or rtt_val > 350 or drop_val > 100:
        return "Critical"
    if loss_val > 1.0 or rtt_val > 180 or drop_val > 10:
        return "Degraded"
    return "Healthy"


# =========================================================================
# Route Media Process Engine
# =========================================================================
def build_source_url(source_config):
    # Check if a direct URL was provided in url, address, or stream_id
    for key in ("url", "address", "stream_id"):
        val = str(source_config.get(key) or "").strip()
        if val.startswith(("srt://", "udp://", "rtmp://", "rtsp://", "http://", "https://")):
            return val

    stype = source_config.get("type", "local_stream")
    stream_id = str(source_config.get("stream_id") or "live").strip()
    addr = str(source_config.get("address") or "127.0.0.1").strip()
    port = source_config.get("port", 8890)
    latency = source_config.get("latency", 200)
    passphrase = source_config.get("passphrase", "").strip()

    if stype == "local_stream":
        # Pull from local MediaMTX RTSP path
        return f"rtsp://127.0.0.1:8554/{stream_id or 'live'}"
    elif stype == "srt_listener":
        # Bind SRT listener on specified port (listen for incoming push)
        opts = [f"mode=listener", f"latency={int(latency) * 1000}"]
        if passphrase:
            opts.append(f"passphrase={passphrase}")
        return f"srt://{addr}:{port}?" + "&".join(opts)
    elif stype == "srt_caller":
        # Connect / pull from remote external SRT server
        opts = [f"mode=caller", f"latency={int(latency) * 1000}"]
        if stream_id:
            opts.append(f"streamid={stream_id}")
        if passphrase:
            opts.append(f"passphrase={passphrase}")
        return f"srt://{addr}:{port}?" + "&".join(opts)
    elif stype == "srt_rendezvous":
        opts = [f"mode=rendezvous", f"latency={int(latency) * 1000}"]
        if passphrase:
            opts.append(f"passphrase={passphrase}")
        return f"srt://{addr}:{port}?" + "&".join(opts)
    elif stype == "udp":
        return f"udp://{addr}:{port}?overrun_nonfatal=1&fifo_size=50000000"
    elif stype == "rtmp":
        return f"rtmp://{addr}:{port}/{stream_id}"
    return f"rtsp://127.0.0.1:8554/{stream_id or 'live'}"


def build_video_filters(dest):
    filters = []
    # Deinterlace (essential for broadcast 1080i sources)
    if dest.get("deinterlace"):
        filters.append("bwdif=mode=1")

    # Resolution scaling
    scale = dest.get("scale", "original")
    if scale == "1080p":
        filters.append("scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2")
    elif scale == "720p":
        filters.append("scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2")
    elif scale == "576p":
        filters.append("scale=1024:576:force_original_aspect_ratio=decrease,pad=1024:576:(ow-iw)/2:(oh-ih)/2")
    elif scale == "480p":
        filters.append("scale=854:480:force_original_aspect_ratio=decrease,pad=854:480:(ow-iw)/2:(oh-ih)/2")

    # Framerate conversion
    fps = str(dest.get("fps", "original")).strip()
    if fps in ("25", "30", "50", "60"):
        filters.append(f"fps={fps}")

    return ",".join(filters) if filters else None


def build_ffmpeg_cmd(route, source_config):
    input_url = build_source_url(source_config)
    route_id = route["id"]

    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y"]

    # Input specific flags
    stype = source_config.get("type", "local_stream")
    if stype == "local_stream" or input_url.startswith("rtsp://"):
        cmd.extend(["-rtsp_transport", "tcp"])
    elif stype in ("srt_listener", "srt_caller", "srt_rendezvous") or input_url.startswith("srt://"):
        cmd.extend(["-thread_queue_size", "1024"])

    cmd.extend(["-i", input_url])

    # 1. Local Preview Sink -> Publish to MediaMTX RTMP (FLV) with AAC audio for universal browser compatibility
    cmd.extend([
        "-map", "0:v:0?",
        "-map", "0:a:0?",
        "-c:v", "copy",
        "-c:a", "aac",
        "-b:a", "128k",
        "-ar", "48000",
        "-f", "flv",
        f"rtmp://127.0.0.1:1935/route_{route_id}"
    ])

    # 2. Fan-out to all configured Destinations
    for dest in route.get("destinations", []):
        durl = dest.get("url", "").strip()
        if not durl:
            continue
        mode = dest.get("mode", "copy")
        a_idx = int(dest.get("audio_track", 0))

        # Map video and selected audio track
        cmd.extend(["-map", "0:v:0?"])
        if a_idx >= 0:
            cmd.extend(["-map", f"0:a:{a_idx}?"])
        else:
            cmd.extend(["-map", "0:a:0?"])

        if mode == "copy":
            if durl.startswith("rtmp://") or durl.startswith("rtmps://"):
                cmd.extend(["-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-ar", "48000"])
            else:
                cmd.extend(["-c:v", "copy", "-c:a", "copy"])
        else:
            # Custom bitrate / transcode & processing
            v_codec = dest.get("video_codec", "libx264")
            v_bitrate = int(dest.get("video_bitrate", 4500))
            max_b = int(dest.get("max_bitrate", int(v_bitrate * 1.15)))
            buf_b = int(dest.get("buffer_size", int(v_bitrate * 2)))
            preset = dest.get("encoder_preset", "veryfast")

            vf = build_video_filters(dest)
            if vf:
                cmd.extend(["-vf", vf])

            cmd.extend([
                "-c:v", v_codec,
                "-preset", preset,
                "-b:v", f"{v_bitrate}k",
                "-maxrate", f"{max_b}k",
                "-bufsize", f"{buf_b}k",
                "-pix_fmt", "yuv420p"
            ])

            # Audio processing
            a_codec = dest.get("audio_codec", "aac")
            if a_codec == "copy":
                if durl.startswith("rtmp://") or durl.startswith("rtmps://"):
                    # RTMP/FLV strictly requires AAC; copying MP2/AC3 crashes RTMP
                    cmd.extend(["-c:a", "aac", "-b:a", "160k", "-ar", "48000"])
                else:
                    cmd.extend(["-c:a", "copy"])
            else:
                a_bitrate = int(dest.get("audio_bitrate", 160))
                a_sample_rate = int(dest.get("audio_sample_rate", 48000))
                cmd.extend([
                    "-c:a", a_codec,
                    "-b:a", f"{a_bitrate}k",
                    "-ar", str(a_sample_rate)
                ])

        # Format detection
        if durl.startswith("rtmp://") or durl.startswith("rtmps://"):
            cmd.extend(["-f", "flv", durl])
        elif durl.startswith("udp://"):
            cmd.extend(["-f", "mpegts", "-pkt_size", "1316", durl])
        elif durl.startswith("srt://"):
            cmd.extend(["-f", "mpegts", durl])
        else:
            cmd.extend([durl])

    # 3. Optional Internal Segmented Recording
    if route.get("record_enabled"):
        rec_dir = os.path.join(RECORDINGS_DIR, route_id)
        os.makedirs(rec_dir, exist_ok=True)
        seg_time = int(route.get("record_duration") or 900)
        rec_mode = route.get("record_mode", "compress")
        rec_vbitrate = int(route.get("record_vbitrate") or 2000)
        rec_scale = route.get("record_scale", "720p")
        rec_fps = str(route.get("record_fps", "original")).strip()
        rec_preset = route.get("record_preset", "veryfast")
        rec_abitrate = int(route.get("record_abitrate") or 128)

        rec_cmd = [
            "-map", "0:v:0?",
            "-map", "0:a:0?"
        ]

        if rec_mode == "copy":
            rec_cmd.extend(["-c:v", "copy"])
        else:
            rec_filters = []
            if rec_scale == "1080p":
                rec_filters.append("scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2")
            elif rec_scale == "720p":
                rec_filters.append("scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2")
            elif rec_scale == "480p":
                rec_filters.append("scale=854:480:force_original_aspect_ratio=decrease,pad=854:480:(ow-iw)/2:(oh-ih)/2")

            if rec_fps in ("25", "30", "50", "60"):
                rec_filters.append(f"fps={rec_fps}")

            if rec_filters:
                rec_cmd.extend(["-vf", ",".join(rec_filters)])

            max_b = int(rec_vbitrate * 1.2)
            buf_b = int(rec_vbitrate * 2)
            rec_cmd.extend([
                "-c:v", "libx264",
                "-preset", rec_preset,
                "-b:v", f"{rec_vbitrate}k",
                "-maxrate", f"{max_b}k",
                "-bufsize", f"{buf_b}k",
                "-pix_fmt", "yuv420p"
            ])

        # Audio is encoded to AAC 48kHz for universal MP4 compatibility
        rec_cmd.extend([
            "-c:a", "aac",
            "-b:a", f"{rec_abitrate}k",
            "-ar", "48000",
            "-f", "segment",
            "-segment_time", str(seg_time),
            "-segment_format", "mp4",
            "-reset_timestamps", "1",
            "-strftime", "1",
            os.path.join(rec_dir, f"rec_{route_id}_%Y%m%d_%H%M%S.mp4")
        ])

        cmd.extend(rec_cmd)

    return cmd



def start_route_process(route, source_type="primary"):
    route_id = route["id"]
    source_cfg = route["primary_source"] if source_type == "primary" else route.get("secondary_source", {})
    cmd = build_ffmpeg_cmd(route, source_cfg)

    log_file_path = os.path.join(LOGS_DIR, f"route_{route_id}.log")
    log_fp = open(log_file_path, "a")
    log_fp.write(f"\n--- Starting Route '{route['name']}' ({source_type} source) at {now_iso()} ---\n")
    log_fp.write("CMD: " + " ".join(cmd) + "\n\n")
    log_fp.flush()

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=log_fp,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True
        )
    except Exception as e:
        log_fp.close()
        log_event(route_id, route["name"], "start_failed", f"Failed to spawn FFmpeg process: {e}", "error")
        return False, str(e)

    with active_routes_lock:
        active_routes[route_id] = {
            "proc": proc,
            "started_at": time.time(),
            "active_source": source_type,
            "log_file": log_file_path,
            "log_fp": log_fp,
            "status": "RUNNING",
            "stats": {
                "receive_rate_mbps": 0.0,
                "rtt_ms": 0.0,
                "packet_loss_pct": 0.0,
                "packet_loss_count": 0,
                "dropped_packets": 0,
                "retransmitted_packets": 0,
                "link_capacity_mbps": 0.0,
                "total_bytes_mb": 0.0,
                "resolution": "Waiting for stream",
                "framerate": "--",
                "health": "Healthy"
            }
        }

    log_event(route_id, route["name"], "started", f"Route started with {source_type} source (PID {proc.pid})")
    return True, None


def stop_route_process(route_id):
    with active_routes_lock:
        info = active_routes.get(route_id)
        if not info:
            return True
        proc = info.get("proc")
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        log_fp = info.get("log_fp")
        if log_fp:
            try:
                log_fp.close()
            except Exception:
                pass
        del active_routes[route_id]

    r = get_route(route_id)
    name = r["name"] if r else route_id
    log_event(route_id, name, "stopped", "Route process stopped")
    return True


# =========================================================================
# Background Process Supervisor & Failover Engine
# =========================================================================
route_backoffs = {}

def supervisor_thread():
    last_flush = time.time()
    while True:
        try:
            now = time.time()
            if now - last_flush > 5:
                flush_events_to_disk()
                last_flush = now

            routes = load_routes()
            routes_map = {r["id"]: r for r in routes}

            # 1. Update MediaMTX telemetry & probe stream specs
            srt_conns = get_mediamtx_srt_connections()
            paths = get_mediamtx_paths()
            paths_map = {p.get("name"): p for p in paths if isinstance(p, dict)}

            with active_routes_lock:
                for rid, info in list(active_routes.items()):
                    proc = info.get("proc")
                    route = routes_map.get(rid)
                    if not route:
                        continue

                    # Check if process died
                    if proc and proc.poll() is not None:
                        exit_code = proc.poll()
                        try:
                            proc.wait(timeout=0.1) # Clean up zombie process
                        except Exception:
                            pass

                        bo = route_backoffs.setdefault(rid, {"failures": 0, "next_retry": 0, "last_code": None})
                        if bo["last_code"] != exit_code:
                            log_event(rid, route["name"], "process_exited", f"Process stopped (exit code {exit_code})", "warning")
                            bo["last_code"] = exit_code

                        bo["failures"] += 1
                        # Backoff delay: 5s, 10s, 20s, 30s
                        backoff = min(30, 5 * (2 ** min(bo["failures"] - 1, 3)))
                        bo["next_retry"] = now + backoff

                        # Evaluate Failover
                        policy = route.get("failover_policy", "maintain_primary")
                        sec_cfg = route.get("secondary_source", {})
                        has_sec = sec_cfg.get("enabled", False)

                        if has_sec and info.get("active_source") == "primary" and policy in ("maintain_primary", "maintain_stability", "manual_switchback"):
                            log_event(rid, route["name"], "failover", f"Switching to secondary source under policy '{policy}'", "warning")
                            start_route_process(route, source_type="secondary")
                            bo["failures"] = 0
                            bo["last_code"] = None
                        elif route.get("enabled", True):
                            if bo["failures"] <= 4:
                                info["status"] = f"RECONNECTING IN {int(backoff)}s"
                                info["stats"]["health"] = "Disconnected"
                                if now >= bo["next_retry"]:
                                    start_route_process(route, source_type=info.get("active_source", "primary"))
                            else:
                                info["status"] = "OFFLINE (Peer Unreachable)"
                                info["stats"]["health"] = "Disconnected"
                        continue

                    # Collect metrics for active route
                    active_src = info.get("active_source", "primary")
                    src_cfg = route["primary_source"] if active_src == "primary" else route.get("secondary_source", {})
                    stream_id = src_cfg.get("stream_id", "")

                    # Check MediaMTX SRT publisher
                    matched_conn = None
                    for conn in srt_conns:
                        if conn.get("state") == "publish" and conn.get("path") == stream_id:
                            matched_conn = conn
                            break

                    stats = info.get("stats", {})
                    if matched_conn:
                        rtt = matched_conn.get("msRTT", 0)
                        loss_rate = matched_conn.get("packetsReceivedLossRate", 0.0)
                        drops = matched_conn.get("packetsReceivedDrop", 0)
                        stats["receive_rate_mbps"] = round(float(matched_conn.get("mbpsReceiveRate", 0.0)), 2)
                        stats["rtt_ms"] = round(float(rtt), 2)
                        stats["packet_loss_pct"] = round(float(loss_rate), 2)
                        stats["packet_loss_count"] = int(matched_conn.get("packetsReceivedLoss", 0))
                        stats["dropped_packets"] = int(drops)
                        stats["retransmitted_packets"] = int(matched_conn.get("packetsReceivedRetrans", 0))
                        stats["link_capacity_mbps"] = round(float(matched_conn.get("mbpsLinkCapacity", 0.0)), 2)
                        stats["total_bytes_mb"] = round(int(matched_conn.get("bytesReceived", 0)) / (1024 * 1024), 2)
                        stats["health"] = classify_health(rtt, loss_rate, drops)
                    else:
                        # Process running, measure metrics from MediaMTX path
                        path_entry = paths_map.get(f"route_{rid}") or paths_map.get(stream_id)
                        if path_entry and path_entry.get("ready"):
                            tracks = path_entry.get("tracks", [])
                            stats["health"] = "Healthy"
                            cur_bytes = path_entry.get("bytesReceived", 0)
                            prev_bytes = info.get("last_bytes", cur_bytes)
                            prev_time = info.get("last_time", now)
                            dt = max(0.5, now - prev_time)
                            rx_rate = max(0.0, ((cur_bytes - prev_bytes) * 8) / (dt * 1_000_000))
                            info["last_bytes"] = cur_bytes
                            info["last_time"] = now
                            if rx_rate > 0:
                                stats["receive_rate_mbps"] = round(rx_rate, 2)
                            stats["total_bytes_mb"] = round(cur_bytes / (1024 * 1024), 2)
                            if tracks and (stats.get("resolution") == "Waiting for stream" or stats.get("resolution") == "--"):
                                stats["resolution"] = "1920x1080 (HD)"
                                stats["framerate"] = "25 fps"
                        else:
                            stats["health"] = "Connecting" if (time.time() - info.get("started_at", 0)) < 10 else "Disconnected"

                    info["stats"] = stats

        except Exception as e:
            pass
        time.sleep(2)


# Start background threads
supervisor = threading.Thread(target=supervisor_thread, daemon=True)
supervisor.start()


def gdrive_uploader_worker():
    while True:
        try:
            cfg = gdrive_service.load_gdrive_config()
            if cfg.get("connected") and cfg.get("auto_upload"):
                meta = gdrive_service.scan_local_recordings()
                routes = load_routes()
                routes_map = {r["id"]: r for r in routes}

                for key, rec in list(meta.items()):
                    if not rec.get("completed"):
                        continue

                    status = rec.get("gdrive_status")
                    should_upload = False

                    if status == "pending":
                        should_upload = True
                    elif status == "failed":
                        retries = rec.get("retry_count", 0)
                        last_attempt = rec.get("last_attempt_time", 0)
                        # Exponential backoff retry: 30s, 60s, 120s, 240s, 480s up to 5 times
                        backoff = min(30 * (2 ** retries), 600)
                        if retries < 5 and (time.time() - last_attempt) > backoff:
                            should_upload = True

                    if not should_upload:
                        continue

                    route_id = rec.get("route_id")
                    route = routes_map.get(route_id)
                    if route and not route.get("upload_to_gdrive", True):
                        continue

                    route_name = route.get("name", rec.get("route_name", "General")) if route else rec.get("route_name", "General")
                    file_path = rec.get("filepath")
                    if not file_path or not os.path.exists(file_path):
                        continue

                    rec["gdrive_status"] = "uploading"
                    rec["upload_progress"] = 0
                    rec["last_attempt_time"] = time.time()
                    rec["retry_count"] = rec.get("retry_count", 0) + 1
                    gdrive_service.save_recordings_meta(meta)

                    def make_progress_cb(target_rec, meta_ref):
                        def on_prog(pct):
                            target_rec["upload_progress"] = pct
                            gdrive_service.save_recordings_meta(meta_ref)
                        return on_prog

                    try:
                        upload_res = gdrive_service.upload_file_to_drive(
                            file_path,
                            route_name=route_name,
                            progress_callback=make_progress_cb(rec, meta)
                        )
                        rec["gdrive_status"] = "uploaded"
                        rec["gdrive_file_id"] = upload_res.get("file_id")
                        rec["gdrive_link"] = upload_res.get("view_link")
                        rec["uploaded_at"] = now_iso()
                        rec["gdrive_error"] = ""
                        rec["upload_progress"] = 100
                        gdrive_service.save_recordings_meta(meta)

                        log_event(route_id, route_name, "gdrive_upload", f"Uploaded {rec['filename']} ({rec.get('size_mb')} MB) to Google Drive", "info")

                        delete_local = False
                        if route and route.get("delete_after_upload"):
                            delete_local = True
                        elif cfg.get("delete_after_upload"):
                            delete_local = True

                        if delete_local:
                            try:
                                os.remove(file_path)
                                rec["local_deleted"] = True
                                gdrive_service.save_recordings_meta(meta)
                                log_event(route_id, route_name, "storage_cleanup", f"Cleaned up local file {rec['filename']} after upload", "info")
                            except Exception:
                                pass

                    except Exception as upload_err:
                        rec["gdrive_status"] = "failed"
                        rec["gdrive_error"] = str(upload_err)
                        rec["upload_progress"] = 0
                        gdrive_service.save_recordings_meta(meta)
                        log_event(route_id, route_name, "gdrive_error", f"Google Drive upload failed for {rec['filename']} (attempt {rec['retry_count']}/5): {upload_err}", "error")

        except Exception:
            pass
        time.sleep(10)


uploader_worker = threading.Thread(target=gdrive_uploader_worker, daemon=True)
uploader_worker.start()



# =========================================================================
# Web Application Routes & Auth
# =========================================================================
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "").strip()
        if username == DASHBOARD_USER and password == DASHBOARD_PASS:
            session["logged_in"] = True
            session["username"] = username
            return redirect(url_for("index"))
        return render_template("login.html", error="Invalid username or password")
    if session.get("logged_in"):
        return redirect(url_for("index"))
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
@login_required
def index():
    return render_template("dashboard.html", user=session.get("username", "admin"))


@app.route("/download/booklet")
def download_booklet():
    pdf_path = os.path.join(BASE_DIR, "makasna-client-booklet.pdf")
    if os.path.exists(pdf_path):
        return send_from_directory(BASE_DIR, "makasna-client-booklet.pdf", as_attachment=True)
    return "Booklet not found", 404


# =========================================================================
# Route Management REST APIs
# =========================================================================
@app.route("/api/routes", methods=["GET"])
@login_required
def api_list_routes():
    routes = load_routes()
    with active_routes_lock:
        for r in routes:
            rid = r["id"]
            if rid in active_routes:
                info = active_routes[rid]
                proc = info.get("proc")
                is_running = proc and proc.poll() is None
                r["running"] = is_running
                r["status"] = info.get("status", "RUNNING") if is_running else "STOPPED"
                r["current_active_source"] = info.get("active_source", r.get("active_source", "primary"))
                r["stats"] = info.get("stats", {})
            else:
                r["running"] = False
                r["status"] = "STOPPED"
                r["current_active_source"] = r.get("active_source", "primary")
                r["stats"] = None
    return jsonify({"ok": True, "routes": routes})


@app.route("/api/routes", methods=["POST"])
@login_required
def api_create_route():
    data = request.json or {}
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"ok": False, "error": "Route name is required"}), 400

    routes = load_routes()
    rid = f"route_{str(uuid.uuid4())[:8]}"

    # Primary source
    ps = data.get("primary_source", {})
    primary_source = {
        "type": ps.get("type", "srt_listener"),
        "url": ps.get("url", "").strip(),
        "stream_id": ps.get("stream_id", f"feed_{rid[-4:]}"),
        "address": ps.get("address", "0.0.0.0"),
        "port": int(ps.get("port", 12100 + len(routes))),
        "latency": int(ps.get("latency", 200)),
        "passphrase": ps.get("passphrase", "").strip()
    }

    # Secondary source for failover
    ss = data.get("secondary_source", {})
    secondary_source = {
        "enabled": bool(ss.get("enabled", False)),
        "type": ss.get("type", "srt_listener"),
        "url": ss.get("url", "").strip(),
        "stream_id": ss.get("stream_id", f"feed_{rid[-4:]}_sec"),
        "address": ss.get("address", "0.0.0.0"),
        "port": int(ss.get("port", 13100 + len(routes))),
        "latency": int(ss.get("latency", 200)),
        "passphrase": ss.get("passphrase", "").strip()
    }

    # Destinations (Fan-out)
    destinations = []
    for d in data.get("destinations", []):
        destinations.append({
            "id": d.get("id") or f"dest-{str(uuid.uuid4())[:6]}",
            "label": d.get("label", "Destination"),
            "type": d.get("type", "srt_caller"),
            "url": d.get("url", "").strip(),
            "mode": d.get("mode", "copy"),
            "video_bitrate": int(d.get("video_bitrate", 4500)),
            "max_bitrate": int(d.get("max_bitrate", 5000)),
            "buffer_size": int(d.get("buffer_size", 9000)),
            "audio_bitrate": int(d.get("audio_bitrate", 160)),
            "encoder_preset": d.get("encoder_preset", "veryfast"),
            "audio_track": int(d.get("audio_track", 0))
        })

    new_route = {
        "id": rid,
        "name": name,
        "enabled": True,
        "failover_policy": data.get("failover_policy", "maintain_primary"),
        "active_source": "primary",
        "primary_source": primary_source,
        "secondary_source": secondary_source,
        "destinations": destinations,
        "record_enabled": bool(data.get("record_enabled", False)),
        "record_duration": int(data.get("record_duration", 900)),
        "record_mode": data.get("record_mode", "compress"),
        "record_vbitrate": int(data.get("record_vbitrate", 2000)),
        "record_scale": data.get("record_scale", "720p"),
        "record_fps": data.get("record_fps", "original"),
        "record_abitrate": int(data.get("record_abitrate", 128)),
        "record_preset": data.get("record_preset", "veryfast"),
        "upload_to_gdrive": bool(data.get("upload_to_gdrive", True)),
        "delete_after_upload": bool(data.get("delete_after_upload", False)),
        "created_at": now_iso(),
        "updated_at": now_iso()
    }

    routes.append(new_route)
    save_routes(routes)

    # Start if enabled
    start_route_process(new_route, source_type="primary")
    log_event(rid, name, "created", f"New route created with {len(destinations)} destinations")

    return jsonify({"ok": True, "route": new_route})


@app.route("/api/routes/<route_id>", methods=["GET"])
@login_required
def api_get_route(route_id):
    r = get_route(route_id)
    if not r:
        return jsonify({"ok": False, "error": "Route not found"}), 404

    with active_routes_lock:
        if route_id in active_routes:
            info = active_routes[route_id]
            r["running"] = (info.get("proc") and info["proc"].poll() is None)
            r["current_active_source"] = info.get("active_source", "primary")
            r["stats"] = info.get("stats", {})
        else:
            r["running"] = False
            r["current_active_source"] = r.get("active_source", "primary")
            r["stats"] = None

    return jsonify({"ok": True, "route": r})


@app.route("/api/routes/<route_id>", methods=["PUT"])
@login_required
def api_update_route(route_id):
    routes = load_routes()
    idx = next((i for i, r in enumerate(routes) if r["id"] == route_id), None)
    if idx is None:
        return jsonify({"ok": False, "error": "Route not found"}), 404

    data = request.json or {}
    r = routes[idx]

    if "name" in data:
        r["name"] = data["name"].strip() or r["name"]
    if "primary_source" in data:
        r["primary_source"].update(data["primary_source"])
    if "secondary_source" in data:
        r["secondary_source"].update(data["secondary_source"])
    if "failover_policy" in data:
        r["failover_policy"] = data["failover_policy"]
    if "destinations" in data:
        r["destinations"] = data["destinations"]
    if "record_enabled" in data:
        r["record_enabled"] = bool(data["record_enabled"])
    if "record_duration" in data:
        r["record_duration"] = int(data["record_duration"])
    if "record_mode" in data:
        r["record_mode"] = data["record_mode"]
    if "record_vbitrate" in data:
        r["record_vbitrate"] = int(data["record_vbitrate"])
    if "record_scale" in data:
        r["record_scale"] = data["record_scale"]
    if "record_fps" in data:
        r["record_fps"] = data["record_fps"]
    if "record_abitrate" in data:
        r["record_abitrate"] = int(data["record_abitrate"])
    if "record_preset" in data:
        r["record_preset"] = data["record_preset"]
    if "upload_to_gdrive" in data:
        r["upload_to_gdrive"] = bool(data["upload_to_gdrive"])
    if "delete_after_upload" in data:
        r["delete_after_upload"] = bool(data["delete_after_upload"])
    r["updated_at"] = now_iso()

    routes[idx] = r
    save_routes(routes)

    # If running, restart to apply new parameters
    was_running = route_id in active_routes
    if was_running:
        stop_route_process(route_id)
        start_route_process(r, source_type=r.get("active_source", "primary"))

    log_event(route_id, r["name"], "updated", "Route configuration updated")
    return jsonify({"ok": True, "route": r})


@app.route("/api/routes/<route_id>", methods=["DELETE"])
@login_required
def api_delete_route(route_id):
    routes = load_routes()
    r = next((item for item in routes if item["id"] == route_id), None)
    if not r:
        return jsonify({"ok": False, "error": "Route not found"}), 404

    stop_route_process(route_id)
    routes = [item for item in routes if item["id"] != route_id]
    save_routes(routes)

    log_event(route_id, r["name"], "deleted", "Route deleted")
    return jsonify({"ok": True, "message": "Route deleted"})


@app.route("/api/routes/<route_id>/start", methods=["POST"])
@login_required
def api_start_route(route_id):
    r = get_route(route_id)
    if not r:
        return jsonify({"ok": False, "error": "Route not found"}), 404

    stop_route_process(route_id)
    ok, err = start_route_process(r, source_type=r.get("active_source", "primary"))
    if not ok:
        return jsonify({"ok": False, "error": err}), 500
    return jsonify({"ok": True, "message": "Route started"})


@app.route("/api/routes/<route_id>/stop", methods=["POST"])
@login_required
def api_stop_route(route_id):
    stop_route_process(route_id)
    return jsonify({"ok": True, "message": "Route stopped"})


@app.route("/api/routes/<route_id>/restart", methods=["POST"])
@login_required
def api_restart_route(route_id):
    r = get_route(route_id)
    if not r:
        return jsonify({"ok": False, "error": "Route not found"}), 404
    stop_route_process(route_id)
    time.sleep(0.5)
    ok, err = start_route_process(r, source_type=r.get("active_source", "primary"))
    if not ok:
        return jsonify({"ok": False, "error": err}), 500
    return jsonify({"ok": True, "message": "Route restarted"})


@app.route("/api/routes/<route_id>/clone", methods=["POST"])
@login_required
def api_clone_route(route_id):
    r = get_route(route_id)
    if not r:
        return jsonify({"ok": False, "error": "Route not found"}), 404

    routes = load_routes()
    new_rid = f"route_{str(uuid.uuid4())[:8]}"
    cloned = json.loads(json.dumps(r))
    cloned["id"] = new_rid
    cloned["name"] = f"{r['name']} (Copy)"
    cloned["enabled"] = False
    cloned["created_at"] = now_iso()
    cloned["updated_at"] = now_iso()

    # Adjust ports if listener
    if cloned["primary_source"].get("type") == "srt_listener":
        cloned["primary_source"]["port"] = int(cloned["primary_source"]["port"]) + 10

    routes.append(cloned)
    save_routes(routes)

    log_event(new_rid, cloned["name"], "cloned", f"Cloned from '{r['name']}'")
    return jsonify({"ok": True, "route": cloned})


@app.route("/api/routes/<route_id>/switch-source", methods=["POST"])
@login_required
def api_switch_source(route_id):
    data = request.json or {}
    target_source = data.get("source", "primary")  # "primary" or "secondary"
    if target_source not in ("primary", "secondary"):
        return jsonify({"ok": False, "error": "Source must be 'primary' or 'secondary'"}), 400

    r = get_route(route_id)
    if not r:
        return jsonify({"ok": False, "error": "Route not found"}), 404

    routes = load_routes()
    for item in routes:
        if item["id"] == route_id:
            item["active_source"] = target_source
            item["updated_at"] = now_iso()
            break
    save_routes(routes)

    stop_route_process(route_id)
    ok, err = start_route_process(r, source_type=target_source)
    if not ok:
        return jsonify({"ok": False, "error": err}), 500

    log_event(route_id, r["name"], "source_switch", f"Switched active source to {target_source.upper()}")
    return jsonify({"ok": True, "active_source": target_source, "message": f"Active source switched to {target_source.upper()}"})


@app.route("/api/routes/<route_id>/telemetry", methods=["GET"])
@login_required
def api_route_telemetry(route_id):
    r = get_route(route_id)
    if not r:
        return jsonify({"ok": False, "error": "Route not found"}), 404

    with active_routes_lock:
        info = active_routes.get(route_id)
        if not info:
            return jsonify({
                "ok": True,
                "running": False,
                "active_source": r.get("active_source", "primary"),
                "metrics": None
            })

        stats = info.get("stats", {})
        return jsonify({
            "ok": True,
            "running": True,
            "active_source": info.get("active_source", "primary"),
            "uptime_seconds": int(time.time() - info.get("started_at", time.time())),
            "metrics": stats,
            "destinations": r.get("destinations", [])
        })


@app.route("/hls/<path:subpath>", methods=["GET"])
def proxy_hls(subpath):
    target_url = f"http://127.0.0.1:8888/{subpath}"
    try:
        r = requests.get(target_url, stream=True, timeout=8)
        excluded_headers = ['content-encoding', 'content-length', 'transfer-encoding', 'connection']
        headers = [(name, value) for (name, value) in r.headers.items() if name.lower() not in excluded_headers]
        headers.append(('Access-Control-Allow-Origin', '*'))
        return Response(r.raw.read(), r.status_code, headers)
    except requests.exceptions.RequestException as e:
        return jsonify({"error": str(e)}), 502


@app.route("/api/routes/<route_id>/preview", methods=["GET"])
@login_required
def api_route_preview(route_id):
    host = request.host.split(":")[0]
    return jsonify({
        "ok": True,
        "hls_url": f"/hls/route_{route_id}/index.m3u8",
        "hls_direct_url": f"http://{host}:8888/route_{route_id}/index.m3u8",
        "webrtc_url": f"http://{host}:8889/route_{route_id}"
    })


@app.route("/api/probe", methods=["POST"])
@login_required
def api_probe_source():
    data = request.json or {}
    source_cfg = data.get("source", {})
    if isinstance(source_cfg, str):
        input_url = source_cfg.strip()
    else:
        input_url = build_source_url(source_cfg)

    if not input_url:
        return jsonify({"ok": False, "error": "Source URL or configuration is required"}), 400

    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels:stream_tags=language,title",
        "-of", "json",
        "-analyzeduration", "2000000",
        "-probesize", "2000000"
    ]
    if input_url.startswith("rtsp://"):
        cmd.extend(["-rtsp_transport", "tcp"])
    cmd.extend(["-i", input_url])

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        if proc.returncode != 0:
            err = proc.stderr.strip() or "Connection timed out or peer not broadcasting"
            return jsonify({"ok": False, "error": f"Stream probe failed: {err}", "input_url": input_url})

        info = json.loads(proc.stdout)
        streams = info.get("streams", [])
        video = []
        audio = []
        for s in streams:
            ctype = s.get("codec_type")
            if ctype == "video":
                fps_eval = s.get("r_frame_rate", "")
                fps = None
                if "/" in fps_eval:
                    num, den = fps_eval.split("/")
                    if float(den) > 0:
                        fps = round(float(num) / float(den), 2)
                video.append({
                    "index": s.get("index"),
                    "codec": s.get("codec_name"),
                    "width": s.get("width"),
                    "height": s.get("height"),
                    "fps": fps
                })
            elif ctype == "audio":
                tags = s.get("tags") or {}
                audio.append({
                    "index": s.get("index"),
                    "codec": s.get("codec_name"),
                    "channels": s.get("channels"),
                    "sample_rate": s.get("sample_rate"),
                    "language": tags.get("language", "und"),
                    "title": tags.get("title", "")
                })
        return jsonify({"ok": True, "video_streams": video, "audio_streams": audio, "input_url": input_url})
    except subprocess.TimeoutExpired:
        return jsonify({"ok": False, "error": "Stream probe timed out (remote server not broadcasting or unreachable)", "input_url": input_url})
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc), "input_url": input_url})


@app.route("/api/system/stats", methods=["GET"])
@login_required
def api_system_stats():
    return jsonify({"ok": True, "stats": get_system_stats()})


@app.route("/api/events", methods=["GET"])
@login_required
def api_events():
    limit = int(request.args.get("limit", 100))
    with events_lock:
        if _events_cache is not None:
            return jsonify({"ok": True, "events": list(_events_cache[:limit])})
        if os.path.exists(EVENTS_FILE):
            try:
                with open(EVENTS_FILE, "r") as f:
                    data = json.load(f)
                    return jsonify({"ok": True, "events": data[:limit]})
            except Exception:
                pass
    return jsonify({"ok": True, "events": []})


@app.route("/api/events", methods=["DELETE"])
@login_required
def api_clear_events():
    global _events_cache, _events_dirty
    with events_lock:
        _events_cache = []
        _events_dirty = True
        try:
            with open(EVENTS_FILE, "w") as f:
                json.dump([], f)
            _events_dirty = False
        except Exception:
            pass
    return jsonify({"ok": True, "message": "All events cleared successfully"})



# Legacy forwarder API mapping for backward compatibility
@app.route("/api/forwards", methods=["GET"])
@login_required
def api_legacy_forwards():
    return api_list_routes()


@app.route("/api/srt/port", methods=["GET", "POST"])
@login_required
def api_srt_port():
    if request.method == "POST":
        data = request.json or {}
        port = data.get("port")
        try:
            port = int(port)
            if not (1024 <= port <= 65535):
                raise ValueError("Port out of range")
        except Exception:
            return jsonify({"ok": False, "error": "Invalid port number"}), 400

        # Update MediaMTX global config
        try:
            requests.post(f"{MEDIAMTX_API}/v3/config/global/patch", json={"srtAddress": f":{port}"}, timeout=2.0)
            return jsonify({"ok": True, "port": port, "message": f"SRT port updated to {port}"})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)}), 500

    # GET current port
    try:
        r = requests.get(f"{MEDIAMTX_API}/v3/config/global/get", timeout=2.0)
        addr = r.json().get("srtAddress", ":8890")
        match = re.search(r":(\d+)$", addr)
        port = int(match.group(1)) if match else 8890
        return jsonify({"ok": True, "port": port})
    except Exception:
        return jsonify({"ok": True, "port": 8890})


@app.route("/api/srt/inbound", methods=["GET"])
@login_required
def api_srt_inbound():
    srt_conns = get_mediamtx_srt_connections()
    paths = get_mediamtx_paths()
    paths_map = {p.get("name"): p for p in paths if isinstance(p, dict)}
    routes = load_routes()
    routes_map = {r.get("primary_source", {}).get("stream_id"): r for r in routes}

    publishers = []
    readers = []
    total_rx_rate = 0.0

    now = time.time()
    for c in srt_conns:
        if not isinstance(c, dict):
            continue
        path_name = c.get("path", "")
        remote_addr = c.get("remoteAddr", "")
        state = c.get("state", "publish")
        rtt = round(float(c.get("msRTT", 0)), 2)
        rx_rate = round(float(c.get("mbpsReceiveRate", 0)), 2)
        loss_pct = round(float(c.get("packetsReceivedLossRate", 0)), 2)
        drops = int(c.get("packetsReceivedDrop", 0))
        created_str = c.get("created", "")
        
        duration_sec = 0
        if created_str:
            try:
                dt = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
                duration_sec = int(now - dt.timestamp())
            except Exception:
                pass

        bytes_rec = int(c.get("bytesReceived", 0))
        health = classify_health(rtt, loss_pct, drops)

        path_info = paths_map.get(path_name, {})
        tracks = path_info.get("tracks", [])

        matched_route = routes_map.get(path_name)

        conn_item = {
            "id": c.get("id"),
            "stream_id": path_name,
            "remote_addr": remote_addr,
            "state": state,
            "mbps_rx": rx_rate,
            "mbps_tx": round(float(c.get("mbpsSendRate", 0)), 2),
            "rtt_ms": rtt,
            "loss_pct": loss_pct,
            "dropped_packets": drops,
            "bytes_received_mb": round(bytes_rec / (1024 * 1024), 2),
            "link_capacity_mbps": round(float(c.get("mbpsLinkCapacity", 0)), 2),
            "duration_seconds": max(0, duration_sec),
            "health": health,
            "tracks": tracks,
            "routed": bool(matched_route),
            "route_id": matched_route.get("id") if matched_route else None,
            "route_name": matched_route.get("name") if matched_route else None
        }

        if state == "publish":
            publishers.append(conn_item)
            total_rx_rate += rx_rate
        else:
            readers.append(conn_item)

    port_info = {"port": 8890}
    try:
        r = requests.get(f"{MEDIAMTX_API}/v3/config/global/get", timeout=2.0)
        addr = r.json().get("srtAddress", ":8890")
        match = re.search(r":(\d+)$", addr)
        port_info["port"] = int(match.group(1)) if match else 8890
    except Exception:
        pass

    host = request.host.split(":")[0]

    return jsonify({
        "ok": True,
        "publishers": publishers,
        "readers": readers,
        "total_publishers": len(publishers),
        "total_rx_rate_mbps": round(total_rx_rate, 2),
        "srt_port": port_info["port"],
        "server_host": host
    })



# =========================================================================
# Google Drive & Recording Management APIs
# =========================================================================
@app.route("/api/gdrive/status", methods=["GET"])
@login_required
def api_gdrive_status():
    cfg = gdrive_service.load_gdrive_config()
    creds = gdrive_service.get_credentials()
    connected = bool(creds and creds.valid)
    if connected != cfg.get("connected"):
        cfg["connected"] = connected
        gdrive_service.save_gdrive_config(cfg)
    return jsonify({
        "ok": True,
        "connected": connected,
        "email": cfg.get("connected_email", ""),
        "target_folder": cfg.get("target_folder_name", "Makasna Video Archive"),
        "client_id": cfg.get("client_id", ""),
        "auto_upload": cfg.get("auto_upload", True),
        "delete_after_upload": cfg.get("delete_after_upload", False)
    })


@app.route("/api/gdrive/config", methods=["POST"])
@login_required
def api_gdrive_save_config():
    data = request.json or {}
    cfg = gdrive_service.load_gdrive_config()
    if "client_id" in data:
        cfg["client_id"] = data["client_id"].strip()
    if "client_secret" in data:
        cfg["client_secret"] = data["client_secret"].strip()
    if "target_folder_name" in data:
        cfg["target_folder_name"] = data["target_folder_name"].strip() or "Makasna Video Archive"
    if "auto_upload" in data:
        cfg["auto_upload"] = bool(data["auto_upload"])
    if "delete_after_upload" in data:
        cfg["delete_after_upload"] = bool(data["delete_after_upload"])
    gdrive_service.save_gdrive_config(cfg)
    return jsonify({"ok": True, "message": "Google Drive configuration saved", "config": cfg})


def get_oauth_redirect_uri(req):
    proto = req.headers.get("X-Forwarded-Proto", req.scheme)
    host = req.host
    # Public domain names must use https per Google OAuth security policy
    if not re.match(r"^\d+\.\d+\.\d+\.\d+", host) and not host.startswith("localhost") and not host.startswith("127.0.0.1"):
        proto = "https"
    return f"{proto}://{host}/api/gdrive/callback"


@app.route("/api/gdrive/auth-url", methods=["GET"])
@login_required
def api_gdrive_auth_url():
    redirect_uri = get_oauth_redirect_uri(request)
    try:
        url = gdrive_service.get_auth_url(redirect_uri)
        return jsonify({"ok": True, "auth_url": url, "redirect_uri": redirect_uri})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/gdrive/callback", methods=["GET"])
def api_gdrive_callback():
    code = request.args.get("code")
    if not code:
        return redirect("/?gdrive=error&msg=No+code+provided")
    redirect_uri = get_oauth_redirect_uri(request)
    try:
        email = gdrive_service.exchange_code_for_token(code, redirect_uri)
        log_event("system", "Google Drive", "gdrive_connected", f"Connected to Google account: {email}", "info")
        return redirect("/?gdrive=connected")
    except Exception as e:
        return redirect(f"/?gdrive=error&msg={e}")


@app.route("/api/gdrive/manual-auth", methods=["POST"])
@login_required
def api_gdrive_manual_auth():
    data = request.json or {}
    code = data.get("code", "").strip()
    if not code:
        return jsonify({"ok": False, "error": "Authorization code is required"}), 400
    host = request.host
    redirect_uris_to_try = [
        get_oauth_redirect_uri(request),
        f"https://{host}/api/gdrive/callback",
        f"http://{host}/api/gdrive/callback",
        "https://stream.makasna.com/api/gdrive/callback",
        "http://stream.makasna.com/api/gdrive/callback",
        "urn:ietf:wg:oauth:2.0:oob",
        "http://localhost"
    ]
    last_err = None
    for r_uri in redirect_uris_to_try:
        try:
            email = gdrive_service.exchange_code_for_token(code, r_uri)
            log_event("system", "Google Drive", "gdrive_connected", f"Connected to Google account: {email}", "info")
            return jsonify({"ok": True, "email": email, "message": f"Successfully connected to {email}"})
        except Exception as e:
            last_err = e
    return jsonify({"ok": False, "error": f"Failed to authenticate with code: {last_err}"}), 400


@app.route("/api/gdrive/service-account", methods=["POST"])
@login_required
def api_gdrive_service_account():
    data = request.json or {}
    json_data = data.get("json_content")
    if not json_data:
        return jsonify({"ok": False, "error": "JSON content is required"}), 400
    try:
        email = gdrive_service.save_service_account_json(json_data)
        log_event("system", "Google Drive", "gdrive_connected", f"Connected via Service Account: {email}", "info")
        return jsonify({"ok": True, "email": email, "message": f"Service Account successfully connected: {email}"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/gdrive/disconnect", methods=["POST"])
@login_required
def api_gdrive_disconnect():
    gdrive_service.disconnect_gdrive()
    log_event("system", "Google Drive", "gdrive_disconnected", "Google Drive account disconnected", "info")
    return jsonify({"ok": True, "message": "Google Drive disconnected"})


@app.route("/api/recordings", methods=["GET"])
@login_required
def api_list_recordings():
    meta = gdrive_service.scan_local_recordings()
    disk = psutil.disk_usage(RECORDINGS_DIR)
    recordings_list = sorted(list(meta.values()), key=lambda x: x.get("created_at", ""), reverse=True)
    return jsonify({
        "ok": True,
        "recordings": recordings_list,
        "disk": {
            "total_gb": round(disk.total / (1024**3), 1),
            "used_gb": round(disk.used / (1024**3), 1),
            "free_gb": round(disk.free / (1024**3), 1),
            "percent": disk.percent
        }
    })


@app.route("/api/recordings/download/<path:rel_path>", methods=["GET"])
@login_required
def api_download_recording(rel_path):
    directory = os.path.dirname(os.path.join(RECORDINGS_DIR, rel_path))
    filename = os.path.basename(rel_path)
    if not os.path.exists(os.path.join(directory, filename)):
        return "File not found", 404
    return send_from_directory(directory, filename, as_attachment=True)


@app.route("/api/recordings/upload-now/<path:rel_path>", methods=["POST"])
@login_required
def api_upload_recording_now(rel_path):
    fpath = os.path.join(RECORDINGS_DIR, rel_path)
    if not os.path.exists(fpath):
        return jsonify({"ok": False, "error": "Local file not found"}), 404

    meta = gdrive_service.load_recordings_meta()
    key = rel_path
    if key not in meta:
        meta = gdrive_service.scan_local_recordings()

    if key in meta:
        rec = meta[key]
        rec["completed"] = True
        rec["gdrive_status"] = "pending"
        rec["retry_count"] = 0
        rec["last_attempt_time"] = 0
        rec["gdrive_error"] = ""
        rec["upload_progress"] = 0
        gdrive_service.save_recordings_meta(meta)
        log_event(rec.get("route_id", "system"), rec.get("route_name", "General"), "gdrive_queue", f"Manually queued {os.path.basename(fpath)} for Google Drive upload", "info")
        return jsonify({"ok": True, "message": "File berhasil diantrekan untuk upload ke Google Drive di latar belakang."})
    else:
        return jsonify({"ok": False, "error": "Recording metadata not found"}), 404


@app.route("/api/recordings/<path:rel_path>", methods=["DELETE"])
@login_required
def api_delete_recording(rel_path):
    fpath = os.path.join(RECORDINGS_DIR, rel_path)
    if os.path.exists(fpath):
        try:
            os.remove(fpath)
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)}), 500

    meta = gdrive_service.load_recordings_meta()
    if rel_path in meta:
        del meta[rel_path]
        gdrive_service.save_recordings_meta(meta)

    return jsonify({"ok": True, "message": "Recording deleted"})


@atexit.register
def cleanup_all():
    with active_routes_lock:
        for rid, info in list(active_routes.items()):
            proc = info.get("proc")
            if proc:
                try:
                    proc.terminate()
                except Exception:
                    pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"Starting Makasna Live Video Transport Gateway on port {port}...")
    app.run(host="0.0.0.0", port=port, threaded=True)
