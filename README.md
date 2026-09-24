# Makasna Live Video Transport Gateway

[Bahasa Indonesia](#bahasa-indonesia) | [English](#english)

---

<a id="bahasa-indonesia"></a>
## Bahasa Indonesia

### 1. Ringkasan & Arsitektur Sistem

**Makasna Live Video Transport Gateway** adalah platform broadcast transport gateway tingkat enterprise berbasis Python/Flask, MediaMTX, dan FFmpeg. Gateway ini dirancang khusus untuk ingestion, transmisi redundan (failover), transcoding real-time, monitoring latensi rendah, fan-out multi-tujuan, serta perekaman bersegmen otomatis ke Google Drive.

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
        │   MULTI-DESTINATION FAN-OUT  │        │   SEGMENTED RECORDING        │        │   OPERATOR PREVIEW & AUDIT   │
        │   • SRT Caller / Listener    │        │   • Segmen 15m / 30m / 1h    │        │   • fMP4 HLS Buffer (12s)    │
        │   • RTMP / RTMPS / YouTube   │        │   • Kompresi Hemat s/d 92%   │        │   • WebRTC Sub-Second (<0.3s)│
        │   • UDP MPEG-TS / RTSP       │        │   • Google Service Account   │        │   • Same-Origin HTTPS Proxy  │
        │   • Auto MP2->AAC Transcode  │        │   • Auto Cloud Upload Worker │        │   • Fixed Scroll Event Log   │
        └──────────────────────────────┘        └──────────────────────────────┘        └──────────────────────────────┘
```

---

### 2. Fitur Utama

#### A. Gateway Routing & Hot-Standby Failover
* **Dual-Source Architecture:** Setiap rute mendukung *Primary Contribution Source* dan *Secondary Source (Failover)* independen.
* **Kebijakan Failover:** `Maintain Primary`, `Invert (Stick to Secondary)`, atau `Manual Switch`.
* **Protokol Ingest Lengkap:**
  * **SRT Listener:** Menunggu koneksi push dari encoder lapangan pada port UDP spesifik.
  * **SRT Caller (Pull):** Menarik stream langsung dari server/edge SRT eksternal.
  * **SRT Rendezvous:** Melakukan NAT-traversal peer-to-peer dua arah.
  * **Local Stream:** Mengadopsi stream yang sudah masuk ke MediaMTX (format `publish:STREAM_ID`).
  * **Direct Stream URLs:** RTSP, RTMP, HTTP, atau UDP TS.
* **Enkripsi & Latensi:** Mendukung SRT AES-128/256 Passphrase serta buffer latensi yang dapat disesuaikan (default 200 ms s/d 8000 ms).
* **Live Probing (`ffprobe`):** Analisis instan resolusi, framerate, dan susunan multitrack audio sebelum rute dijalankan.

#### B. Multi-Destination Fan-Out (Egress)
* Distribusi 1 sumber ingest ke berbagai tujuan secara bersamaan:
  * **SRT Caller / Listener** (Point-to-Point broadcast link).
  * **RTMP / RTMPS** (YouTube Live, Facebook Live, Twitch, CDN kustom).
  * **UDP MPEG-TS Multicast/Unicast** (Decoder perangkat keras studio / IRD).
  * **RTSP / HTTP**.
* **Direct Stream Copy:** Pilihan default `-c copy` untuk efisiensi CPU 0% tanpa penurunan kualitas video bitstream.
* **Auto-Fallback Audio Transcoding:** Deteksi otomatis feed broadcast bertipe audio MPEG-1 Layer II (MP2) atau AC3; mengonversi audio ke AAC (`-c:a aac 128k/160k`) secara otomatis untuk tujuan FLV/RTMP/YouTube guna mencegah crash muxer, tanpa menyentuh stream video (`-c:v copy`).

#### C. Engine Transcoding & Pemrosesan Video
* **Video Rescaling:** Mengubah resolusi video (1080p, 720p, 576p PAL, 480p NTSC, atau resolusi kustom).
* **Frame Rate Conversion:** Penyesuaian framerate siaran (25 fps, 30 fps, 50 fps, 60 fps).
* **Deinterlacing:** Filter adaptif `bwdif` untuk feed interlaced (1080i/576i) menjadi progressive.
* **Bitrate Control:** Target Video Bitrate, Maximum Bitrate (`-maxrate`), dan VBV Buffer Size (`-bufsize`).
* **Encoder Presets:** Profil kompresi H.264 (`ultrafast`, `superfast`, `veryfast`, `faster`, `medium`).
* **Audio Track Mapping & Transcode:** Pemetaan track audio tertentu (`-map 0:a:X`), transcode AAC / Opus, sample rate 48 kHz / 44.1 kHz, dan bitrate 64k s/d 320k.

#### D. Inbound SRT Ingest Monitor
* Deteksi stream SRT masuk secara pasif melalui MediaMTX REST API (`/v3/srtconns/list`).
* Tabel pemantau real-time: **Stream ID**, **Remote IP & Port Pengirim**, **Receive Bitrate (Mbps)**, **RTT Latency (ms)**, **Packet Loss (%)**, dan **Uptime**.
* **1-Click Preview:** Meninjau feed yang masuk secara instan tanpa perlu membuat rute terlebih dahulu.
* **1-Click `+ Route`:** Mengadopsi stream yang sedang masuk menjadi rute gateway resmi hanya dengan satu klik.

#### E. Blackmagic HyperDeck Studio Console & Perekaman Bersegmen Mandiri
* **Konsol Rack-Mount HyperDeck Studio Terintegrasi:**
  * Konsol broadcast ISO recorder bergaya hardware rack-mount profesional di tab *Recordings & Cloud Archive*.
  * **LCD Confidence Monitor (16:9):** Pemutaran video fMP4 HLS langsung dari feed yang dipilih, otomatis menampilkan *SMPTE Color Bars Test Pattern* saat idle/standby.
  * **Broadcast OSD & Digital Timecode:** Overlay live status mode (`● REC` / `● STBY`), format stream, label input feed, serta running digital timecode broadcast monospace `00:00:00:00`.
  * **Stereo Peak VU Meters:** Dua meteran kanal audio LED vertikal (CH1 / CH2) dinamis dengan zona Green (`-40dB`), Amber (`-12dB`), dan Red (`0dB Peak`).
  * **Dual Media Bays:** 
    * **Slot 1 (Local NVMe/SSD):** Kapasitas disk lokal, usage bar real-time, dan kalkulator sisa jam rekam (`~XX.X Jam Tersedia`).
    * **Slot 2 (Google Drive Cloud):** Status sinkronisasi akun Google Drive dan target folder cloud archive.
  * **Tombol Fisik Tactile [ ● RECORD ] & [ ■ STOP ]:** Tombol hardware glowing red pulse saat merekam dan tombol stop brushed steel untuk penghentian aman tanpa merusak file.
* **Pilihan Feed Source Dinamis:**
  * **Live Inbound SRT Ingest (Port 8890 Masuk):** Merekam langsung stream yang dikirim encoder lapangan (`publish:STREAM_ID`) tanpa perlu membuat konfigurasi rute terlebih dahulu.
  * **SRT Caller (Server Pull / Kita Call):** Merekam stream yang ditarik server dari encoder/edge remote.
  * **SRT Listener / Rendezvous / Direct:** Merekam feed dari rute listening atau direct stream URL.
* **Format Container & Kontrol Kompresi Fleksibel:**
  * **Pilihan Container:** **MP4** (universal web/archive) atau **MOV** (Apple QuickTime dengan flag `+faststart` untuk editing NLE broadcast di Premiere Pro, Final Cut Pro, DaVinci Resolve).
  * **Pilihan Bitrate:** Presets (1.2 Mbps, 2.0 Mbps, 3.5 Mbps, 5.0 Mbps, 8.0 Mbps, Direct Stream Copy) serta **Custom Bitrate** (bebas input angka kbps sesuai kebutuhan).
  * **Pilihan Resolusi:** Source Native, 1080p, 720p, 480p, 4K UHD, serta **Custom Resolution (Width x Height)** dengan aspect ratio auto-padding.
  * **Durasi Segmen Cepat:** 15 Menit, 30 Menit, atau 1 Jam (60m).
* **Arsitektur Perekaman Independen (Zero Disruption):**
  * Perekaman berjalan pada subprocess terpisah dari proses rute utama. Operator dapat menyalakan atau mematikan rekaman berkali-kali tanpa memutus siaran langsung ke YouTube atau pemirsa SRT.
  * Penghentian bersih via `signal.SIGINT` memastikan penulisan header `moov atom` MP4/MOV tertutup sempurna.
* **Sinkronisasi Cloud Google Drive Andal (16MB Resumable Chunks):**
  * Pengunggahan file rekaman gigabyte bersegmen 16 MB dengan auto-retry exponential backoff (hingga 8 kali) dan socket timeout 120 detik.
  * Deteksi file lock aktif via Linux `/proc/[0-9]*/fd/*` guna memastikan file yang masih ditulis FFmpeg tidak diambil oleh background worker.
  * Antrean background async non-blocking dengan indikator progres live (`UPLOADING %`), auto-retry file failed, serta pemutaran rekaman langsung di browser.

#### F. Preview Player Broadcast & WebRTC
* **Fragmented MP4 HLS (`fmp4`):** Menggantikan LL-HLS micro-parts yang rentan stuttering dengan segmen 2 detik yang mulus dan stabil.
* **Buffer Margin 12 Detik & Auto-Nudge:** Player HLS.js dilengkapi buffer pengaman untuk mengatasi fluktuasi koneksi seluler tanpa buffering terus-menerus.
* **Same-Origin HTTPS Proxy (`/hls/...`):** Stream preview dialirkan melalui proxy reverse gateway lokal, menghilangkan masalah pemblokiran *Mixed-Content SSL* dan port non-standar `:8888`.
* **Viewer WebRTC Ultra-Low Latency (`<0.3s`):** Pilihan tombol buka pemutar WebRTC untuk pemantauan video real-time sub-detik tanpa latensi.

#### G. Modal Connection URLs Interaktif
* Dialog referensi parameter endpoint untuk mempermudah konfigurasi software eksternal:
  * **Sender (Pengirim):** OBS Studio (Service: Custom SRT), vMix / Hardware Encoders, FFmpeg CLI.
  * **Receiver (Penerima):** VLC Media Player, OBS Media Source, Browser HLS Player, RTSP Player.
* Target Stream ID dinamis dan tombol copy satu klik (*1-click copy*).

#### H. Gateway Event Log & Sistem Audit
* Log aktivitas sistem dan perubahan status gateway.
* **Fixed-Height Viewport Container:** Tampilan log dibatasi dengan scrollbar internal, mencegah halaman meregang (*infinite scroll*) ke bawah.
* **Fitur Hapus Log (Clear Event Log):** Tombol pembersih riwayat log dan endpoint backend `DELETE /api/events`.

#### I. Keandalan Sistem & Circuit Breaker
* **Exponential Backoff:** Mencegah supervisor melakukan restart loop terus-menerus ketika stream remote offline (backoff 5s hingga 30s; berhenti otomatis setelah 5 kali kegagalan berturut-turut).
* **In-Memory Caching:** Konfigurasi rute dan event log disimpan di memori proses dengan sinkronisasi disk asynchronous untuk menghilangkan lonjakan beban I/O server.

#### J. Desain Antarmuka Dark Broadcast Control Room
* Nuansa visual ruang kendali siaran gelap profesional (`#08080A`, border `#27272A`, aksen Cyan `#00E5FF` dan Royal Blue `#2563EB`).
* Bebas dari emoji informal; seluruh ikon menggunakan vektor garis SVG murni.
* Sepenuhnya responsif untuk smartphone (kartu modular adaptif, navigasi bawah / *bottom navigation bar*, dan modal fullscreen sheet).

---

### 3. Panduan Instalasi & Deploy Server

#### Kebutuhan Sistem
* OS: Debian 12 (Bookworm) atau Ubuntu 22.04/24.04 LTS.
* Python 3.10 atau lebih baru (dengan modul `venv`).
* FFmpeg & `ffprobe` (versi 5.x / 6.x atau lebih baru).
* Binary MediaMTX (v1.11.3 atau lebih baru).

#### Instalasi Dependensi Sistem
```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip ffmpeg curl
```

#### Clone Repository & Setup Virtual Environment
```bash
git clone https://github.com/justrangga/makasna-srt-dashboard.git /opt/makasna-dashboard
cd /opt/makasna-dashboard
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

#### Menjalankan sebagai Service Systemd

1. **Service MediaMTX (`/etc/systemd/system/mediamtx.service`):**
```ini
[Unit]
Description=MediaMTX SRT and Live Streaming Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mediamtx /etc/mediamtx/mediamtx.yml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

2. **Service Gateway Dashboard (`/etc/systemd/system/makasna-dashboard.service`):**
```ini
[Unit]
Description=Makasna Live Video Transport Gateway
After=network.target mediamtx.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/makasna-dashboard
Environment="PATH=/opt/makasna-dashboard/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
Environment="PORT=8080"
Environment="SECRET_KEY=ganti_dengan_secret_key_acak"
Environment="DASHBOARD_USER=admin"
Environment="DASHBOARD_PASS=ganti_dengan_password_anda"
ExecStart=/opt/makasna-dashboard/.venv/bin/python3 app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Aktifkan service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mediamtx
sudo systemctl enable --now makasna-dashboard
```

---

### 4. Daftar Port & Firewall Jaringan

| Port | Protokol | Fungsi | Keterangan Akses |
|---|---|---|---|
| **`8890`** | UDP | SRT Ingest & Egress (MediaMTX) | Wajib dibuka untuk publisher & receiver |
| **`1935`** | TCP | RTMP / FLV Internal Sink | Localhost / Encoder lapangan |
| **`8554`** | TCP | RTSP Stream Ingest/Read | Opsional |
| **`8888`** | TCP | HLS Server (fMP4 Engine) | Internal / Proxy ke dashboard |
| **`8889`** | TCP | WebRTC HTTP Signal Viewer | Sub-second Live Viewer |
| **`9997`** | TCP | MediaMTX REST Control API | **Localhost Only** (`127.0.0.1`) |
| **`8080`** | TCP | Gateway Dashboard HTTP | Reverse proxy (Cloudflare Tunnel / Nginx) |
| **`443`** | TCP | HTTPS Public Access | Cloudflare Tunnel / SSL Proxy |

---

### 5. Format Endpoint URL

* **Ingest SRT Pengirim (OBS / vMix):**
  * `srt://IP_SERVER:8890?streamid=publish:NAMA_STREAM`
* **Membaca SRT Penerima (VLC / OBS Media Source):**
  * `srt://IP_SERVER:8890?streamid=read:NAMA_STREAM`
* **Browser HLS Preview URL:**
  * `https://domain-anda.com/hls/NAMA_STREAM/index.m3u8`
* **WebRTC Live Viewer URL:**
  * `http://IP_SERVER:8889/NAMA_STREAM/`

---

<a id="english"></a>
## English

### 1. Overview & System Architecture

**Makasna Live Video Transport Gateway** is an enterprise-grade broadcast video routing, failover, transcoding, and archiving platform powered by Python/Flask, MediaMTX, and FFmpeg. Engineered for low-latency live contribution, redundant ingress switching, multi-destination fan-out, and internal segmented recording with automated Google Drive synchronization.

---

### 2. Core Capabilities

#### A. Gateway Routing & Hot-Standby Failover
* **Dual-Source Redundancy:** Dedicated Primary and Secondary sources per gateway route.
* **Failover Policies:** `Maintain Primary`, `Invert (Stick to Secondary)`, or `Manual Switch`.
* **Ingest Protocol Matrix:**
  * **SRT Listener:** Dedicated UDP port binding for remote contributions.
  * **SRT Caller (Pull):** Pulls live streams from external broadcast servers.
  * **SRT Rendezvous:** Bidirectional peer-to-peer traversal.
  * **Local Stream:** Ingests any active stream published to MediaMTX (`publish:STREAM_ID`).
  * **Direct Stream URLs:** RTSP, RTMP, HTTP, and UDP MPEG-TS.
* **Security & Latency Tuning:** SRT AES-128/256 passphrase encryption and custom latency buffer (200 ms to 8000 ms).
* **Live Ingest Prober (`ffprobe`):** Instant pre-flight analysis of incoming video codecs, dimensions, framerates, and audio multitrack indices.

#### B. Multi-Destination Fan-Out (Egress)
* Simultaneous stream re-transmission across diverse protocols:
  * **SRT Caller / Listener** (Point-to-point contribution links).
  * **RTMP / RTMPS** (YouTube Live, Facebook Live, Twitch, custom CDN ingress).
  * **UDP MPEG-TS** (Studio hardware decoders / IRD appliances).
  * **RTSP / HTTP**.
* **Direct Stream Copy:** Zero-overhead `-c copy` pipeline preserves 100% bitstream integrity with minimal CPU utilization.
* **Automated Broadcast Audio Fallback:** Automatically detects MPEG-1 Layer II (MP2) or AC3 audio tracks and converts them to AAC (`-c:a aac`) when targeting RTMP/FLV/YouTube destinations to prevent muxer container crashes while keeping video untouched (`-c:v copy`).

#### C. Broadcast Transcoding Pipeline
* **Resolution Scaling:** 1080p, 720p, 576p PAL, 480p NTSC, and arbitrary custom geometries.
* **Framerate Standardization:** Conversion across broadcast standards (25, 30, 50, 60 fps).
* **Broadcast Deinterlacer:** Adaptive `bwdif` filter turns 1080i/576i interlaced signals into smooth progressive video.
* **Bitrate & VBV Control:** Target video bitrates, maxrates, and VBV buffer sizing.
* **H.264 Encoder Presets:** Selectable compression presets (`ultrafast` through `medium`).
* **Audio Routing & Transcode:** Independent audio channel mapping (`-map 0:a:X`), AAC / Opus encoding, custom sample rates, and bitrates.

#### D. Inbound SRT Ingest Monitor
* Real-time passive tracking of incoming SRT publishers via the MediaMTX API (`/v3/srtconns/list`).
* Live telemetry grid: **Stream ID**, **Sender IP & Port**, **Receive Bitrate (Mbps)**, **RTT Latency (ms)**, **Packet Loss (%)**, and **Connection Uptime**.
* **1-Click Preview:** Monitor incoming feeds before committing them to active routes.
* **1-Click `+ Route`:** Immediately adopt incoming streams into managed routes with auto-filled parameters.

#### E. Blackmagic HyperDeck Studio Console & On-Demand Segmented Recording
* **Rack-Mount HyperDeck Studio Master Recorder Interface:**
  * Broadcast-grade hardware console styling directly embedded inside the *Recordings & Cloud Archive* workspace.
  * **Built-in 16:9 LCD Confidence Monitor:** Low-latency fMP4 HLS live video playback from any selected feed, automatically falling back to SMPTE Color Bars during standby.
  * **Broadcast OSD & Timecode Engine:** Real-time on-screen status (`● REC` / `● STBY`), video codec/bitrate badge, input source label, and high-precision monospace digital timecode counter `00:00:00:00`.
  * **Stereo Peak VU Meters:** Dynamic dual-channel audio monitoring bars (CH1 & CH2) featuring Green (`-40dB`), Amber (`-12dB`), and Red (`0dB Peak`) zones.
  * **Dual Media Bays:** 
    * **Slot 1 (Local NVMe/SSD):** Live disk capacity, usage bar, and remaining record time estimation (`~XX.X Hours Available`).
    * **Slot 2 (Google Drive Cloud Archive):** Real-time OAuth/Service Account status and target cloud folder indicators.
  * **Tactile Hardware Controls [ ● RECORD ] & [ ■ STOP ]:** Glowing pulsing red record button and brushed-steel stop button for safe, instant capture control.
* **Flexible Multi-Source Ingest Selection:**
  * **Live Inbound SRT Ingest (Port 8890 Push):** Instant 1-click recording of incoming client publishers (`publish:STREAM_ID`) without requiring a pre-configured gateway route.
  * **SRT Caller Routes (Server Pull / Call):** Capture streams pulled from remote encoders, gateways, or edge servers.
  * **SRT Listener / Rendezvous / Direct Routes:** Seamless recording from listening port streams or RTSP feeds.
* **Versatile Container Formats & Compression Controls:**
  * **Container Options:** **MP4** (universal web standard) or **MOV** (Apple QuickTime with `+faststart` for broadcast NLE suites like DaVinci Resolve, Final Cut Pro, and Adobe Premiere Pro).
  * **Bitrate Controls:** High-efficiency presets (1.2 Mbps, 2.0 Mbps, 3.5 Mbps, 5.0 Mbps, 8.0 Mbps, Direct Stream Copy) plus **Custom Bitrate in kbps**.
  * **Resolution Scaling:** Source Native, 1080p, 720p, 480p, 4K UHD, plus **Custom Resolution (Width x Height)** with aspect-ratio preserving padding.
  * **Segment Duration:** 15 Minutes, 30 Minutes, or 1 Hour (60m).
* **Decoupled Zero-Disruption Architecture:**
  * Perekaman berjalan pada subprocess FFmpeg sekunder independen. Operators can start and stop recordings at will without interrupting or glitching primary transmission streams or egress fan-outs.
  * Clean `signal.SIGINT` termination guarantees proper closure of the MP4/MOV `moov atom` header to prevent file corruption.
* **Resilient Google Drive Cloud Sync (16MB Resumable Chunks):**
  * Resumable chunked upload protocol (16 MB chunks) with 8x exponential backoff retry logic and 120s socket timeout.
  * Linux `/proc/[0-9]*/fd/*` file lock inspection prevents uploading segments currently actively written by FFmpeg.
  * Asynchronous background queue with live progress indicators (`UPLOADING %`), auto-retry for interrupted uploads, and in-browser playback.

#### F. High-Performance Preview & WebRTC
* **Fragmented MP4 HLS (`fmp4`):** Stable 2-second segments eliminate micro-gap stalls and playback freezing.
* **12-Second Buffer Margin & Auto-Nudge:** Robust playback buffering prevents underruns over mobile connections.
* **Same-Origin HTTPS Proxy (`/hls/...`):** Routes HLS traffic through the dashboard's HTTPS origin, preventing Mixed-Content blocks and cellular port filtering.
* **Sub-Second WebRTC Viewer (`<0.3s`):** Dedicated low-latency playback option for real-time camera and live event monitoring.

#### G. Interactive Connection URLs Modal
* Contextual setup instructions and connection strings:
  * **Senders:** OBS Studio, vMix / Hardware Encoders, FFmpeg CLI.
  * **Receivers:** VLC Media Player, OBS Media Source, Web HLS Players, RTSP Clients.
* Dynamic Stream ID substitution with 1-click clipboard copy.

#### H. Gateway Event Log & System Audit
* Real-time operational audit trail.
* **Fixed-Height Viewport Container:** Confines log entries to an internal scrollable window, preventing infinite page growth.
* **Clear Event Log Action:** Secure 1-click log purge via `DELETE /api/events`.

#### I. Reliability & Resilience
* **Exponential Backoff Circuit Breaker:** Protects system resources by throttling restart attempts against offline remote SRT targets (5s to 30s backoff; stops after 5 consecutive failures).
* **In-Memory Caching:** Eliminates disk I/O bottlenecks by caching route configurations and event entries in RAM with debounced persistence.

#### J. Dark Broadcast Control Room Interface
* High-contrast theme (`#08080A`, border `#27272A`, accents in Cyan `#00E5FF` and Royal Blue `#2563EB`).
* Clean, professional vector line SVG icons.
* Fully responsive across smartphones and multi-display control room workstations.

---

### 3. Server Deployment

#### Environment Requirements
* Debian 12 (Bookworm) or Ubuntu 22.04/24.04 LTS.
* Python 3.10+ (with `venv`).
* FFmpeg & `ffprobe` (5.x or 6.x+).
* MediaMTX binary (v1.11.3+).

#### Quick Setup
```bash
git clone https://github.com/justrangga/makasna-srt-dashboard.git /opt/makasna-dashboard
cd /opt/makasna-dashboard
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

#### Systemd Services
* **MediaMTX:** Managed by `/etc/systemd/system/mediamtx.service`.
* **Dashboard Gateway:** Managed by `/etc/systemd/system/makasna-dashboard.service`.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mediamtx
sudo systemctl enable --now makasna-dashboard
```

---

### 4. Port Reference

| Port | Protocol | Purpose | Access Policy |
|---|---|---|---|
| **`8890`** | UDP | SRT Ingest / Egress | Open to field publishers and receivers |
| **`1935`** | TCP | RTMP / FLV Ingest | Localhost / Field encoders |
| **`8554`** | TCP | RTSP Stream Ingest/Read | Private / optional |
| **`8888`** | TCP | HLS Server (fMP4 Engine) | Internal / Proxied via Dashboard |
| **`8889`** | TCP | WebRTC HTTP Signaler | Low-latency live viewer |
| **`9997`** | TCP | MediaMTX REST API | **Localhost Only** (`127.0.0.1`) |
| **`8080`** | TCP | Gateway Web Dashboard | Upstream to reverse proxy |
| **`443`** | TCP | Public Secure Dashboard | Cloudflare Tunnel / Reverse Proxy |

---

### 5. Documentation & Booklet
Technical booklet proposal (22-page dark mode PDF) is available for download at `/download/booklet` or in the repository root as `makasna-client-booklet.pdf`.

---

### 6. License
Released under the [MIT License](LICENSE).
