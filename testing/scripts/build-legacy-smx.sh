#!/usr/bin/env bash
# Rebuild the prebuilt old-compiler plugins in testing/plugins/legacy-smx/.
#
# Botplay loads these .smx files as they are (install-botplay-plugins.sh); CI
# never runs this script. It downloads the pinned SourceMod releases (sha256
# checked), compiles each plugin of legacy-smx/plugins.tsv with that release's
# spcomp and includes, copies the sources next to the .smx and rewrites
# SHA256SUMS. spcomp 1.7 / 1.11 are 32-bit; they run in an i386 container
# (LEGACY_SMX_IMAGE), so Docker is required (sudo when not in the docker group).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ROOT}/testing/plugins/legacy-smx"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}/legacy-smx"
IMAGE="${LEGACY_SMX_IMAGE:-i386/debian:11}"
DOCKER="${DOCKER:-docker}"

# compiler dir | release tarball | sha256
COMPILERS=(
  "1.7.3-git5334|https://sm.alliedmods.net/smdrop/1.7/sourcemod-1.7.3-git5334-linux.tar.gz|1b661b251f716e745dd1c0b73717a4d7e384161d677d5d4c4d19efbbde0cf65f"
  "1.11.0-git6970|https://sm.alliedmods.net/smdrop/1.11/sourcemod-1.11.0-git6970-linux.tar.gz|75ebcd0e8aa7192b83ac2e21a645638261fb1bc6882ec12f8736ac6aca7c29a7"
)

mkdir -p "${CACHE_DIR}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

for entry in "${COMPILERS[@]}"; do
  IFS='|' read -r ver url sha <<<"${entry}"
  tarball="${CACHE_DIR}/$(basename "${url}")"
  if [[ ! -f "${tarball}" ]]; then
    curl -fsSL --retry 3 -o "${tarball}.tmp" "${url}"
    mv "${tarball}.tmp" "${tarball}"
  fi
  echo "${sha}  ${tarball}" | sha256sum -c - >/dev/null
  mkdir -p "${work}/${ver}"
  tar -xzf "${tarball}" -C "${work}/${ver}" addons/sourcemod/scripting
done

# Probe source is shared with the current-compiler build (testing/plugins).
for entry in "${COMPILERS[@]}"; do
  ver="${entry%%|*}"
  cp -f "${ROOT}/testing/plugins/css34_legacy_forward_probe.sp" \
    "${work}/${ver}/addons/sourcemod/scripting/"
done

rm -rf "${OUT:?}"/*/
jobs="${work}/jobs.txt"
: >"${jobs}"
while IFS=$'\t' read -r ver source installed_as; do
  [[ -z "${ver}" || "${ver}" == \#* ]] && continue
  echo "${ver} ${source} ${installed_as}" >>"${jobs}"
  scripting="${work}/${ver}/addons/sourcemod/scripting"
  mkdir -p "${OUT}/${ver}/src"
  cp -f "${scripting}/${source}.sp" "${OUT}/${ver}/src/"
  if [[ -d "${scripting}/${source}" ]]; then
    cp -rf "${scripting}/${source}" "${OUT}/${ver}/src/"
  fi
done <"${OUT}/plugins.tsv"

# shellcheck disable=SC2016
${DOCKER} run --rm --network none -v "${work}:/work" -v "${OUT}:/out" "${IMAGE}" bash -c '
  set -euo pipefail
  while read -r ver source installed_as; do
    s=/work/${ver}/addons/sourcemod/scripting
    echo "== spcomp ${ver}: ${source}.sp -> ${ver}/${installed_as}"
    (cd "${s}" && ./spcomp -i"${s}/include" -o"/out/${ver}/${installed_as}" "${source}.sp")
    test -s "/out/${ver}/${installed_as}"
    "${s}/spcomp" 2>&1 | head -n 1 >"/out/${ver}/SPCOMP_VERSION" || true
  done </work/jobs.txt
  chown -R '"$(id -u):$(id -g)"' /out
'

(cd "${OUT}" && find . -mindepth 2 -type f ! -name SPCOMP_VERSION -printf '%P\n' | LC_ALL=C sort \
  | xargs sha256sum >SHA256SUMS)
echo "Rebuilt ${OUT}:"
cat "${OUT}/SHA256SUMS"
