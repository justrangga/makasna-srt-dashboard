#!/usr/bin/env python3
"""
Makasna SRT & RTMP Relay Dashboard
Lightweight streaming redirector & relay manager
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
import hmac
from datetime import datetime
from functools import wraps
from urllib.parse import urlsplit
from flask import Flask, render_template, request, jsonify, send_from_directory, session, redirect, url_for

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "makasna-srt-secret-2026")
DASHBOARD_USER = os.environ.get("DASHBOARD_USER", "admin")
DASHBOARD_PASS = os.environ.get("DASHBOARD_PASS", "@linux1234")
DATA_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forwards.json")
LOGS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
os.makedirs(LOGS_DIR, exist_ok=True)

# Global process dictionary: id -> {"proc": subprocess.Popen, "started_at": timestamp, "log_file": path}
active_relays = {}
MAX_AUDIO_INDEX = 63
PROBE_TIMEOUT_SECONDS = 8
ALLOWED_SOURCE_PREFIXES = ("rtsp://", "rtmp://", "srt://", "http://")
CUSTOM_MODE = "custom"
LEGACY_TRANSCODE_MODES = ("transcode_1080p", "transcode_720p")
ALLOWED_MODES = ("copy", CUSTOM_MODE) + LEGACY_TRANSCODE_MODES
ALLOWED_ENCODER_PRESETS = ("ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow")
TRANSCODE_DEFAULTS = {
    "video_bitrate": 4500,
    "max_bitrate": 5000,
    "buffer_size": 9000,
    "audio_bitrate": 160,
    "encoder_preset": "veryfast"
}
LEGACY_720P_DEFAULTS = {
    "video_bitrate": 2500,
    "max_bitrate": 3000,
    "buffer_size": 5000,
    "audio_bitrate": 128,
    "encoder_preset": "veryfast"
}
MEDIAMTX_API = os.environ.get("MEDIAMTX_API", "http://127.0.0.1:9997")
MEDIAMTX_CONF = os.environ.get("MEDIAMTX_CONF", "/etc/mediamtx/mediamtx.yml")
STREAM_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
PREVIEW_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".runtime", "preview")
PREVIEW_TIMEOUT_SECONDS = 900
PREVIEW_LOCK = threading.RLock()
preview_state = {"proc": None, "token": None, "stream_id": None, "audio_index": None,
                 "started_at": None, "error": None, "timer": None}


def validate_integer_setting(value, name, minimum, maximum):
    if isinstance(value, bool):
        raise ValueError(f"{name} must be an integer between {minimum} and {maximum} kbps")
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        raise ValueError(f"{name} must be an integer between {minimum} and {maximum} kbps")
    if str(value).strip() != str(parsed) or not minimum <= parsed <= maximum:
        raise ValueError(f"{name} must be an integer between {minimum} and {maximum} kbps")
    return parsed


def processing_settings(forward):
    mode = forward.get("mode", "copy")
    if mode not in ALLOWED_MODES:
        raise ValueError("Mode must be copy or custom")
    if mode == "copy":
        return {"mode": "copy"}
    defaults = LEGACY_720P_DEFAULTS if mode == "transcode_720p" else TRANSCODE_DEFAULTS
    settings = {
        "mode": mode,
        "video_bitrate": validate_integer_setting(forward.get("video_bitrate", defaults["video_bitrate"]), "Video bitrate", 250, 50000),
        "max_bitrate": validate_integer_setting(forward.get("max_bitrate", defaults["max_bitrate"]), "Max bitrate", 250, 50000),
        "buffer_size": validate_integer_setting(forward.get("buffer_size", defaults["buffer_size"]), "Buffer size", 500, 100000),
        "audio_bitrate": validate_integer_setting(forward.get("audio_bitrate", defaults["audio_bitrate"]), "Audio bitrate", 32, 512),
        "encoder_preset": forward.get("encoder_preset", defaults["encoder_preset"])
    }
    if settings["max_bitrate"] < settings["video_bitrate"]:
        raise ValueError("Max bitrate must be greater than or equal to video bitrate")
    if settings["encoder_preset"] not in ALLOWED_ENCODER_PRESETS:
        raise ValueError("Encoder preset is not allowed")
    return settings


def processing_summary(forward):
    settings = processing_settings(forward)
    if settings["mode"] == "copy":
        return "Direct Copy — original bitrate"
    return (f"Custom Bitrate — {settings['video_bitrate']}/{settings['max_bitrate']}k video, "
            f"{settings['audio_bitrate']}k audio, {settings['encoder_preset']}")


def safe_destination_label(destination):
    try:
        parsed = urlsplit(destination)
        if parsed.scheme and parsed.netloc:
            return f"{parsed.scheme}://{parsed.netloc}"
    except (TypeError, ValueError):
        pass
    return "Configured target"


def normalize_source(source):
    source = source.strip()
    if not source:
        raise ValueError("Source is required")
    if not source.startswith(ALLOWED_SOURCE_PREFIXES):
        return f"rtsp://127.0.0.1:8554/{source}"
    return source

def validate_audio_index(value):
    if value is None or value == "":
        return 0
    if isinstance(value, bool):
        raise ValueError("Audio index must be a non-negative integer")
    try:
        index = int(value)
    except (TypeError, ValueError):
        raise ValueError("Audio index must be a non-negative integer")
    if str(value).strip() != str(index) or not 0 <= index <= MAX_AUDIO_INDEX:
        raise ValueError(f"Audio index must be between 0 and {MAX_AUDIO_INDEX}")
    return index

def parse_audio_streams(probe_data):
    streams = probe_data.get("streams", []) if isinstance(probe_data, dict) else []
    result = []
    for stream in streams:
        if not isinstance(stream, dict) or stream.get("codec_type") != "audio":
            continue
        tags = stream.get("tags") if isinstance(stream.get("tags"), dict) else {}
        result.append({
            "selector": len(result),
            "stream_index": stream.get("index"),
            "codec": stream.get("codec_name") or "unknown",
            "channels": stream.get("channels"),
            "channel_layout": stream.get("channel_layout"),
            "sample_rate": stream.get("sample_rate"),
            "language": tags.get("language"),
            "title": tags.get("title")
        })
    return result

def probe_audio_streams(source, timeout=PROBE_TIMEOUT_SECONDS):
    normalized_source = normalize_source(source)
    cmd = [
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_entries", "stream=index,codec_type,codec_name,channels,channel_layout,sample_rate:stream_tags=language,title"
    ]
    if normalized_source.startswith("rtsp://"):
        cmd.extend(["-rtsp_transport", "tcp"])
    cmd.append(normalized_source)
    completed = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               universal_newlines=True, timeout=timeout, check=False)
    if completed.returncode != 0:
        raise RuntimeError("Source is unavailable or has no readable media")
    try:
        return parse_audio_streams(json.loads(completed.stdout))
    except (TypeError, ValueError, json.JSONDecodeError):
        raise RuntimeError("ffprobe returned a malformed response")

def load_forwards():
    if not os.path.exists(DATA_FILE):
        return []
    try:
        with open(DATA_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return []

def save_forwards(forwards):
    with open(DATA_FILE, "w") as f:
        json.dump(forwards, f, indent=2)

def get_server_stats():
    try:
        cpu = psutil.cpu_percent(interval=None)
        if cpu is None:
            cpu = 0.0
    except Exception:
        cpu = 0.0

    try:
        mem = psutil.virtual_memory()
        ram_percent = round(mem.percent, 1)
        ram_used_mb = round(mem.used / 1024 / 1024)
        ram_total_mb = round(mem.total / 1024 / 1024)
    except Exception:
        ram_percent = 0.0
        ram_used_mb = 0
        ram_total_mb = 0

    try:
        disk = psutil.disk_usage("/")
        disk_percent = round(disk.percent, 1)
    except Exception:
        disk_percent = 0.0

    rx_speed = 0.0
    tx_speed = 0.0
    try:
        net1 = psutil.net_io_counters()
        time.sleep(0.1)
        net2 = psutil.net_io_counters()
        rx_speed = (net2.bytes_recv - net1.bytes_recv) * 8 / 1024 / 1024 / 0.1 # Mbps
        tx_speed = (net2.bytes_sent - net1.bytes_sent) * 8 / 1024 / 1024 / 0.1 # Mbps
    except Exception:
        pass
    
    # Check MediaMTX active streams
    active_streams = []
    try:
        r = requests.get(f"{MEDIAMTX_API}/v3/paths/list", timeout=1.0)
        if r.status_code == 200:
            data = r.json()
            items = data.get("items", [])
            if items:
                for item in items:
                    if item.get("ready", False):
                        active_streams.append({
                            "name": item.get("name", "stream"),
                            "ready": item.get("ready", False),
                            "tracks": len(item.get("tracks", []) or []),
                            "bytesReceived": item.get("bytesReceived", 0),
                            "readers": len(item.get("readers", []) or [])
                        })
    except Exception:
        pass
    
    return {
        "cpu": round(float(cpu), 1),
        "ram_percent": ram_percent,
        "ram_used_mb": ram_used_mb,
        "ram_total_mb": ram_total_mb,
        "disk_percent": disk_percent,
        "rx_mbps": round(float(rx_speed), 2),
        "tx_mbps": round(float(tx_speed), 2),
        "active_streams": active_streams
    }

def build_ffmpeg_command(forward):
    src = normalize_source(forward["source"])
    dest = forward["destination"]
    settings = processing_settings(forward)
    audio_index = validate_audio_index(forward.get("audio_index", 0))
    
    cmd = [
        "ffmpeg",
        "-nostdin",
        "-loglevel", "info",
        "-re",
    ]
    
    # Input options based on source
    if src.startswith("rtsp://"):
        cmd.extend(["-rtsp_transport", "tcp"])
    elif src.startswith("srt://"):
        cmd.extend(["-timeout", "5000000"])
        
    cmd.extend(["-i", src])
    cmd.extend(["-map", "0:v:0?", "-map", f"0:a:{audio_index}?"])
    
    # Video & Audio codec
    if settings["mode"] == "copy":
        cmd.extend(["-c:v", "copy", "-c:a", "copy"])
    else:
        cmd.extend([
            "-c:v", "libx264",
            "-preset", settings["encoder_preset"],
            "-b:v", f"{settings['video_bitrate']}k",
            "-maxrate", f"{settings['max_bitrate']}k",
            "-bufsize", f"{settings['buffer_size']}k",
            "-c:a", "aac",
            "-b:a", f"{settings['audio_bitrate']}k"
        ])
    
    # Output format
    if dest.startswith("rtmp://") or dest.startswith("rtmps://"):
        cmd.extend(["-f", "flv", dest])
    elif dest.startswith("srt://"):
        cmd.extend(["-f", "mpegts", dest])
    else:
        cmd.extend(["-f", "flv", dest])
        
    return cmd

def run_relay_worker(relay_id):
    while True:
        forwards = load_forwards()
        target = next((f for f in forwards if f["id"] == relay_id), None)
        if not target or not target.get("enabled", False):
            break
            
        log_file = os.path.join(LOGS_DIR, f"relay_{relay_id}.log")
        cmd = build_ffmpeg_command(target)
        
        with open(log_file, "a") as f_out:
            f_out.write(f"\n--- [ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ] Starting Relay ---\n")
            f_out.write("CMD: " + " ".join(cmd) + "\n\n")
            f_out.flush()
            
            proc = subprocess.Popen(
                cmd,
                stdout=f_out,
                stderr=subprocess.STDOUT,
                shell=False
            )
            
            active_relays[relay_id] = {
                "proc": proc,
                "started_at": time.time(),
                "log_file": log_file,
                "target": target
            }
            
            proc.wait()
            
        time.sleep(3) # auto-reconnect delay if enabled
        
        # Check if still enabled
        forwards = load_forwards()
        target = next((f for f in forwards if f["id"] == relay_id), None)
        if not target or not target.get("enabled", False):
            break

def start_relay(relay_id):
    stop_relay(relay_id)
    t = threading.Thread(target=run_relay_worker, args=(relay_id,), daemon=True)
    t.start()

def stop_relay(relay_id):
    if relay_id in active_relays:
        item = active_relays.pop(relay_id)
        proc = item.get("proc")
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=2)
            except Exception:
                proc.kill()

# Start previously enabled relays on app boot
def bootstrap_relays():
    forwards = load_forwards()
    for f in forwards:
        if f.get("enabled", False):
            start_relay(f["id"])


def validate_stream_id(value):
    if not isinstance(value, str) or not STREAM_ID_PATTERN.fullmatch(value):
        raise ValueError("Stream ID must be 1-64 letters, numbers, dots, underscores, or hyphens")
    return value


def preview_directory(token):
    if not isinstance(token, str) or not re.fullmatch(r"[a-f0-9]{32}", token):
        raise ValueError("Invalid preview token")
    path = os.path.abspath(os.path.join(PREVIEW_ROOT, token))
    root = os.path.abspath(PREVIEW_ROOT)
    if os.path.commonpath((root, path)) != root:
        raise ValueError("Invalid preview path")
    return path


def build_preview_command(stream_id, audio_index, output_dir, transcode=False):
    stream_id = validate_stream_id(stream_id)
    audio_index = validate_audio_index(audio_index)
    source = f"rtsp://127.0.0.1:8554/{stream_id}"
    playlist = os.path.join(output_dir, "index.m3u8")
    segments = os.path.join(output_dir, "segment_%05d.ts")
    command = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "warning",
               "-rtsp_transport", "tcp", "-i", source,
               "-map", "0:v:0?", "-map", f"0:a:{audio_index}?", "-sn", "-dn"]
    if transcode:
        command.extend(["-c:v", "libx264", "-preset", "veryfast", "-tune", "zerolatency",
                        "-pix_fmt", "yuv420p", "-g", "50", "-keyint_min", "50",
                        "-c:a", "aac", "-b:a", "128k"])
    else:
        command.extend(["-c:v", "copy", "-c:a", "copy", "-bsf:v", "h264_mp4toannexb"])
    command.extend(["-f", "hls", "-hls_time", "2", "-hls_list_size", "5",
                    "-hls_flags", "delete_segments+append_list+omit_endlist+independent_segments",
                    "-hls_segment_filename", segments, playlist])
    return command


def _reset_preview_state(error=None):
    timer = preview_state.get("timer")
    if timer:
        timer.cancel()
    preview_state.update({"proc": None, "token": None, "stream_id": None,
                          "audio_index": None, "started_at": None, "error": error, "timer": None})


def stop_preview():
    with PREVIEW_LOCK:
        proc = preview_state.get("proc")
        token = preview_state.get("token")
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        _reset_preview_state()
        if token:
            shutil.rmtree(preview_directory(token), ignore_errors=True)


def _watch_preview(proc, token):
    returncode = proc.wait()
    with PREVIEW_LOCK:
        if preview_state.get("proc") is proc and preview_state.get("token") == token:
            error = None if returncode == 0 else "Preview encoder exited; verify the stream and selected tracks"
            _reset_preview_state(error)


def start_preview(stream_id, audio_index):
    stream_id = validate_stream_id(stream_id)
    audio_index = validate_audio_index(audio_index)
    stop_preview()
    token = uuid.uuid4().hex
    output_dir = preview_directory(token)
    os.makedirs(output_dir, mode=0o700, exist_ok=False)
    command = build_preview_command(stream_id, audio_index, output_dir)
    try:
        proc = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                shell=False, close_fds=True)
    except OSError:
        shutil.rmtree(output_dir, ignore_errors=True)
        raise RuntimeError("FFmpeg is unavailable")
    with PREVIEW_LOCK:
        timer = threading.Timer(PREVIEW_TIMEOUT_SECONDS, stop_preview)
        timer.daemon = True
        preview_state.update({"proc": proc, "token": token, "stream_id": stream_id,
                              "audio_index": audio_index, "started_at": time.time(),
                              "error": None, "timer": timer})
        timer.start()
    threading.Thread(target=_watch_preview, args=(proc, token), daemon=True).start()
    return token


def preview_status_payload():
    with PREVIEW_LOCK:
        proc = preview_state.get("proc")
        running = bool(proc and proc.poll() is None)
        token = preview_state.get("token") if running else None
        return {"ok": True, "running": running, "ready": bool(
                    token and os.path.isfile(os.path.join(preview_directory(token), "index.m3u8"))),
                "stream_id": preview_state.get("stream_id") if running else None,
                "audio_index": preview_state.get("audio_index") if running else None,
                "playlist_url": f"/preview/{token}/index.m3u8" if token else None,
                "started_at": preview_state.get("started_at") if running else None,
                "error": preview_state.get("error")}


def _number(record, key, integer=False):
    value = record.get(key, 0)
    try:
        return int(value) if integer else round(float(value), 3)
    except (TypeError, ValueError):
        return 0 if integer else 0.0


def classify_srt_health(rtt_ms, loss_rate, drop_packets):
    if loss_rate >= 2 or rtt_ms >= 300 or drop_packets >= 100:
        return "critical"
    if loss_rate >= 0.5 or rtt_ms >= 150 or drop_packets > 0:
        return "degraded"
    return "healthy"


def sanitize_srt_connection(record):
    rtt = _number(record, "msRTT")
    loss_rate = _number(record, "packetsReceivedLossRate")
    drops = _number(record, "packetsReceivedDrop", True)
    started = record.get("created") or record.get("createdAt")
    uptime = None
    if isinstance(started, str):
        try:
            uptime = max(0, int(time.time() - datetime.fromisoformat(started.replace("Z", "+00:00")).timestamp()))
        except (ValueError, TypeError):
            pass
    return {"receive_mbps": _number(record, "mbpsReceiveRate"), "rtt_ms": rtt,
            "packet_loss_count": _number(record, "packetsReceivedLoss", True),
            "packet_loss_rate": loss_rate,
            "retransmitted_packets": _number(record, "packetsReceivedRetrans", True),
            "dropped_packets": drops, "dropped_bytes": _number(record, "bytesReceivedDrop", True),
            "link_capacity_mbps": _number(record, "mbpsLinkCapacity"),
            "packets_received": _number(record, "packetsReceived", True),
            "packets_received_unique": _number(record, "packetsReceivedUnique", True),
            "bytes_received": _number(record, "bytesReceived", True),
            "bytes_lost": _number(record, "bytesReceivedLoss", True), "uptime_seconds": uptime,
            "health": classify_srt_health(rtt, loss_rate, drops)}


def find_srt_publisher(data, stream_id):
    items = data.get("items", []) if isinstance(data, dict) else []
    for record in items if isinstance(items, list) else []:
        if isinstance(record, dict) and record.get("state") == "publish" and record.get("path") == stream_id:
            return sanitize_srt_connection(record)
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


def get_current_srt_port():
    try:
        response = requests.get(f"{MEDIAMTX_API}/v3/config/global/get", timeout=2.0)
        response.raise_for_status()
        address = response.json().get("srtAddress") or ":8890"
        match = re.search(r":(\d+)$", address)
        port = int(match.group(1)) if match else 8890
        return {"ok": True, "port": port, "address": address}
    except (requests.RequestException, ValueError, TypeError, AttributeError) as exc:
        try:
            if os.path.isfile(MEDIAMTX_CONF):
                with open(MEDIAMTX_CONF, "r") as config_file:
                    content = config_file.read()
                match = re.search(r"^\s*srtAddress:\s*[^\n#]*:?(\d+)\s*$", content, re.MULTILINE)
                if match:
                    port = int(match.group(1))
                    return {"ok": True, "port": port, "address": f":{port}"}
        except (OSError, ValueError):
            pass
        return {"ok": False, "port": 8890, "error": str(exc)}


def update_srt_port(new_port):
    if isinstance(new_port, bool):
        raise ValueError("Port must be an integer between 1024 and 65535")
    try:
        port = int(new_port)
    except (TypeError, ValueError):
        raise ValueError("Port must be an integer between 1024 and 65535")
    if str(new_port).strip() != str(port) or not 1024 <= port <= 65535:
        raise ValueError("Port must be an integer between 1024 and 65535")
    response = requests.patch(f"{MEDIAMTX_API}/v3/config/global/patch",
                              json={"srtAddress": f":{port}"}, timeout=3.0)
    response.raise_for_status()
    if os.path.isfile(MEDIAMTX_CONF) and os.access(MEDIAMTX_CONF, os.W_OK):
        with open(MEDIAMTX_CONF, "r") as config_file:
            content = config_file.read()
        updated, count = re.subn(r"^(#?\s*srtAddress:\s*).*$", f"srtAddress: :{port}",
                                 content, flags=re.MULTILINE)
        if count:
            with open(MEDIAMTX_CONF, "w") as config_file:
                config_file.write(updated)
    return {"ok": True, "port": port, "message": f"SRT port updated to {port}"}


atexit.register(stop_preview)


@app.before_request
def protect_api_routes():
    if request.path.startswith("/api/") and not session.get("logged_in"):
        return jsonify({"ok": False, "error": "Unauthorized"}), 401


@app.route("/login", methods=["GET", "POST"])
def login():
    if session.get("logged_in"):
        return redirect(url_for("index"))
    if request.method == "GET":
        return render_template("login.html")
    is_json = request.is_json
    data = request.get_json(silent=True) if is_json else request.form
    data = data or {}
    username = str(data.get("username", ""))
    password = str(data.get("password", ""))
    valid = (hmac.compare_digest(username, DASHBOARD_USER) and
             hmac.compare_digest(password, DASHBOARD_PASS))
    if valid:
        session["logged_in"] = True
        session["username"] = username
        if is_json:
            return jsonify({"ok": True})
        return redirect(url_for("index"))
    error = "Invalid username or password"
    if is_json:
        return jsonify({"ok": False, "error": error}), 401
    return render_template("login.html", error=error), 401


@app.route("/logout", methods=["GET", "POST"])
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
@login_required
def index():
    return render_template("dashboard.html")


@app.route("/api/srt/port", methods=["GET", "POST"])
@login_required
def api_srt_port():
    if request.method == "GET":
        return jsonify(get_current_srt_port())
    data = request.get_json(silent=True) or {}
    try:
        return jsonify(update_srt_port(data.get("port")))
    except ValueError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 400
    except requests.RequestException as exc:
        return jsonify({"ok": False, "error": str(exc)}), 502

@app.route("/api/stats")
def api_stats():
    return jsonify(get_server_stats())

@app.route("/api/audio-tracks", methods=["POST"])
def api_audio_tracks():
    data = request.get_json(silent=True) or {}
    source = data.get("source")
    stream_id = data.get("stream_id")
    try:
        if source is None:
            source = validate_stream_id(stream_id)
        elif not isinstance(source, str):
            raise ValueError("Source is required")
        audio_streams = probe_audio_streams(source)
    except subprocess.TimeoutExpired:
        return jsonify({"ok": False, "error": "Audio probe timed out; verify the stream is active"}), 504
    except (ValueError, RuntimeError) as exc:
        return jsonify({"ok": False, "error": str(exc)}), 400
    except OSError:
        return jsonify({"ok": False, "error": "ffprobe is unavailable"}), 503
    return jsonify({"ok": True, "source": source, "stream_id": stream_id,
                    "audio_streams": audio_streams})


@app.route("/api/preview/start", methods=["POST"])
def api_preview_start():
    data = request.get_json(silent=True) or {}
    try:
        stream_id = validate_stream_id(data.get("stream_id"))
        audio_index = validate_audio_index(data.get("audio_index"))
        token = start_preview(stream_id, audio_index)
    except ValueError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 400
    except RuntimeError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 503
    return jsonify({"ok": True, "stream_id": stream_id, "audio_index": audio_index,
                    "playlist_url": f"/preview/{token}/index.m3u8"})


@app.route("/api/preview/status")
def api_preview_status():
    return jsonify(preview_status_payload())


@app.route("/api/preview/stop", methods=["POST"])
def api_preview_stop():
    stop_preview()
    return jsonify({"ok": True, "running": False})


@app.route("/preview/<token>/<path:filename>")
@login_required
def preview_file(token, filename):
    try:
        directory = preview_directory(token)
    except ValueError:
        return jsonify({"ok": False, "error": "Invalid preview token"}), 404
    if filename != "index.m3u8" and not re.fullmatch(r"segment_[0-9]{5}\.ts", filename):
        return jsonify({"ok": False, "error": "Invalid preview file"}), 404
    with PREVIEW_LOCK:
        if token != preview_state.get("token"):
            return jsonify({"ok": False, "error": "Preview is no longer active"}), 404
    return send_from_directory(directory, filename, conditional=True, max_age=0)


@app.route("/api/srt-health")
def api_srt_health():
    try:
        stream_id = validate_stream_id(request.args.get("stream_id"))
    except ValueError as exc:
        return jsonify({"ok": False, "connected": False, "metrics": None, "error": str(exc)}), 400
    try:
        response = requests.get(f"{MEDIAMTX_API}/v3/srtconns/list", timeout=1.5)
        response.raise_for_status()
        metrics = find_srt_publisher(response.json(), stream_id)
    except (requests.RequestException, ValueError):
        return jsonify({"ok": False, "connected": False, "metrics": None,
                        "error": "MediaMTX SRT metrics are temporarily unavailable"}), 503
    if metrics is None:
        return jsonify({"ok": True, "connected": False, "stream_id": stream_id,
                        "metrics": None, "error": "No SRT publisher for selected stream"})
    return jsonify({"ok": True, "connected": True, "stream_id": stream_id,
                    "metrics": metrics, "error": None})

@app.route("/api/forwards", methods=["GET"])
def api_get_forwards():
    items = load_forwards()
    for item in items:
        rid = item["id"]
        try:
            item["processing_summary"] = processing_summary(item)
        except ValueError:
            item["processing_summary"] = "Invalid processing settings"
        item["destination_label"] = safe_destination_label(item.get("destination", ""))
        if rid in active_relays:
            proc = active_relays[rid].get("proc")
            item["running"] = (proc and proc.poll() is None)
        else:
            item["running"] = False
    return jsonify(items)

@app.route("/api/forwards", methods=["POST"])
def api_add_forward():
    data = request.json or {}
    forwards = load_forwards()
    try:
        audio_index = validate_audio_index(data.get("audio_index", 0))
        settings = processing_settings(data)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    relay_id = f"fwd_{int(time.time())}"
    new_item = {
        "id": relay_id,
        "name": data.get("name", "Target"),
        "source": data.get("source", "live"),
        "destination": data.get("destination", ""),
        "audio_index": audio_index,
        "mode": settings["mode"],
        "enabled": True,
        "created_at": time.time()
    }
    if settings["mode"] != "copy":
        new_item.update({key: settings[key] for key in (
            "video_bitrate", "max_bitrate", "buffer_size", "audio_bitrate", "encoder_preset"
        )})
    forwards.append(new_item)
    save_forwards(forwards)
    start_relay(relay_id)
    return jsonify({"success": True, "item": new_item})

@app.route("/api/forwards/<relay_id>/toggle", methods=["POST"])
def api_toggle_forward(relay_id):
    data = request.json or {}
    enable = data.get("enabled", False)
    forwards = load_forwards()
    for f in forwards:
        if f["id"] == relay_id:
            f["enabled"] = enable
            break
    save_forwards(forwards)
    
    if enable:
        start_relay(relay_id)
    else:
        stop_relay(relay_id)
        
    return jsonify({"success": True})

@app.route("/api/forwards/<relay_id>", methods=["DELETE"])
def api_delete_forward(relay_id):
    stop_relay(relay_id)
    forwards = load_forwards()
    forwards = [f for f in forwards if f["id"] != relay_id]
    save_forwards(forwards)
    return jsonify({"success": True})

@app.route("/api/forwards/<relay_id>/logs")
def api_get_logs(relay_id):
    log_file = os.path.join(LOGS_DIR, f"relay_{relay_id}.log")
    if os.path.exists(log_file):
        try:
            with open(log_file, "r") as f:
                lines = f.readlines()
                return "".join(lines[-100:])
        except Exception as e:
            return f"Error reading log: {str(e)}"
    return "Log file empty."

if __name__ == "__main__":
    bootstrap_relays()
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
