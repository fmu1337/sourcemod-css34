#!/usr/bin/env bash
# Write css34-package.json (self-describing package manifest) for installers.
#
#   write-package-manifest.sh <out.json> <metamod_binary>
#
# Reads from env (set by builder/resolve-version.sh / builder/run/linux.sh):
#   CSS34_LINE, SOURCEMOD_DIR, SOURCEMOD_GIT_REV, SOURCEMOD_COMMIT,
#   SOURCEMOD_BUILD_COMMIT, MMS_DIR, MMS_GIT_REV, MMS_COMMIT
#
# extension_api / extension_api_min come from SourceMod public/IExtensionSys.h.
# SM 1.11/1.12 define no _MIN (any API <= VERSION loads), so min is 1 there.
set -euo pipefail

OUT="${1:?output json path required}"
METAMOD_BINARY="${2:?metamod binary name required (metamod.1.ep1 / metamod.2.ep1)}"

SOURCEMOD_DIR="${SOURCEMOD_DIR:?SOURCEMOD_DIR required}"
MMS_DIR="${MMS_DIR:?MMS_DIR required}"

sm_product="$(tr -d '\r\n' < "$SOURCEMOD_DIR/product.version")"
sm_rev="${SOURCEMOD_GIT_REV:?SOURCEMOD_GIT_REV required}"
sm_commit="${SOURCEMOD_BUILD_COMMIT:-${SOURCEMOD_COMMIT:-}}"
if [[ -z "$sm_commit" ]]; then
  sm_commit="$(git -C "$SOURCEMOD_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
fi
mm_product="$(tr -d '\r\n' < "$MMS_DIR/product.version")"
mm_rev="${MMS_GIT_REV:?MMS_GIT_REV required}"
mm_commit="${MMS_COMMIT:-$(git -C "$MMS_DIR" rev-parse HEAD 2>/dev/null || echo unknown)}"

ext_h="$SOURCEMOD_DIR/public/IExtensionSys.h"
ext_api="$(sed -nE 's/^[[:space:]]*#define[[:space:]]+SMINTERFACE_EXTENSIONAPI_VERSION[[:space:]]+([0-9]+).*/\1/p' "$ext_h" | head -n1)"
ext_api_min="$(sed -nE 's/^[[:space:]]*#define[[:space:]]+SMINTERFACE_EXTENSIONAPI_VERSION_MIN[[:space:]]+([0-9]+).*/\1/p' "$ext_h" | head -n1)"
if [[ -z "$ext_api" ]]; then
  echo "Cannot read SMINTERFACE_EXTENSIONAPI_VERSION from $ext_h" >&2
  exit 1
fi
ext_api_min="${ext_api_min:-1}"

# "1.12.0-dev" → "1.12.0"; SM version string matches `sm version` (1.13.0.7472).
sm_base="${sm_product%%-*}"
mm_base="${mm_product%%-*}"
build_date="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
pack_commit="$(git -C "${WDIR:-$SOURCEMOD_DIR/..}" rev-parse HEAD 2>/dev/null || echo unknown)"

# Windows packages record toolset/SDK; Linux packages record min_glibc from GLIBC_FLOOR.
toolchain_fields=""
if [[ "${BUILD_PLATFORM:-}" == "windows" ]]; then
  msvc_toolset="${MSVC_TOOLSET:?MSVC_TOOLSET required for Windows packages}"
  windows_sdk="${WINDOWS_SDK:?WINDOWS_SDK required for Windows packages}"
  if [[ ! "$msvc_toolset" =~ ^[0-9]+(\.[0-9]+)+$ || ! "$windows_sdk" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "Bad MSVC_TOOLSET/WINDOWS_SDK (expected dotted versions)" >&2
    exit 1
  fi
  toolchain_fields=$(printf '  "msvc_toolset": "%s",\n  "windows_sdk": "%s",\n' \
    "$msvc_toolset" "$windows_sdk")
else
  glibc_floor="${GLIBC_FLOOR:-2.17}"
  toolchain_fields=$(printf '  "min_glibc": "%s",\n' "$glibc_floor")
fi

mkdir -p "$(dirname "$OUT")"
cat >"$OUT" <<EOF
{
  "line": "${CSS34_LINE:-custom}",
  "sm_version": "${sm_base}.${sm_rev}",
  "sm_product_version": "${sm_product}",
  "sm_commit": "${sm_commit}",
  "mm_version": "${mm_base}-git${mm_rev}",
  "mm_product_version": "${mm_product}",
  "mm_commit": "${mm_commit}",
  "extension_api": ${ext_api},
  "extension_api_min": ${ext_api_min},
  "metamod_binary": "${METAMOD_BINARY}",
${toolchain_fields}  "css34_pack_commit": "${pack_commit}",
  "build_date": "${build_date}"
}
EOF
echo "==> Wrote $OUT" >&2
