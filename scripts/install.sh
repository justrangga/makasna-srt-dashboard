#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/srv/makasna-dashboard}"
SERVICE_USER="${SERVICE_USER:-makasna}"
ENV_FILE="${ENV_FILE:-/etc/makasna-dashboard.env}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer as root: sudo bash scripts/install.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git python3 python3-venv python3-pip ffmpeg curl jq ca-certificates openssl

if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --home "${APP_DIR}" --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

if [[ ! -f "${APP_DIR}/app.py" ]]; then
  echo "Application source not found at ${APP_DIR}. Clone the repository there first." >&2
  exit 1
fi

python3 -m venv "${APP_DIR}/.venv"
"${APP_DIR}/.venv/bin/python" -m pip install --upgrade pip wheel
"${APP_DIR}/.venv/bin/python" -m pip install -r "${APP_DIR}/requirements.txt"
"${APP_DIR}/.venv/bin/python" -m compileall -q "${APP_DIR}/app.py"

install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${APP_DIR}"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${APP_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  install -m 600 -o root -g root "${APP_DIR}/.env.example" "${ENV_FILE}"
  SECRET=$(openssl rand -hex 32)
  sed -i "s/^SECRET_KEY=.*/SECRET_KEY=${SECRET}/" "${ENV_FILE}"
  sed -i "s/^DASHBOARD_PASS=.*/DASHBOARD_PASS=change-this-password/" "${ENV_FILE}"
  echo "Created ${ENV_FILE}. Change DASHBOARD_PASS before exposing the dashboard."
fi

install -m 644 "${APP_DIR}/systemd/makasna-dashboard.service" /etc/systemd/system/makasna-dashboard.service
systemctl daemon-reload
systemctl enable makasna-dashboard

if systemctl is-active --quiet mediamtx; then
  echo "MediaMTX is active. Checking its API..."
  curl --fail --silent http://127.0.0.1:9997/v3/paths/list >/dev/null || {
    echo "MediaMTX is running but its API check failed." >&2
    exit 1
  }
else
  echo "MediaMTX is not active. Install/configure it, then run: systemctl enable --now mediamtx"
fi

systemctl restart makasna-dashboard
systemctl --no-pager --full status makasna-dashboard
