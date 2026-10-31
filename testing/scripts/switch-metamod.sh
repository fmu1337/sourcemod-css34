#!/usr/bin/env bash
# Switch the Metamod build of an installed server the way an operator would:
# remove addons/metamod/bin/{server*,metamod.*}, extract the other Metamod
# package into cstrike/, keep metaplugins.ini. SourceMod is left untouched.
#
# Usage: SERVER_DIR=<srcds root> switch-metamod.sh <mmsource-*-css34-linux.tar.gz>
#
# The script adds a comment line to metaplugins.ini before switching and fails
# unless that line, sourcemod.vdf and exactly one Metamod binary survive.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
package="${1:?Metamod package path required}"
mm="${SERVER_DIR}/cstrike/addons/metamod"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${package}" ]] || fail "Metamod package not found: ${package}"
[[ -d "${mm}/bin" ]] || fail "no installed Metamod under ${mm}"
[[ -f "${mm}/sourcemod.vdf" ]] || fail "SourceMod is not installed (${mm}/sourcemod.vdf missing)"

target="$(tar -tzf "${package}" | grep -Eo 'addons/metamod/bin/metamod\.[12]\.ep1\.so' | head -n1 || true)"
[[ -n "${target}" ]] || fail "${package} ships no addons/metamod/bin/metamod.{1,2}.ep1.so"
target="$(basename "${target}")"

marker="; css34 switch-metamod: operator entry kept $(date -u +%s)"
printf '%s\n' "${marker}" >>"${mm}/metaplugins.ini"
backup="$(mktemp)"
trap 'rm -f "${backup}"' EXIT
cp -p "${mm}/metaplugins.ini" "${backup}"
vdf_before="$(sha256sum "${mm}/sourcemod.vdf" | cut -d' ' -f1)"

echo "==> Switching Metamod to $(basename "${package}") (${target})"
rm -f "${mm}"/bin/server* "${mm}"/bin/metamod.*
tar -xzf "${package}" -C "${SERVER_DIR}/cstrike"
cp -p "${backup}" "${mm}/metaplugins.ini"

grep -Fxq "${marker}" "${mm}/metaplugins.ini" || fail "metaplugins.ini was not kept"
[[ "$(sha256sum "${mm}/sourcemod.vdf" | cut -d' ' -f1)" == "${vdf_before}" ]] \
  || fail "sourcemod.vdf changed during the Metamod switch"
mapfile -t binaries < <(find "${mm}/bin" -maxdepth 1 -name 'metamod.*.ep1.so' -printf '%f\n' | sort)
[[ "${#binaries[@]}" -eq 1 && "${binaries[0]}" == "${target}" ]] \
  || fail "expected only ${target} after the switch, found: ${binaries[*]:-none}"
for loader in server.so server_i486.so; do
  [[ -f "${mm}/bin/${loader}" ]] || fail "missing ${mm}/bin/${loader} after the switch"
done
echo "OK: Metamod switched to ${target}; metaplugins.ini and sourcemod.vdf kept"
