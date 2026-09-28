<p align="center">
  <img src="static/logo-banner.svg" alt="MAKASNA Live Video Transport Gateway" width="100%" />
</p>

<p align="center">
  <b>Enterprise SRT Live Video Transport Gateway, Failover Switching, Master Deck ISO Recorder &amp; Multi-Destination Playout Engine</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/SRT-Reliable%20Transport-00E5FF?style=flat-square" alt="SRT" />
  <img src="https://img.shields.io/badge/MediaMTX-v1.11+-3B82F6?style=flat-square" alt="MediaMTX" />
  <img src="https://img.shields.io/badge/FFmpeg-Transcode%20%26%20ISO%20Rec-F59E0B?style=flat-square" alt="FFmpeg" />
  <img src="https://img.shields.io/badge/Master%20Deck-Broadcast%20Console-EF4444?style=flat-square" alt="Master Deck" />
  <img src="https://img.shields.io/badge/Google%20Drive-Chunked%20Upload-10B981?style=flat-square" alt="Google Drive" />
  <img src="https://img.shields.io/badge/Flutter-Mobile%20Remote-02569B?style=flat-square" alt="Flutter" />
</p>

---

## Technical Overview & Architecture

**Makasna Live Video Transport Gateway** is an enterprise broadcast gateway built on Python/Flask, MediaMTX, and FFmpeg. The platform is designed for mission-critical video contribution, hot-standby failover switching, real-time audio/video transcoding, sub-second latency monitoring, multi-destination fan-out distribution, and automated ISO recording with Google Drive cloud archiving.

```
                  ┌────────────────────────────────────────────────────────┐
                  │              INBOUND CONTRIBUTION                      │
                  │   OBS / vMix / Hardware Encoders / Remote SRT / RTMP   │
                  └──────────────────────────┬─────────────────────────────┘
                                             │
                                             ▼
                  ┌────────────────────────────────────────────────────────┐
                  │                 MEDIAMTX CORE ENGINE                   │
                  │    • SRT Ingest (UDP 8890)    • RTMP Ingest (TCP 1935) │
                  │    • RTSP Server (TCP 8554)   • HLS/fMP4 (Port 8888)   │
                  │    • WebRTC (<300ms)          • REST API (Port 9997)   │
                  └──────────────┬───────────────────────────┬─────────────┘
                                 │                           │
                   Inbound Poll  │             FFmpeg Bridge │ (Dynamic Routes)
                                 ▼                           ▼
        ┌──────────────────────────────────┐   ┌───────────────────────────────┐
        │   INBOUND INGEST MONITOR         │   │   SUPERVISED ROUTE PIPELINE   │
        │   • Real-time Stream ID Detector │   │   • Primary / Secondary Source│
        │   • Bitrate, RTT, Loss, Drops    │   │   • Hot-Standby Failover      │
        │   • Instant Preview & + Route    │   │   • Circuit Breaker (Backoff) │
        └──────────────────────────────────┘   └───────────────┬───────────────┘
                                                               │
                       ┌───────────────────────────────────────┴───────────────────────────────────────┐
                       │                                       │                                       │
                       ▼                                       ▼                                       ▼
        ┌──────────────────────────────┐        ┌──────────────────────────────┐        ┌──────────────────────────────┐
        │   MULTI-DESTINATION FAN-OUT  │        │   SEGMENTED ISO RECORDING    │        │   OPERATOR PREVIEW & AUDIT   │
        │   • SRT Caller / Listener    │        │   • 15m / 30m / 1h Segments  │        │   • fMP4 HLS Buffer (12s)    │
        │   • RTMP / RTMPS / CDN       │        │   • Clean SIGINT Atom Closure│        │   • WebRTC Sub-Second (<0.3s)│
        │   • UDP MPEG-TS / RTSP       │        │   • Google Service Account   │        │   • Same-Origin Proxy        │
        │   • Auto MP2->AAC Transcode  │        │   • Chunked 16MB Background  │        │   • Audio Digital Clip Alert │
        └──────────────────────────────┘        └──────────────────────────────┘        └──────────────────────────────┘
```

---

## Core Capabilities

### 1. Ingestion & Hot-Standby Failover
* **Dual-Source Redundancy:** Every broadcast route supports independent Primary Contribution and Secondary Failover inputs.
* **Failover Policies:** `Maintain Primary`, `Invert (Stick to Secondary)`, or `Manual Switch`.
* **Protocols Supported:**
  * **SRT Listener:** Dedicated UDP port binding for remote contributions.
  * **SRT Caller:** Actively pulls live video streams from remote edge encoders or transmitters.
  * **SRT Rendezvous:** Bidirectional peer-to-peer NAT traversal.
  * **Local Inbound Stream:** Captures incoming feeds on MediaMTX (e.g. `publish:STREAM_ID`).
  * **Direct Stream URLs:** RTSP, RTMP, HTTP-TS, and UDP TS.
* **Security & Latency Tuning:** SRT AES-128/256 passphrase encryption and custom latency buffer (200 ms to 8000 ms).
* **Live Probing (`ffprobe`):** On-demand inspection of codecs, video resolution, color space, and audio channels before route startup.

### 2. Multi-Destination Fan-Out Distribution
* Egress single inbound feeds to multiple simultaneous targets:
  * **SRT Caller / Listener** (Studio playout clients, remote receivers).
  * **RTMP / RTMPS** (YouTube Live, Facebook Live, Twitch, custom CDN endpoints).
  * **UDP MPEG-TS Unicast / Multicast** (Studio hardware IRDs and decoders).
  * **RTSP / HTTP-TS**.
