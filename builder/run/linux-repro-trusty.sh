#!/usr/bin/env bash
set -euo pipefail

# In-container entrypoint: Ubuntu 14.04 native clang-9 (no jammy wrappers).
export CLANG9_NATIVE=1
export SKIP_APT_INSTALL=1
export PATH="/opt/python3.6/bin:${PATH:-/usr/bin:/bin}"
export WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

exec "$WDIR/builder/run/linux-repro.sh"
