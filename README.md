# Makasna SRT Dashboard

A lightweight Flask dashboard for monitoring a MediaMTX server and managing FFmpeg-based SRT/RTMP relay destinations.

## Features

- MediaMTX active-stream and host resource statistics
- SRT, RTSP, RTMP, and HTTP media sources
- SRT, RTMP, and RTMPS relay destinations
- Selectable audio track detection with `ffprobe`
- Automatic relay restart while a destination remains enabled
- Per-relay logs and persistent relay definitions
- Direct Copy and configurable H.264/AAC bitrate modes

## Architecture

Publishers send streams to MediaMTX. The Flask dashboard queries the local MediaMTX Control API and starts one FFmpeg process per enabled destination. Relay definitions are stored in `forwards.json`; FFmpeg output is stored under `logs/`. These runtime files are intentionally ignored by Git.

## Requirements

- Linux or another environment capable of running Flask and FFmpeg
- Python 3.9 or newer
- FFmpeg and `ffprobe`
- MediaMTX compatible with the supplied configuration keys
- A non-root service account for service installation

## Install

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
cp config/mediamtx.yml.example config/mediamtx.yml
```

Generate a secret rather than using the example value:

```sh
python -c "import secrets; print(secrets.token_hex(32))"
```

Export configuration before starting the development server:

```sh
export SECRET_KEY="generated-value"
export PORT=8080
python app.py
```

If `SECRET_KEY` is absent, the application generates a random key for that process. Sessions will not survive a restart. The dashboard currently has no built-in login, so bind it to localhost or protect it with an authenticated reverse proxy and firewall.

MediaMTX must use `config/mediamtx.yml` (or another copied configuration). The example enables its Control API only on `127.0.0.1:9997`, matching the dashboard. It allows anonymous publishing and reading on arbitrary paths; restrict MediaMTX authentication and network access before Internet exposure.

## SRT usage

Replace `SERVER_IP` and `STREAM_NAME` with your server address and chosen stream path.

Publish:

```text
srt://SERVER_IP:8890?streamid=publish:STREAM_NAME
```

Read:

```text
srt://SERVER_IP:8890?streamid=read:STREAM_NAME
```

A local stream name such as `live` is resolved by the dashboard as `rtsp://127.0.0.1:8554/live`. Full RTSP, RTMP, SRT, or HTTP source URLs can also be entered.

## Audio and processing modes

Use **Detect Audio Tracks** after entering an active source, then select the desired track. FFmpeg maps the first video track and the selected zero-based audio track; missing optional tracks do not prevent command construction.

- **Direct Copy** copies video and audio packets without re-encoding. It uses little CPU and preserves the original bitrate and codecs, but the destination must support those codecs and bitrate cannot be changed.
- **Custom Bitrate** re-encodes video with H.264 (`libx264`) and audio with AAC. Video bitrate, maximum bitrate, buffer size, audio bitrate, and encoder preset are selectable. This costs CPU and does not resize or change frame rate.

## Service setup

`deploy.sh` only creates a virtual environment and installs Python dependencies. It does not install, enable, restart, or deploy services.

The files under `systemd/` are templates. Adapt paths and service users if your installation differs, then install them as root. For the dashboard template, create `/etc/makasna-dashboard.env` containing at least:

```text
PORT=8080
SECRET_KEY=generated-value
```

For the MediaMTX template, create `/etc/mediamtx.env`:

```text
MEDIAMTX_CONFIG=/etc/mediamtx/mediamtx.yml
```

Copy the example MediaMTX configuration to that path. After reviewing all paths and permissions, copy units to `/etc/systemd/system/`, run `systemctl daemon-reload`, and explicitly enable/start only the services you intend to operate. The dashboard unit binds Gunicorn to localhost and uses one worker because relay process state is in memory; place an authenticated reverse proxy in front if remote access is required.

## Testing

```sh
python -m unittest discover -s tests -v
python -m py_compile app.py tests/test_app.py
```

Tests do not contact production systems. They mock relay startup and use temporary runtime data.

## Security

- Never commit `.env`, `forwards.json`, logs, keys, certificates, stream keys, or destination URLs containing credentials.
- Treat relay destinations and logs as sensitive: FFmpeg command lines may contain complete source or destination URLs.
- Keep the dashboard and MediaMTX Control API private unless access controls are added externally.
- Review anonymous MediaMTX publish/read permissions and use authentication or network filtering for untrusted networks.
- Run both services as dedicated, unprivileged users and limit writable directories.
- Rotate any credential that was ever copied into source control or shared logs.

## License

MIT. See [LICENSE](LICENSE).
