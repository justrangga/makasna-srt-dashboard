# Installation

This page is the short index for a clean Ubuntu installation. Follow the complete [INSTALL.md](../../INSTALL.md) in the repository; it is the canonical procedure.

## Order of operations

1. Prepare Ubuntu, DNS, storage, and firewall.
2. Install Python, FFmpeg, Git, and curl.
3. Install and validate MediaMTX with its API bound to `127.0.0.1:9997`.
4. Clone the repository into `/srv/makasna-dashboard`.
5. Create the Python virtual environment and install `requirements.txt`.
6. Create `/etc/makasna-dashboard.env` with a generated `SECRET_KEY` and unique `DASHBOARD_PASS`.
7. Install `systemd/makasna-dashboard.service`.
8. Validate `/login`, MediaMTX API, and `systemctl status`.
9. Add only the UDP/TCP ports used by the deployment to the firewall.
10. Configure SLS separately if the TV Pool is required.

## Production rule

Do not copy `.env`, service-account files, SSH keys, or route state from another server. Use placeholders in documentation and generate new secrets for every installation.
