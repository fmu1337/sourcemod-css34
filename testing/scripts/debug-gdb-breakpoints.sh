#!/usr/bin/env bash
# Timed gdb breakpoint probe (wrapper around debug-smoke-hang.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "${ROOT}/testing/scripts/debug-smoke-hang.sh" "$@"
