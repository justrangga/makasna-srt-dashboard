# Operations

## Daily checks

```bash
sudo systemctl status mediamtx makasna-dashboard --no-pager
sudo ss -lunp | grep -E ':(8890|12105|12106|12107)'
curl -fsS http://127.0.0.1:9997/v3/paths/list | jq .
curl -fsS http://127.0.0.1:8080/login >/dev/null
```

## Route lifecycle

Start a route only after its input is visible in the ingest monitor. Confirm the destination port and receiver mode, then use **Start**. When stopping, use the dashboard **Stop** action and confirm that the route process exits and Active Listeners reflects the remaining clients.

## Backup

Back up `routes.json`, `events.json`, and `/etc/makasna-dashboard.env`. Never put those files in a public issue, commit, wiki page, or chat message.

## Updates

Use `git pull --ff-only`, stop the service, install dependencies, run `make check` and the smoke tests, then restart and inspect `journalctl`. Keep a rollback archive before changing the application.
