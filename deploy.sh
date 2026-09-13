#!/bin/sh
set -eu

PROJECT_DIR=${PROJECT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
VENV_DIR=${VENV_DIR:-$PROJECT_DIR/.venv}
PYTHON=${PYTHON:-python3}

"$PYTHON" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install -r "$PROJECT_DIR/requirements.txt"

printf '%s\n' "Dependencies installed in $VENV_DIR."
printf '%s\n' "Copy and adapt systemd units manually if you want system services."
