# Troubleshooting

## Dashboard service fails

```bash
sudo systemctl status makasna-dashboard --no-pager
sudo journalctl -u makasna-dashboard -b --no-pager
sudo systemctl cat makasna-dashboard
```

Check that `/etc/makasna-dashboard.env` exists, `SECRET_KEY` and `DASHBOARD_PASS` are set, and `/srv/makasna-dashboard/.venv/bin/gunicorn` exists.

## No ingest appears

```bash
curl -fsS http://127.0.0.1:9997/v3/srtconns/list | jq .
sudo journalctl -u mediamtx -n 100 --no-pager
sudo ss -lunp | grep ':8890'
```

Check the encoder mode, public IP, UDP firewall, Stream ID format (`publish:NAME`), and SRT latency.

## Route starts then exits

Inspect the dashboard log and verify that `ffmpeg` is installed and the input can be read. A destination can fail because of an invalid URL, codec/container incompatibility, occupied port, or firewall policy.

## SLS clients are absent

Verify the route feeding SLS is active, SLS is listening on UDP `12105`, and the SLS webhook is configured for the local dashboard endpoint. Check SLS and dashboard logs. Telemetry should be treated as stale when no active route exists.

## Port already in use

```bash
sudo ss -ltnup
sudo lsof -nP -iUDP:12105
```

Stop the conflicting service or choose a different dedicated port. Do not run two listeners on the same UDP socket.
