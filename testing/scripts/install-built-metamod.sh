#!/usr/bin/env bash
# Install locally built Metamod:Source into SERVER_DIR/cstrike (replaces rom4s MM bin).
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILT_MM_DIR="${BUILT_MM_DIR:-${ROOT}/deps/mmsource-1.10/build/package/addons/metamod}"

if [[ ! -f "${BUILT_MM_DIR}/bin/metamod.1.ep1.so" ]]; then
  echo "Built Metamod not found at ${BUILT_MM_DIR}/bin/metamod.1.ep1.so" >&2
  echo "Build with: cd deps/mmsource-1.10/build && configure.py ... && ambuild" >&2
  exit 1
fi

mkdir -p "${SERVER_DIR}/cstrike/addons/metamod/bin"
cp -f "${BUILT_MM_DIR}/bin/"* "${SERVER_DIR}/cstrike/addons/metamod/bin/"
chmod +x "${SERVER_DIR}/cstrike/addons/metamod/bin/"*.so 2>/dev/null || true

# EP1 css34: use metamod.1.ep1 loader chain (same as rom4s 1.10.6 layout).
if [[ ! -f "${SERVER_DIR}/cstrike/addons/metamod.vdf" ]]; then
  cat >"${SERVER_DIR}/cstrike/addons/metamod.vdf" <<'EOF'
"Plugin"
{
	"file"	"../cstrike/addons/metamod/bin/server"
}
EOF
fi

echo "Installed built Metamod from ${BUILT_MM_DIR}"
ls -la "${SERVER_DIR}/cstrike/addons/metamod/bin/"
