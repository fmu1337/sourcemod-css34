#!/usr/bin/env bash
# Install Metamod:Source + SourceMod into SERVER_DIR/cstrike.
# SM_PACKAGE can be a local .tar.gz path or a URL.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"

MM_URL="${MM_URL:-https://bitbucket.org/rom4s/mmsdrop-1.10/downloads/mmsource-1.10.6-css34-linux.tar.gz}"
SM_PACKAGE="${SM_PACKAGE:-}"
SM_URL="${SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"

mkdir -p "${CACHE_DIR}" "${SERVER_DIR}/cstrike"

download() {
  local url="$1" out="$2"
  if [[ -f "${out}" && -s "${out}" ]]; then
    echo "Using cached $(basename "${out}")"
    return 0
  fi
  echo "Downloading ${url}"
  curl -fL --retry 5 --retry-delay 3 -o "${out}.partial" "${url}"
  mv "${out}.partial" "${out}"
}

MM_TGZ="${CACHE_DIR}/mmsource-1.10.6-css34-linux.tar.gz"
download "${MM_URL}" "${MM_TGZ}"
tar -xzf "${MM_TGZ}" -C "${SERVER_DIR}/cstrike"
echo "Installed Metamod:Source from ${MM_URL}"

if [[ -n "${SM_PACKAGE}" ]]; then
  if [[ ! -f "${SM_PACKAGE}" ]]; then
    echo "SM_PACKAGE not found: ${SM_PACKAGE}" >&2
    exit 1
  fi
  echo "Installing SourceMod from local package ${SM_PACKAGE}"
  tar -xzf "${SM_PACKAGE}" -C "${SERVER_DIR}/cstrike"
else
  SM_TGZ="${CACHE_DIR}/$(basename "${SM_URL}")"
  download "${SM_URL}" "${SM_TGZ}"
  echo "Installing SourceMod from ${SM_URL}"
  tar -xzf "${SM_TGZ}" -C "${SERVER_DIR}/cstrike"
fi

# Optional: keep rom4s reference logic with a host-built core (logic ABI still tracked).
if [[ "${OVERLAY_ROM4S_LOGIC:-}" == "1" && -n "${SM_PACKAGE:-}" ]]; then
  REF_URL="${REFERENCE_SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
  REF_TGZ="${CACHE_DIR}/$(basename "${REF_URL}")"
  download "${REF_URL}" "${REF_TGZ}"
  tmp_overlay="$(mktemp -d)"
  tar -xzf "${REF_TGZ}" -C "${tmp_overlay}" addons/sourcemod/bin/sourcemod.logic.so
  cp -f "${tmp_overlay}/addons/sourcemod/bin/sourcemod.logic.so" \
    "${SERVER_DIR}/cstrike/addons/sourcemod/bin/sourcemod.logic.so"
  rm -rf "${tmp_overlay}"
  echo "Overlaid rom4s sourcemod.logic.so (OVERLAY_ROM4S_LOGIC=1)"
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

# Disable SM auto-updater noise in CI
if [[ -f "${SERVER_DIR}/cstrike/addons/sourcemod/configs/core.cfg" ]]; then
  sed -i 's/"AutoUpdate"[[:space:]]*"yes"/"AutoUpdate"\t\t"no"/' \
    "${SERVER_DIR}/cstrike/addons/sourcemod/configs/core.cfg" || true
fi

echo "Addons installed under ${SERVER_DIR}/cstrike/addons"
ls -la "${SERVER_DIR}/cstrike/addons/metamod/bin" || true
ls -la "${SERVER_DIR}/cstrike/addons/sourcemod/bin" || true
