#!/bin/sh
# Runs spoof.py with the Python that has pymobiledevice3 (installed via pipx).
PY="$(pipx environment --value PIPX_LOCAL_VENVS)/pymobiledevice3/bin/python"
[ -x "$PY" ] || { echo "Install it first:  pipx install pymobiledevice3" >&2; exit 1; }
exec "$PY" "$(dirname "$0")/spoof.py" "$@"
