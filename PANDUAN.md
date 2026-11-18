# Makasna Live Video Transport Gateway — Operations Guide

This guide covers day-to-day broadcast operations: field contribution, studio playout, failover, master recording, cloud archiving, and remote control.

> **New server?** Follow [INSTALL.md](INSTALL.md) first. This guide assumes the gateway is already installed and reachable.

---

## Table of Contents

1. [Signal Flow Overview](#1-signal-flow-overview)
2. [Field Contribution (Ingest Encoders)](#2-field-contribution-ingest-encoders)
3. [Studio Playout (Downstream / Receivers)](#3-studio-playout-downstream--receivers)
4. [Route Management & Failover](#4-route-management--failover)
5. [Master Deck ISO Recorder & Cloud Archive](#5-master-deck-iso-recorder--cloud-archive)
6. [Audio Monitoring & Clipping](#6-audio-monitoring--clipping)
7. [Remote Android App](#7-remote-android-app)
8. [Ports & Troubleshooting](#8-ports--troubleshooting)

---

## 1. Signal Flow Overview

The gateway is the transport layer for mission-critical live video.

1. **Ingest:** field encoders push SRT caller streams to server port `8890` using `publish:STREAM_NAME` as the Stream ID.
2. **Core:** MediaMTX receives the feed and exposes real-time telemetry (bitrate, loss, RTT) to the dashboard, which supervises route processes.
3. **Egress:** the feed fans out to studio switchers (SRT caller/listener), SLS TV Pool decoders, RTMP platforms, and recorders simultaneously.
4. **Master recording:** the ISO recorder runs independently, writing MP4/MOV segments with clean SIGINT finalization.

---

## 2. Field Contribution (Ingest Encoders)

### A. OBS Studio
1. Open **Settings** > **Stream**.
2. Set **Service** to `Custom...`.
3. In the **Server** field enter:
   ```
   srt://SERVER_IP:8890?streamid=publish:STREAM_NAME&latency=2000000
   ```
   Replace `SERVER_IP` with the gateway's public IP and `STREAM_NAME` with a camera identifier (for example `CAM1` or `PROGRAM`).
4. Leave **Stream Key** empty.
5. Click **Apply**, then **Start Streaming**.

### B. vMix
1. Click the gear icon next to **External / Stream**.
2. Set **Destination** to `SRT`.
3. Configure:
   * **Type:** `Caller`
   * **Hostname:** `SERVER_IP`
   * **Port:** `8890`
   * **Latency:** `2000` ms (increase on cellular links)
   * **Stream ID:** `publish:STREAM_NAME` (do not prefix with `streamid=`)
4. Click **Start**.

### C. Encoder Standards
For stable SRT transport over public/cellular networks:
* **Video codec:** H.264 or H.265 (HEVC 8-bit Main Profile).
* **Keyframe GOP:** 1 or 2 seconds (strict closed GOP; never Auto).
* **B-frames:** 0 (zero latency mode).
* **Rate control:** CBR.
* **Audio codec:** AAC stereo, 48 kHz, 128–192 kbps.

---

## 3. Studio Playout (Downstream / Receivers)

### A. vMix Studio
1. Click **Add Input**.
2. Choose the **Stream / SRT** tab.
3. Set **Type:** `Caller`.
4. Configure:
   * **Hostname:** `SERVER_IP`
   * **Port:** `8890`
   * **Latency:** `2000` ms
   * **Stream ID:** `read:STREAM_NAME` (do not prefix with `streamid=`)
5. Click **OK**. The feed plays with low latency.

### B. VLC Media Player
1. Open **Media** > **Open Network Stream** (Ctrl+N).
2. Enter:
   ```
   srt://SERVER_IP:8890?streamid=read:STREAM_NAME
   ```
3. Click **Play**.

### C. Hardware Decoders / TV Pool (Multi-Client, No Stream ID)
Many broadcast decoders have no Stream ID field. Use the **SLS Multi-Client Hub on port `12105`**:

1. Configure the downstream decoder:
   * **Protocol:** `SRT (Caller)`
   * **Hostname:** `SERVER_IP`
   * **Port:** `12105`
   * **Stream ID:** *(leave empty)*
   * **Passphrase:** *(leave empty)*
   * **Latency:** `200` ms (adjust to link quality)
2. Port `12105` advantages:
   * Dozens of receivers can pull simultaneously without socket conflicts.
   * Each decoder appears in the dashboard's **Active Listeners (Receivers)** panel with its IP and bitrate, labeled `HUB_SLS:12105`.

### D. Dedicated 1:1 Listener (Ports 12106, 12107, ...)
For an isolated point-to-point receiver:
1. Create a route destination on a dedicated port (for example `12106`).
2. On the decoder:
   * **Type:** `Caller`
   * **Hostname:** `SERVER_IP`
   * **Port:** `12106`
   * **Stream ID:** *(empty)*

### E. Live Preview in a Browser
* **HLS preview:** `http://SERVER_IP:8080/hls/STREAM_NAME/index.m3u8`
* **WebRTC ultra-low latency:** `http://SERVER_IP:8889/STREAM_NAME/`

---

## 4. Route Management & Failover

1. **Primary source:** live inbound SRT feed, a dedicated SRT listener port, or an SRT caller pull.
2. **Secondary source:** an independent failover path. If the primary drops, the gateway switches automatically without interrupting downstream output.
3. **Multi-destination fan-out:** one input feeds many outputs at once (studio SRT, YouTube RTMP, playout).
   * **Passthrough (copy)** mode costs nearly zero CPU because the bitstream is copied directly.
   * MP2/AC3 audio is transcoded to AAC automatically for RTMP platforms without re-encoding video.

---

## 5. Master Deck ISO Recorder & Cloud Archive

1. **Feed selection:** choose the camera via the *Feed Source* dropdown.
2. **Container format:**
   * **Universal MP4** for web and archival.
   * **QuickTime MOV** with `+faststart` for direct NLE editing (DaVinci Resolve, Final Cut Pro, Premiere Pro).
3. **Bitrate & resolution:** passthrough, 2.5/4.5/6/8/12 Mbps, or custom kbps; original, 1080p, or 720p.
4. **Segment duration:** 15 minutes, 30 minutes, or 1 hour per file.
5. **Clean stop:** the **STOP** button sends SIGINT to FFmpeg so MP4/MOV atoms close cleanly without corrupting the file.
6. **Google Drive sync:** finished segments queue for background upload using 16 MB resumable chunks; Linux file locks prevent premature uploads of files still being written.

---

## 6. Audio Monitoring & Clipping

1. **Real-time VU meters** appear on the web dashboard and remote app with peak-hold ballistics.
2. **Scales:**
   * **dBFS:** -60 to 0 dBFS (digital standard).
   * **dBVU:** -20 to +3 dBVU (broadcast reference: 0 dBVU = -18 dBFS).
3. **DIGITAL CLIP! indicator:** when audio touches 0 dBFS, the red clip lamp lights immediately. Field audio operators must reduce mixer gain.

---

## 7. Remote Android App

The standalone **Makasna Remote** app lets field crews control the server from a phone:

* **Repository:** [justrangga/makasna-remote-controller](https://github.com/justrangga/makasna-remote-controller)
* **Direct download:** `http://SERVER_IP:8080/download/apk` or the app repository's GitHub Releases.
* **Dynamic connection:** enter the server IP, HTTP port (8080), and SRT port (8890). Enable *Remember Login Session* for automatic reconnect.
* **Signal tab:** monitor throughput, connected encoders, and create routes from active feeds.
* **Recorder tab:** control master ISO recording with live timecode and format selection.
* **Routes tab:** start, stop, create, and edit fan-out routes.

---

## 8. Ports & Troubleshooting

| Port | Protocol | Service | Description |
|:---:|:---:|:---|:---|
| **8080** | TCP | Flask Web Dashboard | Web UI, remote API, HLS reverse proxy |
| **8890** | UDP | MediaMTX SRT Server | Primary ingest (publish) and listener pull |
| **1935** | TCP | MediaMTX RTMP Server | Alternative RTMP ingest |
| **8554** | TCP | MediaMTX RTSP Server | Internal RTSP server |
| **8888** | TCP | MediaMTX HLS Server | fMP4 playback engine |
| **8889** | TCP | WebRTC Signaler | Low-latency browser playback |
| **12105** | UDP | SLS Multi-Client Hub | TV Pool egress (simultaneous pull without Stream ID) |
| **12106–12150** | UDP | Dedicated Route Listeners | 1:1 SRT listener ports for dedicated decoders |

### Common Troubleshooting
* **Blank video / buffering:** ensure the field encoder uses strict closed GOP (1–2 s) and B-frames = 0.
* **Connection failures:** verify the cloud firewall allows UDP `8890` and TCP `8080`.
* **Distorted audio:** watch the True Peak VU meter; when the red clip lamp lights, reduce mixer gain before the encoder.
* **SLS clients missing:** check that the feeding route is running and that UDP `12105` is allowed; see the [SLS Hub Setup](docs/wiki/SLS-Hub-Setup.md) wiki page.

For full troubleshooting and installation procedures, see [INSTALL.md](INSTALL.md) and the [Technical Wiki](docs/wiki/Home.md).

---

*Copyright © Makasna Broadcast Infrastructure. All rights reserved.*
