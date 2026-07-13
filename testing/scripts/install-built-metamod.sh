#!/usr/bin/env bash
# Install locally built Metamod:Source into SERVER_DIR/cstrike (replaces rom4s MM bin).
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILT_MM_PACKAGE="${BUILT_MM_PACKAGE:-${ROOT}/deps/mmsource-1.10/build/package}"
BUILT_MM_DIR="${BUILT_MM_DIR:-${BUILT_MM_PACKAGE}/addons/metamod}"

if [[ ! -f "${BUILT_MM_DIR}/bin/metamod.1.ep1.so" ]]; then
  echo "Built Metamod not found at ${BUILT_MM_DIR}/bin/metamod.1.ep1.so" >&2
  echo "Run builder/run/linux.sh or builder/build-metamod.sh first." >&2
  exit 1
fi

mkdir -p "${SERVER_DIR}/cstrike/addons/metamod/bin"
cp -f "${BUILT_MM_DIR}/bin/"* "${SERVER_DIR}/cstrike/addons/metamod/bin/"
chmod +x "${SERVER_DIR}/cstrike/addons/metamod/bin/"*.so 2>/dev/null || true

# EP1 css34: gameinfo path (same as rom4s 1.10.6 layout).
cat >"${SERVER_DIR}/cstrike/addons/metamod.vdf" <<'EOF'
"Plugin"
{
	"file"	"../cstrike/addons/metamod/bin/server"
}
EOF

# Optional support files from the AMBuild package tree.
for extra in metaplugins.ini README.txt; do
  if [[ -f "${BUILT_MM_DIR}/${extra}" ]]; then
    cp -f "${BUILT_MM_DIR}/${extra}" "${SERVER_DIR}/cstrike/addons/metamod/${extra}"
  fi
done

echo "Installed built Metamod from ${BUILT_MM_PACKAGE}"
ls -la "${SERVER_DIR}/cstrike/addons/metamod/bin/"
