#!/usr/bin/env bash
# Sourced by fetch-server.sh and wine-smoke-test.sh: download a CS:S v34 server
# zip and verify it against the sha256 pinned here, cached copies included.
# The zips come from a third-party bitbucket download page and run in
# containers that see the repository, so an unpinned zip is never unpacked.

srcds_zip_sha256() {
  case "$1" in
    srcds_css34_4044.zip) echo 669d3a6c3a65467207ed0e88a4084e1dc5e526eb1cbfcf578627a51d8a7d979d ;;
    srcds_css34_l_a.zip) echo a5362cf0fb6f4acb3096ba3ed03b2b03f114bf8faf365b0d6aa3bdc71d091366 ;;
    srcds_css34_l_eSTEAMATiON.zip) echo 7f284b321d093cacee86937965664000fe59d093692d1b6a0fc4836fefc48d85 ;;
    srcds_css34_w_a.zip) echo "42894f729dc7cd99565e6b266c2f96f6c8a568599f31a5d902ce9e440bb0d020" ;;
    *) return 1 ;;
  esac
}

_srcds_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# fetch_srcds_zip URL OUT: OUT's basename names the pin.
fetch_srcds_zip() {
  local url="$1" out="$2" name want got
  name="$(basename "${out}")"
  if ! want="$(srcds_zip_sha256 "${name}")"; then
    echo "FAIL: no sha256 pin for ${name} (testing/scripts/srcds-zips.sh)" >&2
    return 1
  fi
  if [[ -s "${out}" ]]; then
    echo "Using cached ${name}"
  else
    echo "Downloading ${url}"
    curl -fL --retry 5 --retry-delay 3 -o "${out}.partial" "${url}" \
      || { rm -f "${out}.partial"; return 1; }
    mv "${out}.partial" "${out}" || return 1
  fi
  got="$(_srcds_sha256 "${out}")"
  if [[ "${got}" != "${want}" ]]; then
    echo "FAIL: ${name} sha256 ${got}, pinned ${want}" >&2
    rm -f "${out}"
    return 1
  fi
}
