#!/usr/bin/env bash
# Installer-contract smoke for published release assets.
#
# Downloads SM + MM by public URL (exactly what fmu1337/v34_server_base does),
# verifies SHA256SUMS, runs the static package checks, installs with a plain
# `tar -xzf mm -C cstrike && tar -xzf sm -C cstrike` (PLAIN_TAR_INSTALL=1) and
# boots srcds in debian:11 via smoke-test.sh.
#
# Env:
#   BASE_URL      https://github.com/<repo>/releases/download/<tag>   (required)
#   SM_ASSET      SourceMod asset name                                (required)
#   MM_ASSET      Metamod asset name                                  (required)
#   SUMS_ASSET    checksum file name (default SHA256SUMS; "" to skip)
#   SERVER_TREE   packed server tree (default server-art/css34-server.tar.gz)
#   OUT_DIR       download dir (default .ci-release-smoke)
#   IMAGE         container image (default debian:11)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_URL="${BASE_URL:?BASE_URL is required}"
SM_ASSET="${SM_ASSET:?SM_ASSET is required}"
MM_ASSET="${MM_ASSET:?MM_ASSET is required}"
SUMS_ASSET="${SUMS_ASSET-SHA256SUMS}"
SERVER_TREE="${SERVER_TREE:-server-art/css34-server.tar.gz}"
OUT_DIR="${OUT_DIR:-.ci-release-smoke}"
IMAGE="${IMAGE:-debian:11}"

cd "${ROOT}"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

fetch() {
  # Fresh release assets can take a moment to appear on the CDN.
  curl -fL --retry 8 --retry-delay 5 --retry-all-errors -o "${OUT_DIR}/$1" "${BASE_URL}/$1"
}

echo "==> Downloading ${BASE_URL}/{${SM_ASSET},${MM_ASSET}}"
fetch "${SM_ASSET}"
fetch "${MM_ASSET}"
if [[ -n "${SUMS_ASSET}" ]]; then
  fetch "${SUMS_ASSET}"
  (cd "${OUT_DIR}" && grep -E "  (${SM_ASSET}|${MM_ASSET})\$" "${SUMS_ASSET}" | sha256sum -c -)
  for a in "${SM_ASSET}" "${MM_ASSET}"; do
    grep -Eq "  ${a}\$" "${OUT_DIR}/${SUMS_ASSET}" || { echo "FAIL: ${a} not in ${SUMS_ASSET}" >&2; exit 1; }
  done
fi

SM_PACKAGE="${OUT_DIR}/${SM_ASSET}" bash testing/scripts/check-package.sh
MM_PACKAGE="${OUT_DIR}/${MM_ASSET}" bash testing/scripts/check-metamod-package.sh

# Expected versions come from the package's own manifest (what `sm version` /
# `meta version` must report).
manifest="$(tar -xzOf "${OUT_DIR}/${SM_ASSET}" addons/sourcemod/css34-package.json)"
jget() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "${manifest}" "$1"; }
SM_VERSION_EXPECT="$(jget sm_version)"
SM_COMMIT_EXPECT="$(jget sm_commit)"
MM_COMMIT_EXPECT="$(jget mm_commit)"
mm_version="$(jget mm_version)"
MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-${mm_version%%-*}}"
export SM_VERSION_EXPECT SM_COMMIT_EXPECT MM_COMMIT_EXPECT MM_VERSION_EXPECT
echo "==> Expect SM ${SM_VERSION_EXPECT} (${SM_COMMIT_EXPECT:0:9}) MM ${MM_VERSION_EXPECT} (${MM_COMMIT_EXPECT:0:9})"

docker run --rm --platform linux/amd64 \
  -v "${ROOT}:/workspace" \
  -e SERVER_DIR=/workspace/.ci-server \
  -e CACHE_DIR=/workspace/.ci-cache \
  -e SM_PACKAGE="/workspace/${OUT_DIR}/${SM_ASSET}" \
  -e MM_PACKAGE="/workspace/${OUT_DIR}/${MM_ASSET}" \
  -e PLAIN_TAR_INSTALL=1 \
  -e MM_VERSION_EXPECT -e SM_VERSION_EXPECT -e MM_COMMIT_EXPECT -e SM_COMMIT_EXPECT \
  -e TIMEOUT_SECS=120 \
  -e SMOKE_CONDEBUG=1 \
  -e SMOKE_VERBOSE=1 \
  -w /workspace \
  "${IMAGE}" \
  bash -lc '
    set -euo pipefail
    rm -rf /workspace/.ci-server
    mkdir -p /workspace/.ci-server /workspace/.ci-cache
    tar -xzf /workspace/'"${SERVER_TREE}"' -C /workspace/.ci-server
    testing/scripts/install-deps.sh
    testing/scripts/install-addons.sh
    testing/scripts/smoke-test.sh
  '
echo "==> Release smoke PASSED for ${BASE_URL}"
