# Uninstall and Rollback

## Stop and remove the service

```bash
sudo systemctl disable --now makasna-dashboard
sudo rm -f /etc/systemd/system/makasna-dashboard.service
sudo systemctl daemon-reload
```

Remove the application only after backing up route state and environment:

```bash
sudo tar -C /srv -czf /root/makasna-dashboard-final-backup.tgz makasna-dashboard
sudo rm -rf /srv/makasna-dashboard
sudo rm -f /etc/makasna-dashboard.env
```

Do not remove MediaMTX if other services use it. Remove firewall rules only after confirming no remaining workload needs the ports.

## Roll back an application update

```bash
sudo systemctl stop makasna-dashboard
cd /srv/makasna-dashboard
git log --oneline -5
git checkout <KNOWN_GOOD_COMMIT>
.venv/bin/pip install -r requirements.txt
sudo systemctl start makasna-dashboard
sudo journalctl -u makasna-dashboard -n 100 --no-pager
```

Restore `routes.json` and other state files from the backup only when the backup belongs to the same deployment and has been verified.
