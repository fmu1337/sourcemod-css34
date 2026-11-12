#!/usr/bin/env bash
# Install Metamod:Source + SourceMod into SERVER_DIR/cstrike.
# SM_PACKAGE / MM_PACKAGE are local .tar.gz paths (or USE_BUILT_MM=1 for a Metamod build tree).
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

MM_PACKAGE="${MM_PACKAGE:-}"
BUILT_MM_DIR="${BUILT_MM_DIR:-}"
USE_BUILT_MM="${USE_BUILT_MM:-0}"
SM_PACKAGE="${SM_PACKAGE:-}"

mkdir -p "${SERVER_DIR}/cstrike"

install_metamod() {
  rm -rf "${SERVER_DIR}/cstrike/addons/metamod" "${SERVER_DIR}/cstrike/addons/metamod.vdf"
  if [[ "${USE_BUILT_MM}" == "1" || -n "${BUILT_MM_DIR}" || -n "${BUILT_MM_PACKAGE:-}" ]]; then
    BUILT_MM_PACKAGE="${BUILT_MM_PACKAGE:-${ROOT}/deps/mmsource-1.10/build/package}" \
      BUILT_MM_DIR="${BUILT_MM_DIR:-}" \
      SERVER_DIR="${SERVER_DIR}" \
      bash "${ROOT}/testing/scripts/install-built-metamod.sh"
    echo "Installed Metamod:Source from local build (${BUILT_MM_PACKAGE})"
  elif [[ -n "${MM_PACKAGE}" ]]; then
    if [[ ! -f "${MM_PACKAGE}" ]]; then
      echo "MM_PACKAGE not found: ${MM_PACKAGE}" >&2
      exit 1
    fi
    echo "Installing Metamod:Source from local package ${MM_PACKAGE}"
    tar -xzf "${MM_PACKAGE}" -C "${SERVER_DIR}/cstrike"
  else
    echo "MM_PACKAGE is required (or USE_BUILT_MM=1 / BUILT_MM_PACKAGE)" >&2
    exit 1
  fi
}

install_metamod

if [[ -z "${SM_PACKAGE}" ]]; then
  echo "SM_PACKAGE is required" >&2
  exit 1
fi
if [[ ! -f "${SM_PACKAGE}" ]]; then
  echo "SM_PACKAGE not found: ${SM_PACKAGE}" >&2
  exit 1
fi
echo "Installing SourceMod from local package ${SM_PACKAGE}"
tar -xzf "${SM_PACKAGE}" -C "${SERVER_DIR}/cstrike"

# PLAIN_TAR_INSTALL=1: installer contract — `tar -xzf mm; tar -xzf sm` and
# nothing else. Skip every fixup below so smoke proves the packages are
# self-sufficient (sourcemod.vdf, core.cfg, GeoIP DB all come from the tarballs).
if [[ "${PLAIN_TAR_INSTALL:-0}" == "1" ]]; then
  echo "PLAIN_TAR_INSTALL=1: no post-extract fixups"
  ls -la "${SERVER_DIR}/cstrike/addons/metamod" "${SERVER_DIR}/cstrike/addons/sourcemod/bin" || true
  exit 0
fi

mkdir -p "${SERVER_DIR}/cstrike/addons/metamod"
if [[ ! -f "${SERVER_DIR}/cstrike/addons/metamod/sourcemod.vdf" ]]; then
  cat >"${SERVER_DIR}/cstrike/addons/metamod/sourcemod.vdf" <<'EOF'
"Metamod Plugin"
{
	"alias"		"sourcemod"
	"file"		"addons/sourcemod/bin/sourcemod_mm"
}
EOF
fi

echo "Addons installed under ${SERVER_DIR}/cstrike/addons"
ls -la "${SERVER_DIR}/cstrike/addons/metamod/bin" || true
ls -la "${SERVER_DIR}/cstrike/addons/sourcemod/bin" || true
