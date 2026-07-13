#!/usr/bin/env bash
# Resolve python on Linux (python3) and Windows CI (python only).
set -euo pipefail

if [ -n "${PYTHON:-}" ]; then
  :
elif command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "python3/python not found on PATH" >&2
  exit 127
fi

export PYTHON
exec "$PYTHON" "$@"
