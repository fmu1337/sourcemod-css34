#!/usr/bin/env bash
# bintools is not built in-tree (SourceHook v4); ship rom4s reference extension.
set -euo pipefail

ARTIFACT="${1:?package tarball required}"
REF_URL="${REFERENCE_SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
SPLICE_REFERENCE_EXTRAS="${SPLICE_REFERENCE_EXTRAS:-auto}"

needs_bintools_splice() {
  local tarball="$1"
  local tmp
  tmp="$(mktemp -d)"
  if tar -xzf "${tarball}" -C "${tmp}" addons/sourcemod/extensions/bintools.ext.so 2>/dev/null; then
    rm -rf "${tmp}"
    return 1
  fi
  rm -rf "${tmp}"
  return 0
}

case "${SPLICE_REFERENCE_EXTRAS}" in
  0|false|no|off) exit 0 ;;
  1|yes|true|on) ;;
  auto|*)
    if ! needs_bintools_splice "${ARTIFACT}"; then
      echo "==> Package already has bintools.ext.so" >&2
      exit 0
    fi
    ;;
esac

echo "==> Splicing rom4s reference bintools.ext.so" >&2
tmp_pkg="$(mktemp -d)"
tmp_ref="$(mktemp -d)"
ref_tgz="${tmp_ref}/reference-sm.tar.gz"
trap 'rm -rf "${tmp_pkg}" "${tmp_ref}"' EXIT

tar -xzf "${ARTIFACT}" -C "${tmp_pkg}"
curl -fsSL -o "${ref_tgz}" "${REF_URL}"
tar -xzf "${ref_tgz}" -C "${tmp_ref}" addons/sourcemod/extensions/bintools.ext.so
cp -f "${tmp_ref}/addons/sourcemod/extensions/bintools.ext.so" \
  "${tmp_pkg}/addons/sourcemod/extensions/bintools.ext.so"
strip --strip-unneeded "${tmp_pkg}/addons/sourcemod/extensions/bintools.ext.so" 2>/dev/null || true

rm -f "${ARTIFACT}"
tar -C "${tmp_pkg}" -czf "${ARTIFACT}" addons cfg
