#!/usr/bin/env bash
set -euo pipefail

dest="${1:?destination .mmdb file required}"
mkdir -p "$(dirname "$dest")"

if [ -f "$dest" ] && [ "${FORCE_GEOLITE_DOWNLOAD:-0}" != "1" ]; then
  echo "==> GeoLite2 database already present: $dest"
  exit 0
fi

# P3TERX mirror of MaxMind GeoLite2-Country (updated periodically).
urls=(
  "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
  "https://git.io/GeoLite2-Country.mmdb"
)

for url in "${urls[@]}"; do
  echo "==> Downloading GeoLite2-Country.mmdb from $url"
  if curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"; then
    if [ -s "$dest" ]; then
      echo "==> GeoLite2 database saved to $dest ($(wc -c < "$dest") bytes)"
      exit 0
    fi
  fi
  rm -f "$dest"
done

echo "error: failed to download GeoLite2-Country.mmdb" >&2
exit 1
