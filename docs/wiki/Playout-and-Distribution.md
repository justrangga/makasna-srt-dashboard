# Playout & Distribution Guide: TV Pool vs Dedicated

Makasna Gateway provides flexible egress options tailored to different broadcast receiver hardware limitations.

---

## 1. Solution A: SLS Multi-Client Hub (Port 12105) — TV Pool

### The Problem It Solves
Many legacy hardware decoders (such as older set-top boxes, rackmount satellite IRDs, and closed-circuit decoders) do not feature an input field for SRT `Stream ID`. Traditional FFmpeg 1:1 listener sockets will lock to the first connected caller, causing connection refusal (`connection rejected`) for any additional receivers.

### The SLS Solution
We patched and integrated **SRT Live Server (Edward-Wu/srt-live-server)** into the gateway:
* **Port:** `12105` (UDP)
* **Empty StreamID Fallback:** Decoders connecting without a Stream ID are automatically routed to `live/live/stream`.
* **Simultaneous Callers:** Supports **dozens of TV stations / decoders pulling concurrently** from the same port.
* **Live Telemetry Forwarding:** SLS pushes client metrics every 2 seconds to `/api/sls/stat`. Connected decoders are displayed in the dashboard's **Active Listeners** table with:
  * Stream ID: `HUB_SLS:12105`
  * Remote IP & Port (e.g., `36.80.110.12:61281`)
  * Real-time Egress Bitrate (`Mbps`)
  * Route Name: `SLS TV Pool (Port 12105)`
  * Health status

### Client Configuration (Downstream Receiver / Decoder)
| Parameter | Value | Notes |
|:---|:---|:---|
| **Protocol** | `SRT (Caller)` | Mode Caller / Pull |
| **Hostname / IP** | `IP_SERVER` | Server public IP address |
| **Port** | `12105` | Hub port for TV Pool |
| **Stream ID** | *(Leave blank)* | Empty streamid fallback |
| **Passphrase** | *(Leave blank)* | No encryption |
| **Latency** | `200` ms | Set higher (e.g. 1000–2000 ms) if on public WAN |

---

## 2. Solution B: 1:1 Dedicated Listeners (Port 12106, 12107, etc.)

When a dedicated client or studio requires an isolated port that is strictly bound point-to-point:
* **Port Range:** `12106`–`12150` (UDP)
* **Mode:** Single Receiver Dedicated (1:1)
* **Stream ID:** Not required.
* **Passphrase:** Optional AES passphrase can be set per destination in the Route configuration.

---

## 3. Solution C: MediaMTX Stream ID Ingest / Egress (Port 8890)

For software receivers (vMix, OBS Studio, VLC) and modern decoders that support SRT Stream IDs:
* **Ingest (Field Contribution):** `srt://IP_SERVER:8890?streamid=publish:STREAM_NAME`
* **Egress (Studio Playout):** `srt://IP_SERVER:8890?streamid=read:STREAM_NAME`
