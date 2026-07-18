#!/usr/bin/env bash
# Apply CS:S v34 BufferFix (memcpy→memmove) by rewriting ELF relocations in-place.
# Replaces the old rar download from the `bufferfix` branch.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PATCHER="${ROOT}/testing/scripts/patch-srcds-bufferfix.py"

if [[ ! -f "${PATCHER}" ]]; then
  echo "Missing ${PATCHER}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to patch srcds binaries" >&2
  exit 1
fi

EXTRA=()
if [[ "${SRCDS_PATCH_STEAMCLIENT:-1}" != "1" ]]; then
  EXTRA+=(--no-steamclient)
fi

python3 "${PATCHER}" "${SERVER_DIR}" "${EXTRA[@]}"
echo "Applied srcds bufferfix patch (engine/server/steamclient ELF rewrite)"
