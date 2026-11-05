#!/usr/bin/env bash
# Install the pinned actionlint (ci.yml hygiene) into DEST (default /usr/local/bin).
# The tarball is checked against the sha256 from the release's checksums file.
set -euo pipefail
version=1.7.12
sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
dest="${DEST:-/usr/local/bin}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tarball="$tmp/actionlint.tar.gz"
curl -fsSL --retry 5 -o "$tarball" \
  "https://github.com/rhysd/actionlint/releases/download/v${version}/actionlint_${version}_linux_amd64.tar.gz"
echo "${sha256}  ${tarball}" | sha256sum -c -
tar -xzf "$tarball" -C "$tmp" actionlint
if [[ -w "$dest" ]]; then
  install -m 755 "$tmp/actionlint" "$dest/actionlint"
else
  sudo install -m 755 "$tmp/actionlint" "$dest/actionlint"
fi
"$dest/actionlint" -version
