#!/usr/bin/env bash
# Replace built sourcemod.logic.so with the rom4s reference when in-tree logic still
# exports CXX11 ABI symbols (srcds hang). Core/mm/jit/extensions stay host-built.
set -euo pipefail

ARTIFACT="${1:?package tarball required}"
REF_URL="${REFERENCE_SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
SPLICE_REFERENCE_LOGIC="${SPLICE_REFERENCE_LOGIC:-auto}"

logic_cxx11_count() {
  local tarball="$1"
  local tmp logic count
  tmp="$(mktemp -d)"
  tar -xzf "${tarball}" -C "${tmp}" addons/sourcemod/bin/sourcemod.logic.so
  logic="${tmp}/addons/sourcemod/bin/sourcemod.logic.so"
  count="$(nm -D "${logic}" 2>/dev/null | grep -c '__cxx11' || true)"
  rm -rf "${tmp}"
  echo "${count:-0}"
}

should_splice() {
  case "${SPLICE_REFERENCE_LOGIC}" in
    0|false|no|off) return 1 ;;
    1|yes|true|on) return 0 ;;
    auto|*)
      local n
      n="$(logic_cxx11_count "${ARTIFACT}")"
      if [[ "${n}" -gt 0 ]]; then
        echo "==> Built logic.so exports ${n} __cxx11 symbols; splicing rom4s reference logic" >&2
        return 0
      fi
      echo "==> Built logic.so has no __cxx11 exports; keeping in-tree logic" >&2
      return 1
      ;;
  esac
}

if ! should_splice; then
  exit 0
fi

tmp_pkg="$(mktemp -d)"
tmp_ref="$(mktemp -d)"
ref_tgz="${tmp_ref}/reference-sm.tar.gz"
trap 'rm -rf "${tmp_pkg}" "${tmp_ref}"' EXIT

tar -xzf "${ARTIFACT}" -C "${tmp_pkg}"
curl -fsSL -o "${ref_tgz}" "${REF_URL}"
tar -xzf "${ref_tgz}" -C "${tmp_ref}" addons/sourcemod/bin/sourcemod.logic.so
cp -f "${tmp_ref}/addons/sourcemod/bin/sourcemod.logic.so" \
  "${tmp_pkg}/addons/sourcemod/bin/sourcemod.logic.so"
strip --strip-unneeded "${tmp_pkg}/addons/sourcemod/bin/sourcemod.logic.so" 2>/dev/null || true

rm -f "${ARTIFACT}"
tar -C "${tmp_pkg}" -czf "${ARTIFACT}" addons cfg
echo "==> Spliced rom4s reference sourcemod.logic.so into $(basename "${ARTIFACT}")" >&2
