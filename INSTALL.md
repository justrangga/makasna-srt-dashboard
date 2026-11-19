# Self-Hosted Installation Guide

This guide installs the Makasna dashboard from a clean Ubuntu server. Prerequisites, MediaMTX, systemd, firewall rules, updates, and troubleshooting are covered in order.

## 1. Server Requirements

- Ubuntu 22.04 or 24.04 (amd64 or arm64).
- Minimum 2 vCPU, 4 GB RAM.
- A public IP or firewall forwarding for SRT.
- Root access via sudo.
- MediaMTX v1.11+ installed and running with its API on `127.0.0.1:9997`.
- FFmpeg 6.0+.
- Python 3.10+.

## 2. System Dependencies

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip ffmpeg curl jq ca-certificates
```

Verify tools:

```bash
ffmpeg -version | head -1
python3 --version
git --version
```

## 3. Clone the Repository

```bash
sudo mkdir -p /srv
sudo git clone https://github.com/justrangga/makasna-srt-dashboard.git /srv/makasna-dashboard
sudo chown -R "$USER":"$USER" /srv/makasna-dashboard
cd /srv/makasna-dashboard
```

## 4. Create the Python Virtual Environment

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip wheel
python -m pip install -r requirements.txt
python -m compileall -q app.py
```

`compileall` must finish without errors before continuing.

## 5. Create the Service User and Environment

```bash
sudo useradd --system --home /srv/makasna-dashboard --shell /usr/sbin/nologin makasna 2>/dev/null || true
sudo chown -R makasna:makasna /srv/makasna-dashboard
```

Create the environment file. Replace all example values before starting the service:

```bash
sudo install -m 600 -o root -g root .env.example /etc/makasna-dashboard.env
sudoedit /etc/makasna-dashboard.env
```

Minimum contents:

```ini
PORT=8080
SECRET_KEY=generate-a-long-random-value
DASHBOARD_USER=admin
DASHBOARD_PASS=
MEDIAMTX_API=http://127.0.0.1:9997
MEDIAMTX_CONF=/etc/mediamtx/mediamtx.yml
SERVER_PUBLIC_IP=203.0.113.10
```

Leave `DASHBOARD_PASS` empty: the first dashboard visit opens a one-time setup wizard that asks for the operator username and password. The account is stored hashed in `auth_config.json` (mode `600`) and is used for every login afterwards; the wizard never appears again.

Generate a strong secret with `openssl rand -hex 32`. Never commit the real `.env` or reuse example values in production.

## 6. Configure MediaMTX

Install MediaMTX and keep its API bound to localhost. A baseline configuration is provided in `config/mediamtx.yml.example`:

- SRT address `:8890` (ingest and listener pull).
- API address `127.0.0.1:9997` (required by the dashboard monitor; do not expose publicly).
- HLS (`:8888`) and WebRTC (`:8889`) enabled — the preview players in the telemetry modal depend on them.

After editing the configuration:

```bash
sudo systemctl restart mediamtx
curl -fsS http://127.0.0.1:9997/v3/paths/list
```

The API call must return JSON before continuing.

## 7. Install the systemd Service

```bash
sudo install -m 644 systemd/makasna-dashboard.service /etc/systemd/system/makasna-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable --now makasna-dashboard
sudo systemctl status makasna-dashboard --no-pager
```

Validate from the server:

```bash
curl -fsI http://127.0.0.1:8080/login | head -1
curl -fsS http://127.0.0.1:9997/v3/paths/list | head -c 200; echo
sudo ss -ltnp | grep ':8080'
sudo ss -lunp | grep ':8890'
sudo journalctl -u makasna-dashboard -n 100 --no-pager
```

## 8. Firewall

Allow only the ports actually used:

```bash
sudo ufw allow 22/tcp    # administration
sudo ufw allow 8080/tcp  # dashboard
sudo ufw allow 8890/udp  # SRT ingest/egress
sudo ufw allow 12105:12150/udp  # only if SLS or dedicated listeners are used
sudo ufw enable
sudo ufw status verbose
```

## 9. First Route

1. Point a field encoder at `srt://SERVER_PUBLIC_IP:8890` with `streamid=publish:STREAM_NAME` and confirm it appears in the ingest monitor.
2. Log in to the dashboard and create a route from that stream.
3. Set the destination: MediaMTX pull (`read:STREAM_NAME` on port `8890`), an SLS hub port, or an RTMP target.
4. Start the route and verify the destination receives video.

## 10. SLS Multi-Client Hub (Optional)

Needed only when downstream decoders cannot send a Stream ID:

```bash
sudo bash scripts/patch-sls.sh
```

The script installs build dependencies, clones `Edward-Wu/srt-live-server`, applies the port-range, empty-Stream-ID fallback, and GCC compatibility patches, then builds and installs `/usr/local/bin/sls`. Configure `/etc/sls/sls.conf` and the systemd unit per [SLS Hub Setup](docs/wiki/SLS-Hub-Setup.md).

## 11. Backup and Update

Back up runtime state before changes:

```bash
sudo tar -C /srv -czf /root/makasna-dashboard-backup-$(date +%F).tgz \
  makasna-dashboard/routes.json \
  makasna-dashboard/events.json
sudo cp -a /etc/makasna-dashboard.env /root/makasna-dashboard.env.backup
```

Apply updates:

```bash
cd /srv/makasna-dashboard
sudo systemctl stop makasna-dashboard
sudo git pull --ff-only origin main
sudo -u makasna .venv/bin/pip install -r requirements.txt
sudo systemctl start makasna-dashboard
sudo journalctl -u makasna-dashboard -n 100 --no-pager
```

## 12. Uninstall and Rollback

```bash
sudo systemctl disable --now makasna-dashboard
sudo rm -f /etc/systemd/system/makasna-dashboard.service /etc/makasna-dashboard.env
sudo rm -rf /srv/makasna-dashboard
```

To roll back an update instead, check out the last known-good commit, reinstall requirements, and restart the service. Keep the backup archive from step 11 until the rollback is verified.

## Quick Troubleshooting

| Symptom | Check |
|:---|:---|
| Dashboard unreachable | `sudo systemctl status makasna-dashboard`, `sudo ss -ltnp | grep ':8080'` |
| Ingest monitor empty | MediaMTX API on `127.0.0.1:9997`, UDP `8890` allowed, encoder stream ID format |
| Route exits immediately | `sudo journalctl -u makasna-dashboard -f`, FFmpeg version, output URL |
| SLS clients missing | Feeding route running, UDP `12105` allowed, [SLS Hub Setup](docs/wiki/SLS-Hub-Setup.md) |
