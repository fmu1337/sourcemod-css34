#!/usr/bin/env bash
# Compatibility entry point; builder/lines.json is the pin source.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$repo_root/builder/lines.py" check
