# Ingest Contribution Guide (Field Encoders)

This guide provides practical instructions for broadcast field crews transmitting video to the Makasna Gateway.

---

## 1. OBS Studio Setup

1. Open **Settings** > **Stream**.
2. Set **Service** to `Custom...`.
3. In the **Server** box, enter:
   ```
   srt://IP_SERVER:8890?streamid=publish:STREAM_NAME&latency=2000000
   ```
   *Replace `IP_SERVER` with the server's public IP and `STREAM_NAME` with your camera identifier (e.g. `CAM_MAIN` or `MAKASNA`).*
4. Leave **Stream Key** completely empty.
5. In **Output** > **Streaming**:
   * **Rate Control:** `CBR`
   * **Keyframe Interval:** `2 s` (Strict Closed GOP)
   * **CPU Usage Preset:** `veryfast` (x264) or `P4/P5` (NVENC)
   * **Profile:** `high`
   * **B-frames:** `0` (Zero latency mode)
6. Click **Apply** > **Start Streaming**.

---

## 2. vMix Production Setup

1. Click the gear icon next to **External / Stream**.
2. Select **Destination:** `SRT`.
3. Configure the parameters:
   * **Type:** `Caller`
   * **Hostname:** `IP_SERVER`
   * **Port:** `8890`
   * **Latency:** `2000` ms (or adjusted to mobile connection quality)
   * **Stream ID:** `publish:STREAM_NAME` *(Important: do not add "streamid=")*
4. Click **Start**.

---

## 3. Hardware Encoders (Kiloview, Haivision, LiveU, Teradek)

| Field | Configuration Value |
|:---|:---|
| **Protocol** | SRT Caller (Push) |
| **Server Address** | `IP_SERVER` |
| **Port** | `8890` |
| **Stream ID** | `publish:STREAM_NAME` |
| **Passphrase** | *(Blank unless configured)* |
| **Latency** | `1500 – 2500 ms` |
| **Payload Size** | `1316` (standard 7 TS packets) |