* **Zero-Copy Passthrough:** Native `-c copy` default ensures 0% CPU overhead and zero bitstream loss.
* **Automated Audio Remuxing:** Automatically transcodes legacy broadcast MPEG-1 Layer II (MP2) or AC3 audio to AAC (`128k/160k`) on FLV/RTMP destinations to prevent muxer crashes without re-encoding video streams.

### 3. Master Deck ISO Recorder Console
* **Broadcast Rack-Mount Style Console:**
  * **16:9 Confidence Monitor:** Real-time low-latency fMP4 HLS preview with automatic SMPTE color bars during standby.
  * **Broadcast OSD & Timecode:** Mode indicator (`● REC` / `● STBY`), stream metrics, input label, and monospace running timecode (`00:00:00:00`).
  * **True Peak Audio VU Meters:** Real-time dual/quad audio meters with dBFS and dBVU scales, peak-hold needles, and red Digital Clipping indicators.
  * **Dual Media Bays:** 
    * **Slot 1 (Local Storage):** Free space calculation, real-time disk usage bar, and estimated recording hours remaining.
    * **Slot 2 (Cloud Archive):** Google Drive connection status and automated chunked background upload worker.
  * **Tactile Controls [ ● RECORD ] & [ ■ STOP ]:** Clean SIGINT process finalization ensuring MP4/MOV moov atom integrity without file corruption.
* **Flexible Compression & Container Options:**
  * Container formats: **Universal MP4** (`-segment_format mp4`) and **QuickTime MOV** (`-segment_format mov`).
  * Bitrate controls: **Passthrough (Bitstream Copy)**, **2.5 Mbps**, **4.5 Mbps**, **6.0 Mbps**, **8.0 Mbps**, **12.0 Mbps**, or **Custom Bitrate**.
  * Resolution control: Original source passthrough, 1080p Full HD, or 720p HD.

### 4. Remote Android Controller Application
* **Standalone Mobile App Repository:** [justrangga/makasna-remote-controller](https://github.com/justrangga/makasna-remote-controller)
* **Direct APK Download:** Available at `/download/apk` or from the dedicated mobile app repository release.
* **Key Capabilities:**
  * Dynamic IP & Port onboarding with persistent session caching (Auto-Connect).
  * Real-time Ingest Signal Monitor with 1-click URL copying and route generation.
  * Complete Route Management CRUD (Create, Edit, Delete, Start/Stop).
  * Remote Master ISO Recording controls with live timecode sync and format selection.
  * Multi-channel Audio VU Meter with dBVU (-20 to +3 VU) and dBFS (-60 to 0 dBFS) scales.
  * Built-in Broadcast Technical Guide for OBS Studio, vMix, and field encoders.

---

## Network Port Allocation

| Port | Protocol | Service | Description |
|:---:|:---:|:---|:---|
| **8080** | TCP | Flask Web Dashboard & Reverse Proxy | Web UI, REST API, HLS stream proxy |
| **8890** | UDP | MediaMTX SRT Server | Inbound contribution and reader pull |
| **1935** | TCP | MediaMTX RTMP Server | Inbound RTMP contributions |
| **8554** | TCP | MediaMTX RTSP Server | Inbound and outbound RTSP feeds |
| **8888** | TCP | MediaMTX HLS Native Engine | Low-latency fMP4 HLS player engine |
| **8889** | TCP | MediaMTX WebRTC Server | Sub-second browser monitoring |
| **9997** | TCP | MediaMTX Control API | Internal telemetry and active session listing |
| **12100–12150**| UDP | Dynamic Route Listeners | Primary and Secondary Failover SRT ports |

---

## Server Installation & Setup

### Prerequisites
* Ubuntu 22.04 LTS or newer
* Python 3.10+ with `venv`
* FFmpeg 6.0+ (`ffmpeg`, `ffprobe`)
* MediaMTX v1.11+

### Installation Steps

```bash
# Clone the repository
git clone https://github.com/justrangga/makasna-srt-dashboard.git
cd makasna-srt-dashboard

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Start MediaMTX service
sudo systemctl start mediamtx

# Run Makasna Dashboard Gateway
python app.py
```

---

## REST API Reference

| Endpoint | Method | Description |
|:---|:---:|:---|
| `/api/status` | `GET` | System telemetry, CPU, memory, disk, and gateway status |
| `/api/routes` | `GET`, `POST` | List all routes or create a new broadcast route |
| `/api/routes/<id>` | `PUT`, `DELETE` | Update route configuration or delete an existing route |
| `/api/routes/<id>/start` | `POST` | Start route ingestion and fan-out pipelines |
| `/api/routes/<id>/stop` | `POST` | Stop active route execution cleanly |
| `/api/srt/inbound` | `GET` | List active inbound SRT publishers and connected readers |
| `/api/recordings` | `GET` | List recorded ISO files and cloud upload statuses |
| `/api/recorder/active` | `GET` | Get live status of Master ISO Recorder engine |
| `/api/recorder/start` | `POST` | Start ISO recording with feed, format, bitrate, and duration |
| `/api/recorder/stop` | `POST` | Stop active ISO recording with graceful file closure |
| `/api/gdrive/status` | `GET` | Check Google Drive authentication and upload queue |
| `/download/apk` | `GET` | Download latest Makasna Remote Android APK |

---

## Operational Guide

For comprehensive broadcast operations in Indonesian, please consult **[PANDUAN.md](PANDUAN.md)**.

## License

Proprietary — Developed by **Makasna Broadcast Infrastructure**. All rights reserved.
