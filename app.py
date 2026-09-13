#!/usr/bin/env python3
"""
Makasna SRT & RTMP Relay Dashboard
Lightweight streaming redirector & relay manager
"""

import os
import secrets
import json
import time
import psutil
import requests
import subprocess
import threading
from datetime import datetime
from urllib.parse import urlsplit
from flask import Flask, render_template_string, request, jsonify

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY") or secrets.token_hex(32)
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
        r = requests.get("http://127.0.0.1:9997/v3/paths/list", timeout=1.0)
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
            f_out.write(f"Source: {safe_destination_label(target.get('source', ''))}\n")
            f_out.write(f"Destination: {safe_destination_label(target.get('destination', ''))}\n\n")
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

# HTML Template
DASHBOARD_HTML = """
<!DOCTYPE html>
<html lang="en" class="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Makasna SRT & RTMP Relay Dashboard</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
    body { font-family: 'Inter', sans-serif; background-color: #0f172a; color: #f8fafc; }
    .glass { background: rgba(30, 41, 59, 0.7); backdrop-filter: blur(8px); border: 1px solid rgba(255, 255, 255, 0.08); }
    .network-chart-wrap { position: relative; height: 78px; margin-top: 10px; }
  </style>
</head>
<body class="min-h-screen p-4 md:p-8">
  <div class="max-w-7xl mx-auto space-y-6">
    
    <!-- Top Header -->
    <header class="flex flex-col md:flex-row md:items-center justify-between gap-4 glass p-6 rounded-2xl">
      <div class="flex items-center gap-3">
        <div class="w-12 h-12 rounded-xl bg-gradient-to-tr from-cyan-500 to-blue-600 flex items-center justify-center text-white text-2xl shadow-lg shadow-cyan-500/30">
          🦞
        </div>
        <div>
          <h1 class="text-2xl font-bold text-white tracking-wide">Makasna SRT Relay</h1>
          <p class="text-sm text-slate-400">High-Performance SRT & RTMP Media Redirector</p>
        </div>
      </div>
      
      <div class="flex items-center gap-3">
        <span class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
          <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          MediaMTX Online (:8890)
        </span>
        <button onclick="openAddModal()" class="px-4 py-2 bg-gradient-to-r from-blue-600 to-cyan-600 hover:from-blue-500 hover:to-cyan-500 text-white font-medium rounded-xl text-sm flex items-center gap-2 shadow-lg shadow-blue-500/25 transition">
          <i class="fa-solid fa-plus"></i> Add Redirect Target
        </button>
      </div>
    </header>

    <!-- Server Status Stats Grid -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <div class="glass p-5 rounded-2xl">
        <div class="flex items-center justify-between text-slate-400 mb-2">
          <span class="text-xs uppercase tracking-wider font-semibold">CPU Usage</span>
          <i class="fa-solid fa-microchip text-cyan-400"></i>
        </div>
        <div class="text-2xl font-bold text-white" id="stat-cpu">-- %</div>
        <div class="w-full bg-slate-700/50 h-1.5 rounded-full mt-3 overflow-hidden">
          <div id="bar-cpu" class="bg-cyan-400 h-full rounded-full transition-all duration-500" style="width: 0%"></div>
        </div>
      </div>

      <div class="glass p-5 rounded-2xl">
        <div class="flex items-center justify-between text-slate-400 mb-2">
          <span class="text-xs uppercase tracking-wider font-semibold">RAM Usage</span>
          <i class="fa-solid fa-memory text-purple-400"></i>
        </div>
        <div class="text-2xl font-bold text-white" id="stat-ram">-- MB</div>
        <div class="w-full bg-slate-700/50 h-1.5 rounded-full mt-3 overflow-hidden">
          <div id="bar-ram" class="bg-purple-400 h-full rounded-full transition-all duration-500" style="width: 0%"></div>
        </div>
      </div>

      <div class="glass p-5 rounded-2xl overflow-hidden">
        <div class="flex items-center justify-between text-slate-400 mb-2">
          <span class="text-xs uppercase tracking-wider font-semibold">Network TX / RX</span>
          <i class="fa-solid fa-network-wired text-blue-400"></i>
        </div>
        <div class="text-sm font-bold flex items-center gap-4" id="stat-net">
          <span class="text-cyan-300">↑ TX <span id="stat-tx" class="text-white">0.0</span> <small class="text-[10px] text-slate-500">Mbps</small></span>
          <span class="text-violet-300">↓ RX <span id="stat-rx" class="text-white">0.0</span> <small class="text-[10px] text-slate-500">Mbps</small></span>
        </div>
        <div class="network-chart-wrap">
          <canvas id="network-chart" aria-label="Real-time network TX and RX throughput"></canvas>
        </div>
      </div>

      <div class="glass p-5 rounded-2xl">
        <div class="flex items-center justify-between text-slate-400 mb-2">
          <span class="text-xs uppercase tracking-wider font-semibold">Active Streams</span>
          <i class="fa-solid fa-video text-emerald-400"></i>
        </div>
        <div class="text-2xl font-bold text-emerald-400" id="stat-active-count">0</div>
        <div class="text-xs text-slate-400 mt-2" id="stat-active-names">No incoming stream</div>
      </div>
    </div>

    <!-- Ingest Quick URLs Info Card -->
    <div class="glass p-6 rounded-2xl">
      <h2 class="text-lg font-semibold text-white mb-3 flex items-center gap-2">
        <i class="fa-solid fa-tower-broadcast text-cyan-400"></i> Server Ingest Endpoints
      </h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
        <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-800 flex items-center justify-between">
          <div>
            <span class="text-xs font-semibold text-cyan-400 block mb-1">SRT Ingest URL (OBS / Camera / Encoder)</span>
            <code class="text-slate-300 select-all font-mono text-xs">srt://SERVER_IP:8890?streamid=publish:STREAM_NAME</code>
          </div>
          <button onclick="copyText('srt://SERVER_IP:8890?streamid=publish:live')" class="p-2 text-slate-400 hover:text-white bg-slate-800 rounded-lg transition" title="Copy">
            <i class="fa-regular fa-copy"></i>
          </button>
        </div>

        <div class="bg-slate-900/60 p-4 rounded-xl border border-slate-800 flex items-center justify-between">
          <div>
            <span class="text-xs font-semibold text-amber-400 block mb-1">SRT Play / Receiver URL (OBS / VLC / vMix)</span>
            <code class="text-slate-300 select-all font-mono text-xs">srt://SERVER_IP:8890?streamid=read:STREAM_NAME</code>
          </div>
          <button onclick="copyText('srt://SERVER_IP:8890?streamid=read:live')" class="p-2 text-slate-400 hover:text-white bg-slate-800 rounded-lg transition" title="Copy">
            <i class="fa-regular fa-copy"></i>
          </button>
        </div>
      </div>
    </div>

    <!-- Active Forwarding / Redirect Targets Table -->
    <div class="glass p-6 rounded-2xl space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-white">Stream Forwarders & Redirectors</h2>
          <p class="text-sm text-slate-400">Forward local streams to YouTube, Facebook, Twitch, or Remote SRT/RTMP Servers</p>
        </div>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full text-left text-sm text-slate-300">
          <thead class="text-xs uppercase text-slate-400 bg-slate-800/50 border-b border-slate-700/50">
            <tr>
              <th class="py-3 px-4 rounded-l-xl">Target / Label</th>
              <th class="py-3 px-4">Source Stream</th>
              <th class="py-3 px-4">Destination</th>
              <th class="py-3 px-4">Audio</th>
              <th class="py-3 px-4">Mode</th>
              <th class="py-3 px-4">Status</th>
              <th class="py-3 px-4 text-right rounded-r-xl">Actions</th>
            </tr>
          </thead>
          <tbody id="forwards-table-body" class="divide-y divide-slate-800">
            <tr>
               <td colspan="7" class="py-8 text-center text-slate-500">Loading forwarders...</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

  </div>

  <!-- Add Target Modal -->
  <div id="add-modal" class="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center hidden p-4">
    <div class="glass w-full max-w-lg p-6 rounded-2xl space-y-5 border border-slate-700">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-bold text-white flex items-center gap-2">
          <i class="fa-solid fa-satellite-dish text-cyan-400"></i> New Forward Target
        </h3>
        <button onclick="closeAddModal()" class="text-slate-400 hover:text-white text-lg">&times;</button>
      </div>

      <form id="add-form" onsubmit="handleAddForward(event)" class="space-y-4">
        <div>
          <label class="block text-xs font-semibold text-slate-300 mb-1">Target Label / Name</label>
          <input type="text" name="name" required placeholder="e.g. YouTube Live, Backup SRT" class="w-full bg-slate-900/80 border border-slate-700 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-cyan-500 text-sm">
        </div>

        <div>
          <label class="block text-xs font-semibold text-slate-300 mb-1">Source Stream Name / URL</label>
          <input type="text" name="source" required placeholder="e.g. live or cam1" value="live" class="w-full bg-slate-900/80 border border-slate-700 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-cyan-500 text-sm">
          <span class="text-xs text-slate-500">Ketik nama stream lokal (contoh: <code>live</code>) atau URL lengkap.</span>
        </div>

        <div>
          <div class="flex items-center justify-between mb-1">
            <label class="block text-xs font-semibold text-slate-300">Audio Track</label>
            <button type="button" id="detect-audio-button" onclick="detectAudioTracks()" class="px-3 py-1 rounded-lg text-xs text-cyan-300 bg-cyan-500/10 hover:bg-cyan-500/20">Detect Audio Tracks</button>
          </div>
          <select id="audio-index" name="audio_index" class="w-full bg-slate-900/80 border border-slate-700 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-cyan-500 text-sm">
            <option value="0">Audio 1 (default)</option>
          </select>
          <span id="audio-detect-status" class="text-xs text-slate-500">Defaults to the first audio track.</span>
        </div>

        <div>
          <label class="block text-xs font-semibold text-slate-300 mb-1">Preset / Destination Type</label>
          <select id="dest-preset" onchange="applyPreset(this.value)" class="w-full bg-slate-900/80 border border-slate-700 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-cyan-500 text-sm mb-2">
            <option value="custom">Custom URL</option>
            <option value="youtube">YouTube Live (RTMP)</option>
            <option value="facebook">Facebook Live (RTMP)</option>
            <option value="twitch">Twitch (RTMP)</option>
            <option value="srt_caller">Remote SRT Destination</option>
          </select>
        </div>

        <div>
          <label class="block text-xs font-semibold text-slate-300 mb-1">Destination URL / Stream Target</label>
          <input type="text" id="dest-url" name="destination" required placeholder="rtmp://a.rtmp.youtube.com/live2/YOUR_STREAM_KEY" class="w-full bg-slate-900/80 border border-slate-700 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-cyan-500 text-sm font-mono">
        </div>

        <div>
          <label class="block text-xs font-semibold text-slate-300 mb-1">Video & Audio Processing</label>
          <select name="mode" onchange="updateProcessingFields()" class="w-full bg-slate-900/80 border border-slate-700 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-cyan-500 text-sm">
            <option value="copy" selected>Direct Copy — original bitrate, no re-encode</option>
            <option value="custom">Custom Bitrate — re-encode video/audio</option>
          </select>
          <span class="text-xs text-slate-500">Bitrate cannot change in Direct Copy mode.</span>
        </div>

        <div id="custom-processing-fields" class="hidden grid grid-cols-2 gap-3">
          <label class="text-xs text-slate-300">Video bitrate (kbps)<input type="number" name="video_bitrate" min="250" max="50000" value="4500" class="mt-1 w-full bg-slate-900/80 border border-slate-700 rounded-xl px-3 py-2 text-white"></label>
          <label class="text-xs text-slate-300">Max bitrate (kbps)<input type="number" name="max_bitrate" min="250" max="50000" value="5000" class="mt-1 w-full bg-slate-900/80 border border-slate-700 rounded-xl px-3 py-2 text-white"></label>
          <label class="text-xs text-slate-300">Buffer size (kbps)<input type="number" name="buffer_size" min="500" max="100000" value="9000" class="mt-1 w-full bg-slate-900/80 border border-slate-700 rounded-xl px-3 py-2 text-white"></label>
          <label class="text-xs text-slate-300">Audio bitrate (kbps)<input type="number" name="audio_bitrate" min="32" max="512" value="160" class="mt-1 w-full bg-slate-900/80 border border-slate-700 rounded-xl px-3 py-2 text-white"></label>
          <label class="col-span-2 text-xs text-slate-300">Encoder preset<select name="encoder_preset" class="mt-1 w-full bg-slate-900/80 border border-slate-700 rounded-xl px-3 py-2 text-white"><option>ultrafast</option><option>superfast</option><option selected>veryfast</option><option>faster</option><option>fast</option><option>medium</option><option>slow</option></select></label>
        </div>

        <div class="flex items-center justify-end gap-3 pt-4 border-t border-slate-800">
          <button type="button" onclick="closeAddModal()" class="px-4 py-2 rounded-xl text-sm text-slate-400 hover:text-white bg-slate-800">Cancel</button>
          <button type="submit" class="px-5 py-2 rounded-xl text-sm text-white font-medium bg-cyan-600 hover:bg-cyan-500 transition shadow-lg shadow-cyan-500/20">Save & Start</button>
        </div>
      </form>
    </div>
  </div>

  <!-- Log Viewer Modal -->
  <div id="log-modal" class="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center hidden p-4">
    <div class="glass w-full max-w-3xl p-6 rounded-2xl space-y-4 border border-slate-700 max-h-[85vh] flex flex-col">
      <div class="flex items-center justify-between">
        <h3 class="text-base font-bold text-white flex items-center gap-2">
          <i class="fa-solid fa-terminal text-cyan-400"></i> Relay Logs: <span id="log-title" class="text-slate-300"></span>
        </h3>
        <button onclick="closeLogModal()" class="text-slate-400 hover:text-white text-lg">&times;</button>
      </div>
      <div class="flex-1 bg-black/80 rounded-xl p-4 overflow-y-auto border border-slate-800 font-mono text-xs text-slate-300 whitespace-pre-wrap" id="log-content">
        Loading logs...
      </div>
      <div class="flex justify-between items-center pt-2">
        <span class="text-xs text-slate-500">Auto-refreshes every 2s</span>
        <button onclick="closeLogModal()" class="px-4 py-1.5 rounded-lg text-xs text-white bg-slate-800 hover:bg-slate-700">Close</button>
      </div>
    </div>
  </div>

  <script>
    let currentLogId = null;
    let logInterval = null;
    let networkChart = null;
    let statsRequestInFlight = false;
    const NETWORK_HISTORY_SIZE = 25;

    function initNetworkChart() {
      const canvas = document.getElementById('network-chart');
      if (!canvas || typeof Chart === 'undefined') return;
      const ctx = canvas.getContext('2d');
      const txFill = ctx.createLinearGradient(0, 0, 0, 78);
      txFill.addColorStop(0, 'rgba(34, 211, 238, 0.30)');
      txFill.addColorStop(1, 'rgba(34, 211, 238, 0.01)');
      const rxFill = ctx.createLinearGradient(0, 0, 0, 78);
      rxFill.addColorStop(0, 'rgba(139, 92, 246, 0.27)');
      rxFill.addColorStop(1, 'rgba(59, 130, 246, 0.01)');

      networkChart = new Chart(ctx, {
        type: 'line',
        data: {
          labels: [],
          datasets: [
            { label: 'TX', data: [], borderColor: '#22d3ee', backgroundColor: txFill, fill: true, borderWidth: 2, pointRadius: 0, tension: 0.42 },
            { label: 'RX', data: [], borderColor: '#8b5cf6', backgroundColor: rxFill, fill: true, borderWidth: 2, pointRadius: 0, tension: 0.42 }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          animation: { duration: 350, easing: 'easeOutQuart' },
          interaction: { intersect: false, mode: 'index' },
          plugins: { legend: { display: false }, tooltip: { displayColors: true, backgroundColor: 'rgba(15, 23, 42, .92)' } },
          scales: {
            x: { display: false },
            y: {
              beginAtZero: true,
              border: { display: false },
              ticks: { color: 'rgba(148, 163, 184, .65)', maxTicksLimit: 3, font: { size: 9 } },
              grid: { color: 'rgba(148, 163, 184, .08)', drawTicks: false }
            }
          }
        }
      });
    }

    function updateNetworkChart(tx, rx) {
      if (!networkChart) return;
      networkChart.data.labels.push(new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }));
      networkChart.data.datasets[0].data.push(Number(tx) || 0);
      networkChart.data.datasets[1].data.push(Number(rx) || 0);
      if (networkChart.data.labels.length > NETWORK_HISTORY_SIZE) {
        networkChart.data.labels.shift();
        networkChart.data.datasets.forEach(dataset => dataset.data.shift());
      }
      networkChart.update();
    }

    function copyText(text) {
      navigator.clipboard.writeText(text);
      alert('Copied to clipboard: ' + text);
    }

    function openAddModal() {
      document.getElementById('add-modal').classList.remove('hidden');
    }

    function closeAddModal() {
      document.getElementById('add-modal').classList.add('hidden');
    }

    function updateProcessingFields() {
      const form = document.getElementById('add-form');
      const fields = document.getElementById('custom-processing-fields');
      const custom = form.mode.value === 'custom';
      fields.classList.toggle('hidden', !custom);
      fields.querySelectorAll('input, select').forEach(field => field.disabled = !custom);
    }

    function applyPreset(preset) {
      const destInput = document.getElementById('dest-url');
      if (preset === 'youtube') {
        destInput.value = 'rtmp://a.rtmp.youtube.com/live2/STREAM_KEY';
      } else if (preset === 'facebook') {
        destInput.value = 'rtmps://live-api-s.facebook.com:443/rtmp/STREAM_KEY';
      } else if (preset === 'twitch') {
        destInput.value = 'rtmp://live.twitch.tv/app/STREAM_KEY';
      } else if (preset === 'srt_caller') {
        destInput.value = 'srt://REMOTE_IP:8890?streamid=publish:STREAM_NAME';
      } else {
        destInput.value = '';
      }
    }

    function formatAudioTrack(track) {
      const details = [track.codec, track.channel_layout || (track.channels ? track.channels + ' channels' : null), track.sample_rate ? track.sample_rate + ' Hz' : null, track.language, track.title].filter(Boolean);
      return `Audio ${track.selector + 1}${details.length ? ' — ' + details.join(', ') : ''}`;
    }

    async function detectAudioTracks() {
      const form = document.getElementById('add-form');
      const select = document.getElementById('audio-index');
      const status = document.getElementById('audio-detect-status');
      const button = document.getElementById('detect-audio-button');
      const source = form.source.value.trim();
      if (!source) {
        status.textContent = 'Enter a source before detecting audio tracks.';
        return;
      }
      button.disabled = true;
      status.textContent = 'Detecting audio tracks...';
      try {
        const res = await fetch('/api/audio-tracks', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ source })
        });
        let data;
        try { data = await res.json(); } catch (err) { throw new Error('Malformed response from server.'); }
        if (!res.ok) throw new Error(data.error || 'Unable to probe source.');
        if (!data || !Array.isArray(data.audio_streams)) throw new Error('Malformed response from server.');
        if (data.audio_streams.length === 0) {
          select.innerHTML = '<option value="0">Audio 1 (default; no track detected)</option>';
          status.textContent = 'No audio tracks found on the active source.';
          return;
        }
        select.innerHTML = '';
        data.audio_streams.forEach(track => {
          if (!Number.isInteger(track.selector) || track.selector < 0) return;
          const option = document.createElement('option');
          option.value = track.selector;
          option.textContent = formatAudioTrack(track);
          select.appendChild(option);
        });
        if (!select.options.length) throw new Error('Malformed response from server.');
        status.textContent = `${select.options.length} audio track(s) detected.`;
      } catch (err) {
        status.textContent = err.message || 'Unable to detect audio tracks.';
      } finally {
        button.disabled = false;
      }
    }

    async function fetchStats() {
      if (statsRequestInFlight) return;
      statsRequestInFlight = true;
      try {
        const res = await fetch('/api/stats', { cache: 'no-store' });
        if (!res.ok) throw new Error(`Stats request failed: ${res.status}`);
        const data = await res.json();
        
        const cpuVal = (data && data.cpu !== null && data.cpu !== undefined) ? data.cpu : 0;
        const ramUsed = (data && data.ram_used_mb !== null && data.ram_used_mb !== undefined) ? data.ram_used_mb : 0;
        const ramTotal = (data && data.ram_total_mb !== null && data.ram_total_mb !== undefined) ? data.ram_total_mb : 0;
        const ramPct = (data && data.ram_percent !== null && data.ram_percent !== undefined) ? data.ram_percent : 0;
        const txVal = (data && data.tx_mbps !== null && data.tx_mbps !== undefined) ? data.tx_mbps : 0;
        const rxVal = (data && data.rx_mbps !== null && data.rx_mbps !== undefined) ? data.rx_mbps : 0;

        const elCpu = document.getElementById('stat-cpu');
        const elBarCpu = document.getElementById('bar-cpu');
        if (elCpu) elCpu.textContent = cpuVal + ' %';
        if (elBarCpu) elBarCpu.style.width = Math.min(Math.max(cpuVal, 0), 100) + '%';
        
        const elRam = document.getElementById('stat-ram');
        const elBarRam = document.getElementById('bar-ram');
        if (elRam) elRam.textContent = ramUsed + ' / ' + ramTotal + ' MB';
        if (elBarRam) elBarRam.style.width = Math.min(Math.max(ramPct, 0), 100) + '%';
        
        const elTx = document.getElementById('stat-tx');
        const elRx = document.getElementById('stat-rx');
        if (elTx) elTx.textContent = txVal;
        if (elRx) elRx.textContent = rxVal;
        updateNetworkChart(txVal, rxVal);
        
        const streams = (data && Array.isArray(data.active_streams)) ? data.active_streams : [];
        const count = streams.length;
        const elCount = document.getElementById('stat-active-count');
        const elNames = document.getElementById('stat-active-names');
        if (elCount) elCount.textContent = count;
        if (elNames) {
          if (count > 0) {
            elNames.textContent = streams.map(s => s.name).join(', ');
          } else {
            elNames.textContent = 'No incoming stream';
          }
        }
      } catch (err) {
        console.warn('Unable to refresh server stats:', err);
      } finally {
        statsRequestInFlight = false;
      }
    }

    async function fetchForwards() {
      try {
        const res = await fetch('/api/forwards');
        const list = await res.json();
        const tbody = document.getElementById('forwards-table-body');
        
        if (list.length === 0) {
          tbody.innerHTML = '<tr><td colspan="7" class="py-8 text-center text-slate-500">No redirect rules yet. Click "Add Redirect Target" to create one.</td></tr>';
          return;
        }
        
        let html = '';
        list.forEach(item => {
          const isRunning = item.enabled && item.running;
          const statusBadge = isRunning 
            ? '<span class="px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 inline-flex items-center gap-1.5"><span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span> Streaming</span>'
            : '<span class="px-2.5 py-1 rounded-full text-xs font-semibold bg-slate-700/40 text-slate-400 border border-slate-700 inline-flex items-center gap-1.5">Stopped</span>';
          
          html += `
            <tr class="hover:bg-slate-800/40 transition">
              <td class="py-3.5 px-4 font-semibold text-white">${item.name}</td>
              <td class="py-3.5 px-4"><span class="px-2 py-0.5 bg-cyan-950/60 border border-cyan-800/50 text-cyan-300 rounded font-mono text-xs">${item.source}</span></td>
              <td class="py-3.5 px-4 max-w-xs truncate font-mono text-xs text-slate-400">${item.destination_label}</td>
              <td class="py-3.5 px-4 text-xs text-slate-400">Audio ${(Number.isInteger(item.audio_index) ? item.audio_index : 0) + 1}</td>
              <td class="py-3.5 px-4 text-xs text-slate-400">${item.processing_summary}</td>
              <td class="py-3.5 px-4">${statusBadge}</td>
              <td class="py-3.5 px-4 text-right space-x-2">
                <button onclick="toggleRelay('${item.id}', ${!item.enabled})" class="p-1.5 px-3 rounded-lg text-xs font-medium ${item.enabled ? 'bg-amber-500/10 text-amber-400 hover:bg-amber-500/20' : 'bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20'} transition">
                  <i class="fa-solid ${item.enabled ? 'fa-stop' : 'fa-play'} mr-1"></i> ${item.enabled ? 'Stop' : 'Start'}
                </button>
                <button onclick="openLogModal('${item.id}', '${item.name}')" class="p-1.5 px-2.5 rounded-lg text-xs text-slate-400 hover:text-white bg-slate-800 transition" title="View Logs">
                  <i class="fa-solid fa-file-lines"></i>
                </button>
                <button onclick="deleteForward('${item.id}')" class="p-1.5 px-2.5 rounded-lg text-xs text-rose-400 hover:text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 transition" title="Delete">
                  <i class="fa-solid fa-trash-can"></i>
                </button>
              </td>
            </tr>
          `;
        });
        tbody.innerHTML = html;
      } catch (err) {}
    }

    async function handleAddForward(e) {
      e.preventDefault();
      const form = e.target;
      const data = {
        name: form.name.value,
        source: form.source.value,
        destination: form.destination.value,
        audio_index: form.audio_index.value,
        mode: form.mode.value,
        video_bitrate: form.video_bitrate.value,
        max_bitrate: form.max_bitrate.value,
        buffer_size: form.buffer_size.value,
        audio_bitrate: form.audio_bitrate.value,
        encoder_preset: form.encoder_preset.value
      };
      
      const res = await fetch('/api/forwards', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      
      if (res.ok) {
        closeAddModal();
        form.reset();
        updateProcessingFields();
        fetchForwards();
      }
    }

    async function toggleRelay(id, enable) {
      await fetch(`/api/forwards/${id}/toggle`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ enabled: enable })
      });
      fetchForwards();
    }

    async function deleteForward(id) {
      if (!confirm('Are you sure you want to delete this target?')) return;
      await fetch(`/api/forwards/${id}`, { method: 'DELETE' });
      fetchForwards();
    }

    function openLogModal(id, name) {
      currentLogId = id;
      document.getElementById('log-title').textContent = name;
      document.getElementById('log-modal').classList.remove('hidden');
      loadLogs();
      if (logInterval) clearInterval(logInterval);
      logInterval = setInterval(loadLogs, 2000);
    }

    function closeLogModal() {
      currentLogId = null;
      if (logInterval) clearInterval(logInterval);
      document.getElementById('log-modal').classList.add('hidden');
    }

    async function loadLogs() {
      if (!currentLogId) return;
      try {
        const res = await fetch(`/api/forwards/${currentLogId}/logs`);
        const text = await res.text();
        const box = document.getElementById('log-content');
        box.textContent = text || 'No logs generated yet.';
        box.scrollTop = box.scrollHeight;
      } catch (err) {}
    }

    // Polling init
    initNetworkChart();
    updateProcessingFields();
    fetchStats();
    fetchForwards();
    setInterval(fetchStats, 2000);
    setInterval(fetchForwards, 4000);
  </script>
</body>
</html>
"""

# API Routes
@app.route("/")
def index():
    return render_template_string(DASHBOARD_HTML)

@app.route("/api/stats")
def api_stats():
    return jsonify(get_server_stats())

@app.route("/api/audio-tracks", methods=["POST"])
def api_audio_tracks():
    data = request.json or {}
    source = data.get("source")
    if not isinstance(source, str):
        return jsonify({"error": "Source is required"}), 400
    try:
        audio_streams = probe_audio_streams(source)
    except subprocess.TimeoutExpired:
        return jsonify({"error": "Audio probe timed out; verify the stream is active"}), 504
    except (ValueError, RuntimeError) as exc:
        return jsonify({"error": str(exc)}), 400
    except OSError:
        return jsonify({"error": "ffprobe is unavailable"}), 503
    return jsonify({"audio_streams": audio_streams})

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
