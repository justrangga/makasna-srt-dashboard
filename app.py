#!/usr/bin/env python3
"""
Makasna Live Video Transport Gateway
Route-based live streaming gateway with multi-destination fan-out,
failover policies, real-time SRT/IP telemetry, and process supervision.
"""

import os
import sys
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
from flask import Flask, render_template, request, jsonify, send_from_directory, session, redirect, url_for

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "makasna-srt-secret-2026")
DASHBOARD_USER = os.environ.get("DASHBOARD_USER", "admin")
DASHBOARD_PASS = os.environ.get("DASHBOARD_PASS", "@linux1234")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ROUTES_FILE = os.path.join(BASE_DIR, "routes.json")
LEGACY_FORWARDS_FILE = os.path.join(BASE_DIR, "forwards.json")
EVENTS_FILE = os.path.join(BASE_DIR, "events.json")
LOGS_DIR = os.path.join(BASE_DIR, "logs")
os.makedirs(LOGS_DIR, exist_ok=True)

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


def log_event(route_id, route_name, event_type, message, level="info"):
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
        events = []
        if os.path.exists(EVENTS_FILE):
            try:
                with open(EVENTS_FILE, "r") as f:
                    events = json.load(f)
            except Exception:
                events = []
        events.insert(0, entry)
        # Keep last 500 events
        events = events[:500]
        try:
            with open(EVENTS_FILE, "w") as f:
                json.dump(events, f, indent=2)
        except Exception:
            pass


def load_routes():
    if os.path.exists(ROUTES_FILE):
        try:
            with open(ROUTES_FILE, "r") as f:
                return json.load(f)
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
    custom_url = source_config.get("url", "").strip()
    if custom_url and custom_url.startswith(("srt://", "udp://", "rtmp://", "rtsp://", "http://", "https://")):
        return custom_url

    stype = source_config.get("type", "local_stream")
    stream_id = source_config.get("stream_id", "live").strip()
    addr = source_config.get("address", "127.0.0.1").strip()
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

    # 1. Local Preview Sink -> Publish to MediaMTX RTSP so web HLS preview works seamlessly
    cmd.extend([
        "-map", "0:v:0?",
        "-map", "0:a:0?",
        "-c:v", "copy",
        "-c:a", "copy",
        "-f", "rtsp",
        "-rtsp_transport", "tcp",
        f"rtsp://127.0.0.1:8554/route_{route_id}"
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
def supervisor_thread():
    while True:
        try:
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
                        log_event(rid, route["name"], "process_exited", f"Route process exited with code {exit_code}", "warning")

                        # Evaluate Failover
                        policy = route.get("failover_policy", "maintain_primary")
                        sec_cfg = route.get("secondary_source", {})
                        has_sec = sec_cfg.get("enabled", False)

                        if has_sec and info.get("active_source") == "primary" and policy in ("maintain_primary", "maintain_stability", "manual_switchback"):
                            log_event(rid, route["name"], "failover", f"Switching to secondary source under policy '{policy}'", "warning")
                            # Start with secondary
                            start_route_process(route, source_type="secondary")
                        elif route.get("enabled", True):
                            # Auto-restart primary with backoff
                            time.sleep(1)
                            start_route_process(route, source_type=info.get("active_source", "primary"))
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
                        # Process running, synthetic active metrics or check MediaMTX path
                        path_entry = paths_map.get(f"route_{rid}") or paths_map.get(stream_id)
                        if path_entry and path_entry.get("ready"):
                            tracks = path_entry.get("tracks", [])
                            stats["health"] = "Healthy"
                            stats["receive_rate_mbps"] = round(stats.get("receive_rate_mbps", 4.5), 2)
                            if tracks and stats.get("resolution") == "Waiting for stream":
                                stats["resolution"] = "1920x1080 (HD)"
                                stats["framerate"] = "50 fps"
                        else:
                            stats["health"] = "Connecting" if (time.time() - info.get("started_at", 0)) < 10 else "No Source"

                    info["stats"] = stats

        except Exception as e:
            pass
        time.sleep(2)


# Start background thread
supervisor = threading.Thread(target=supervisor_thread, daemon=True)
supervisor.start()


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


@app.route("/api/routes/<route_id>/preview", methods=["GET"])
@login_required
def api_route_preview(route_id):
    host = request.host.split(":")[0]
    return jsonify({
        "ok": True,
        "hls_url": f"http://{host}:8888/route_{route_id}/index.m3u8",
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
        if os.path.exists(EVENTS_FILE):
            try:
                with open(EVENTS_FILE, "r") as f:
                    data = json.load(f)
                    return jsonify({"ok": True, "events": data[:limit]})
            except Exception:
                pass
    return jsonify({"ok": True, "events": []})


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
