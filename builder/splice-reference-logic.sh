#!/usr/bin/env bash
# Replace built sourcemod.logic.so with the rom4s reference when in-tree logic still
# exports CXX11 ABI symbols (srcds hang). Core/mm/jit/extensions stay host-built.
set -euo pipefail

ARTIFACT="${1:?package tarball required}"
REF_URL="${REFERENCE_SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
SPLICE_REFERENCE_LOGIC="${SPLICE_REFERENCE_LOGIC:-auto}"

logic_needs_splice() {
  local tarball="$1"
  local tmp logic needed cxx11
  tmp="$(mktemp -d)"
  tar -xzf "${tarball}" -C "${tmp}" addons/sourcemod/bin/sourcemod.logic.so
  logic="${tmp}/addons/sourcemod/bin/sourcemod.logic.so"
  needed="$(readelf -d "${logic}" 2>/dev/null | awk '/\(NEEDED\)/ {print $NF}' | tr -d '[]' || true)"
  cxx11="$(nm -D "${logic}" 2>/dev/null | grep -c '__cxx11' || true)"
  rm -rf "${tmp}"
  if [[ "${cxx11:-0}" -gt 0 ]]; then
    echo "==> Built logic.so exports ${cxx11} __cxx11 symbols" >&2
    return 0
  fi
  if printf '%s\n' "${needed}" | grep -qx 'libstdc++.so.6'; then
    echo "==> Built logic.so DT_NEEDED libstdc++.so.6 (rom4s embeds static libstdc++)" >&2
    return 0
  fi
  echo "==> Built logic.so matches rom4s link profile; keeping in-tree logic" >&2
  return 1
}

should_splice() {
  case "${SPLICE_REFERENCE_LOGIC}" in
    0|false|no|off) return 1 ;;
    1|yes|true|on) return 0 ;;
    auto|*) logic_needs_splice "${ARTIFACT}" ;;
  esac
}

if ! should_splice; then
  exit 0
fi

echo "==> Splicing rom4s reference sourcemod.logic.so" >&2

tmp_pkg="$(mktemp -d)"
tmp_ref="$(mktemp -d)"
ref_tgz="${tmp_ref}/reference-sm.tar.gz"
trap 'rm -rf "${tmp_pkg}" "${tmp_ref}"' EXIT

tar -xzf "${ARTIFACT}" -C "${tmp_pkg}"
curl -fsSL -o "${ref_tgz}" "${REF_URL}"
tar -xzf "${ref_tgz}" -C "${tmp_ref}" \
  addons/sourcemod/bin/sourcemod.logic.so \
  addons/sourcemod/extensions/bintools.ext.so \
  addons/sourcemod/extensions/sdktools.ext.1.ep1.so \
  addons/sourcemod/extensions/sdktools.ext.2.ep1.so
cp -f "${tmp_ref}/addons/sourcemod/bin/sourcemod.logic.so" \
  "${tmp_pkg}/addons/sourcemod/bin/sourcemod.logic.so"
for rel in \
  addons/sourcemod/extensions/bintools.ext.so \
  addons/sourcemod/extensions/sdktools.ext.1.ep1.so \
  addons/sourcemod/extensions/sdktools.ext.2.ep1.so; do
  if [[ -f "${tmp_ref}/${rel}" ]]; then
    cp -f "${tmp_ref}/${rel}" "${tmp_pkg}/${rel}"
  fi
done
strip --strip-unneeded "${tmp_pkg}/addons/sourcemod/bin/sourcemod.logic.so" 2>/dev/null || true
for rel in addons/sourcemod/extensions/bintools.ext.so \
  addons/sourcemod/extensions/sdktools.ext.1.ep1.so \
  addons/sourcemod/extensions/sdktools.ext.2.ep1.so; do
  [[ -f "${tmp_pkg}/${rel}" ]] && strip --strip-unneeded "${tmp_pkg}/${rel}" 2>/dev/null || true
done

rm -f "${ARTIFACT}"
tar -C "${tmp_pkg}" -czf "${ARTIFACT}" addons cfg
echo "==> Spliced rom4s reference sourcemod.logic.so into $(basename "${ARTIFACT}")" >&2
