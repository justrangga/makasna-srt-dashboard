# Makasna SRT Video Transport Gateway Wiki

Welcome to the **Makasna Broadcast Infrastructure Wiki**. This knowledge base provides comprehensive technical documentation, network specifications, hardware encoder configurations, and multi-client distribution guides.

---

## 📚 Table of Contents

1. **[Architecture & Signal Flow](Architecture-and-Signal-Flow.md)**
   - MediaMTX & SRT Core Integration
   - Supervised Route Pipeline & Dual-Source Failover
   - High-Density Playout & Fan-Out Mechanics

2. **[Ingest Contribution Guide (Field Encoders)](Ingest-Contribution-Guide.md)**
   - OBS Studio SRT Configuration
   - vMix Broadcast Setup
   - Hardware Encoders (Kiloview, Haivision, LiveU, Teradek)
   - Strict Closed GOP & Latency Tuning

3. **[Playout & Distribution: TV Pool vs Dedicated](Playout-and-Distribution.md)**
   - Solution A: **SRT Live Server (SLS) Multi-Client Hub (Port 12105)**
     - Simultaneous callers without Stream ID (empty streamid fallback)
     - Real-time receiver telemetry integration (`/api/sls/stat`)
   - Solution B: **1:1 Dedicated Sockets (Ports 12106, 12107, etc.)**
   - Solution C: **MediaMTX Pull with Stream ID (Port 8890)**

4. **[Master Deck ISO Recorder & Cloud Sync](Master-Deck-ISO-Recorder.md)**
   - Frame-accurate segmenting (15m, 30m, 1h)
   - MOV QuickTime (`+faststart`) vs MP4 Universal
   - Clean SIGINT atom finalization
   - Automated Google Drive chunked background upload

5. **[Audio Monitoring & True Peak Metering](Audio-Monitoring-and-Metering.md)**
   - Dual-scale ballistics: dBFS (-60 to 0) & dBVU (-20 to +3)
   - Real-time Digital Clipping alert threshold
   - Auto MP2/AC3 to AAC transcoding for RTMP fan-out

6. **[Port Reference & Network Security](Port-Reference-and-Firewall.md)**
   - UDP & TCP Port Table
   - Cloud Firewall / Security Group configuration
   - Latency buffer calculations based on RTT
