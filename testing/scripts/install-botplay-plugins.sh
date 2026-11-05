#!/usr/bin/env bash
# Compile and install botplay helper plugins into SERVER_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
SM_PLUGINS_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/plugins"
BOTPLAY_OUT="${BOTPLAY_OUT:-${ROOT}/.ci-artifacts/botplay-plugins}"

export SERVER_DIR
"${ROOT}/testing/scripts/compile-botplay-plugins.sh"

mkdir -p "${SM_PLUGINS_DIR}"
cp -f "${BOTPLAY_OUT}"/*.smx "${SM_PLUGINS_DIR}/"

# Probe gamedata (v34 offsets / symbols the stock gamedata doesn't carry)
SM_GAMEDATA_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/gamedata"
shopt -s nullglob
for gd in "${ROOT}"/testing/plugins/gamedata/*.txt; do
  mkdir -p "${SM_GAMEDATA_DIR}"
  cp -f "${gd}" "${SM_GAMEDATA_DIR}/"
done
shopt -u nullglob

echo "Installed botplay plugins:"
ls -la "${SM_PLUGINS_DIR}"/css34_*.smx

# Prebuilt plugins from old compilers (testing/plugins/legacy-smx/): stock
# plugins replace the package's copies, so the server runs them with the new
# core the way production servers do; the forward probes are extra plugins.
if [[ "${INSTALL_LEGACY_SMX:-1}" == "1" ]]; then
  LEGACY_DIR="${ROOT}/testing/plugins/legacy-smx"
  (cd "${LEGACY_DIR}" && sha256sum --quiet -c SHA256SUMS)
  # The probe .smx must come from the probe source in testing/plugins.
  for src in "${LEGACY_DIR}"/*/src/css34_legacy_forward_probe.sp; do
    if ! cmp -s "${src}" "${ROOT}/testing/plugins/css34_legacy_forward_probe.sp"; then
      echo "FAIL: ${src#"${ROOT}/"} differs from testing/plugins/css34_legacy_forward_probe.sp;" \
        "run testing/scripts/build-legacy-smx.sh" >&2
      exit 1
    fi
  done
  while IFS=$'\t' read -r ver _source installed_as; do
    [[ -z "${ver}" || "${ver}" == \#* ]] && continue
    cp -f "${LEGACY_DIR}/${ver}/${installed_as}" "${SM_PLUGINS_DIR}/${installed_as}"
    echo "Installed legacy ${installed_as} (spcomp ${ver})"
  done <"${LEGACY_DIR}/plugins.tsv"
fi
