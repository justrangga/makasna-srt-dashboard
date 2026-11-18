# SLS Hub Setup: TV Pool Port 12105

SLS (SRT Live Server) is optional. Install it only when downstream hardware decoders cannot send an SRT Stream ID or when many receivers must pull one port simultaneously.

## What it does

- **Hub port `12105`:** many decoders pull at once; empty Stream ID is mapped to `live/live/stream`.
- **Dedicated ports `12106`+:** 1:1 listener sockets, handled by the dashboard's route engine, not SLS.
- Telemetry: SLS POSTs client stats to the dashboard every 2 s; the Active Listeners panel shows hub clients only while a hub route is running.

## Build from source

```bash
cd /srv/makasna-dashboard
sudo bash scripts/patch-sls.sh
```

The script installs build dependencies, clones `Edward-Wu/srt-live-server` into `/usr/local/src/srt-live-server`, applies three patches, builds, and installs `/usr/local/bin/sls`:

1. Listen port range raised to `65535` (hub ports 12105+ are above upstream's 10000 limit).
2. Empty Stream ID fallback (`live/live/stream`). Both failure modes are covered: missing SRTO_STREAMID and empty-string sid (upstream rejects `''` in `split_sid` before any fallback can trigger).
3. `<time.h>` include fix for current GCC.

## Configure

Create `/etc/sls/sls.conf` (adapt the address `0.0.0.0:12105` only if needed; passphrase fields must stay empty unless you deliberately enable AES):

```text
srt {
    worker_threads 2;
    worker_connections 300;
    log_file logs/error.log;
    log_level info;

    stat_post_url http://127.0.0.1:8080/api/sls/stat;
    stat_post_interval 2;

    server {
        listen 12105;
        latency 120;
        domain_player live;
        domain_publisher uplive;
        backlog 100;
        idle_streams_timeout -1;
        app {
            app_player live;
            app_publisher live;
            record_hls off;
        }
    }
}
```

Key semantics verified against SLS behavior:

- Stream IDs must have **three parts** `host/app/name`. The hub uses `uplive/live/stream` for the feeder (publisher) and the empty-SID fallback maps player connections to `live/live/stream`. The two resolve to the same stream when `domain_publisher uplive;` and `domain_player live;` are set as above.
- Two-part IDs such as `uplive/live` are rejected by SLS.

## systemd service

```ini
[Unit]
Description=SRT Live Server (SLS) TV Pool Hub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/sls
# NOTE: SLS v1.4.x has no -d option. log_file 'logs/error.log' resolves
# relative to WorkingDirectory, so keep WorkingDirectory=/etc/sls.
ExecStart=/usr/local/bin/sls -c /etc/sls/sls.conf
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo mkdir -p /etc/sls/logs
# place sls.conf in /etc/sls/
sudo install -m 644 sls.service /etc/systemd/system/sls.service   # if you created a unit file
sudo systemctl daemon-reload
sudo systemctl enable --now sls
sudo ss -lunp | grep 12105
```

## Feed the hub

The hub has no source until a dashboard route is running. In the dashboard, create a route whose destination is the **SLS Hub (`12105`)** type; the dashboard internally pushes the MediaMTX stream into SLS as caller `srt://127.0.0.1:12105?streamid=uplive/live/stream`. Start the route, then decoders can pull.

## Decoder side

| Parameter | Value |
|:---|:---|
| Mode | Caller |
| Host | gateway public IP |
| Port | `12105` |
| Stream ID | leave empty |
| Passphrase | leave empty |
| Latency | 200–2000 ms per link quality |

## Verify

```bash
# publisher visible in SLS log while route runs
sudo tail -f /etc/sls/logs/error.log | grep -E 'publisher|player'

# pull with empty streamid (simulates a decoder)
ffmpeg -f mpegts -i 'srt://127.0.0.1:12105?mode=caller&latency=200' -c copy -f null -
```

Expected log line for a decoder without Stream ID:

```text
CSLSListener::handler, [IP:PORT], fd=N, empty streamid, fallback to live/live/stream.
CSLSListener::handler, [IP:PORT], sid 'live/live/stream'
CSLSListener::handler, new player[...]..., key_stream_name=uplive/live/stream, publisher=...
```

## Telemetry caveat

`stat_post_url` support in SLS pushes aggregate stats, and the dashboard merges hub players into `/api/srt/inbound` only while a hub route is active. Treat per-client telemetry as best-effort; the primary source of truth is the SLS log.
