#!/usr/bin/env bash
# Apply the debian9-style valve.rc rewrite.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

mkdir -p "${SERVER_DIR}/cstrike/cfg"
cp -f "${ROOT}/testing/configs/valve.rc" "${SERVER_DIR}/cstrike/cfg/valve.rc"
echo "Applied valve.rc fix"
