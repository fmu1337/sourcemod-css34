#!/usr/bin/env bash
# Extract / classify CS:S v34 srcds launch flags from stock binaries.
# Requires: curl, unzip, strings, python3 (optional: addr2line for xref notes).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
OUT_DIR="${OUT_DIR:-${CACHE_DIR}/extract-params}"
BIN_ZIP_URL="${BIN_ZIP_URL:-https://bitbucket.org/rom4s/other.get/downloads/srcds_css34_l_a.zip}"
ZIP="${CACHE_DIR}/srcds_css34_l_a.zip"

mkdir -p "${CACHE_DIR}" "${OUT_DIR}"

if [[ ! -f "${ZIP}" ]]; then
  echo "Downloading ${BIN_ZIP_URL}"
  curl -fL --retry 5 --retry-delay 3 -o "${ZIP}.partial" "${BIN_ZIP_URL}"
  mv "${ZIP}.partial" "${ZIP}"
fi

rm -rf "${OUT_DIR}/bin"
mkdir -p "${OUT_DIR}/bin"
unzip -o -j "${ZIP}" \
  srcds_run srcds_i686 \
  bin/dedicated_i686.so bin/engine_i686.so bin/tier0_i486.so \
  cstrike/bin/server_i486.so \
  -d "${OUT_DIR}/bin" >/dev/null

python3 - "${OUT_DIR}" <<'PY'
import os, sys, re, hashlib

out = sys.argv[1]
bindir = os.path.join(out, "bin")

def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def flags_from(path):
    data = open(path, "rb").read()
    found = set()
    i = 0
    n = len(data)
    while i < n - 1:
        if data[i] == 0x2D and (65 <= data[i + 1] <= 90 or 97 <= data[i + 1] <= 122):
            j = i + 1
            while j < n and (48 <= data[j] <= 57 or 65 <= data[j] <= 90 or 97 <= data[j] <= 122 or data[j] == 95):
                j += 1
            if j < n and data[j] == 0 and 3 <= (j - i) <= 40:
                s = data[i:j].decode("ascii")
                # drop obvious garbage from code bytes
                body = s[1:]
                if body.lower() == body or body[:1].isupper() and body[1:].islower() or s in ("-ip", "-sw", "-DT"):
                    if sum(c.islower() for c in body) >= 2 or s in ("-ip", "-sw"):
                        found.add(s)
            i = j
        else:
            i += 1
    return sorted(found)

watched = [
    "-dev", "-dev2", "-nodev", "-allowdebug", "-debug", "-dumplongticks",
    "-notrap", "-norestart", "-tickrate", "-condebug", "-nomaster",
    "-localcser", "-insecure", "-nobots", "-textmode", "-pidfile",
    "-console", "-usercon", "-reader", "-pcmdscpmrc", "-sfwb", "-wsb",
    "-vcforce", "-sesb",
]

bins = [
    ("srcds_run", "srcds_run"),
    ("srcds_i686", "srcds_i686"),
    ("dedicated_i686.so", "dedicated_i686.so"),
    ("engine_i686.so", "engine_i686.so"),
    ("tier0_i486.so", "tier0_i486.so"),
    ("server_i486.so", "server_i486.so"),
]

zip_path = os.path.join(os.path.dirname(out), "srcds_css34_l_a.zip")
report = os.path.join(out, "params-report.txt")
with open(report, "w", encoding="utf-8") as rp:
    rp.write("CS:S v34 srcds parameter scrape\n")
    rp.write(f"zip md5: {md5(zip_path) if os.path.isfile(zip_path) else 'n/a'}\n\n")
    for label, name in bins:
        path = os.path.join(bindir, name)
        rp.write(f"## {label}  md5={md5(path)}\n")
        if name == "srcds_run":
            text = open(path, "r", encoding="latin1", errors="replace").read()
            flags = sorted(set(re.findall(r'"(-[a-zA-Z][a-zA-Z0-9_]*)"', text)))
        else:
            flags = flags_from(path)
        for f in flags:
            mark = "  <<<" if f in watched else ""
            rp.write(f"  {f}{mark}\n")
        rp.write("\n  watched presence:\n")
        if name == "srcds_run":
            text = open(path, encoding="latin1").read()
            for w in watched:
                rp.write(f"    {w}: {'YES' if w in text else 'no'}\n")
        else:
            data = open(path, "rb").read()
            for w in watched:
                hit = (w.encode("ascii") + b"\x00") in data
                rp.write(f"    {w}: {'YES' if hit else 'no'}\n")
        rp.write("\n")

print(f"Wrote {report}")
print(open(report, encoding="utf-8").read())
PY

echo "Done. See ${OUT_DIR}/params-report.txt and testing/docs/srcds-params.md"
