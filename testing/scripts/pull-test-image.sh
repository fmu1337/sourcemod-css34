#!/usr/bin/env bash
# Pull a smoke/botplay container image and print the reference to run.
#
#   IMAGE="$(testing/scripts/pull-test-image.sh "$IMAGE" "$BASE_IMAGE")"
#
# IMAGE is a matrix row's `image` (the prebuilt ghcr.io test image when
# builder/lines.json has a current one, else the pinned base image), BASE_IMAGE
# its `base_image`. When the prebuilt image cannot be pulled, the base image is
# used and install-deps.sh installs the runtime as before, so a missing or
# private package never fails a job. GHCR_TOKEN (optional): log in to ghcr.io
# first (GITHUB_TOKEN with packages: read). Each pull is tried 3 times.
set -euo pipefail

image="${1:?usage: pull-test-image.sh IMAGE [BASE_IMAGE]}"
base="${2:-}"

if [[ "${image}" == ghcr.io/* && -n "${GHCR_TOKEN:-}" ]]; then
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR:-css34}" --password-stdin >/dev/null 2>&1 \
    || echo "::warning::docker login ghcr.io failed; pulling ${image} anonymously" >&2
fi

pull() {
  local attempt
  for attempt in 1 2 3; do
    if docker pull --platform linux/amd64 "$1" >&2; then
      return 0
    fi
    [[ "${attempt}" -lt 3 ]] && sleep $((attempt * ${CSS34_PULL_RETRY_SECS:-5}))
  done
  return 1
}

if pull "${image}"; then
  printf '%s\n' "${image}"
  exit 0
fi
if [[ -n "${base}" && "${base}" != "${image}" ]]; then
  echo "::warning::cannot pull prebuilt ${image}; falling back to ${base} (install-deps.sh installs at run time)" >&2
  pull "${base}"
  printf '%s\n' "${base}"
  exit 0
fi
echo "FAIL: cannot pull ${image}" >&2
exit 1
