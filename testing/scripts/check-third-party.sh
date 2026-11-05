#!/usr/bin/env bash
# Static checks on a third-party extension archive (builder/third-party/build.sh),
# the same ELF rules as check-package.sh:
#   - every ELF is 32-bit i386 and needs GLIBC <= GLIBC_FLOOR (2.17)
#   - no libstdc++.so.6 / libgcc_s.so.1 in NEEDED (static, like SourceMod's own)
#   - no DT_TEXTREL, no std:: / __cxxabiv1 / boost exports; an extension exports
#     GetSMExtAPI and nothing else of its own
#   - unversioned undefined imports only from testing/unversioned-imports.txt
#   - css34-socket.json names the pinned source; with SM_PACKAGE, its line, SourceMod
#     commit and extension API match that package's css34-package.json
#
# Usage: [SM_PACKAGE=<sm package>] check-third-party.sh <archive.tar.gz>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHIVE="${1:?usage: check-third-party.sh <packages/third-party/*.tar.gz>}"
GLIBC_FLOOR="${GLIBC_FLOOR:-2.17}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
fail=0
ok() { echo "OK: $*"; }
bad() { echo "FAIL: $*" >&2; fail=1; }
version_gt() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

tar -xzf "${ARCHIVE}" -C "${TMP}/"
echo "==> Checking ${ARCHIVE##*/}"

mapfile -t exts < <(find "${TMP}/addons/sourcemod/extensions" -name '*.ext.so' 2>/dev/null | sort)
(( ${#exts[@]} > 0 )) || bad "no addons/sourcemod/extensions/*.ext.so in the archive"

count=0
max_glibc=""
while IFS= read -r -d '' elf; do
  head -c 4 "${elf}" | grep -q $'\x7fELF' || continue
  count=$((count + 1))
  rel="${elf#"${TMP}"/}"
  hdr="$(readelf -h "${elf}")"
  if grep -q 'ELF32' <<<"${hdr}" && grep -q 'Intel 80386' <<<"${hdr}"; then
    ok "${rel} is ELF32 i386"
  else
    bad "${rel} is not a 32-bit i386 ELF"
  fi
  [[ -x "${elf}" ]] || bad "${rel} is not executable in the archive"

  elf_glibc="$(objdump -T "${elf}" | grep -oE 'GLIBC_[0-9.]+' | sed 's/GLIBC_//' | sort -V | tail -1 || true)"
  if [[ -n "${elf_glibc}" ]]; then
    if [[ -z "${max_glibc}" ]] || version_gt "${elf_glibc}" "${max_glibc}"; then max_glibc="${elf_glibc}"; fi
    if version_gt "${elf_glibc}" "${GLIBC_FLOOR}"; then
      bad "${rel} requires GLIBC_${elf_glibc} > ${GLIBC_FLOOR}"
    else
      ok "${rel} needs GLIBC_${elf_glibc} <= ${GLIBC_FLOOR}"
    fi
  fi
  if objdump -T "${elf}" | grep -qE 'GLIBCXX_|CXXABI_'; then
    bad "${rel} imports versioned libstdc++ symbols (GLIBCXX_ / CXXABI_)"
  fi

  needed="$(readelf -d "${elf}" | awk '/\(NEEDED\)/ {print $NF}' | tr -d '[]')"
  echo "    NEEDED: $(tr '\n' ' ' <<<"${needed}")"
  for lib in libstdc++.so.6 libgcc_s.so.1; do
    if grep -qx "${lib}" <<<"${needed}"; then
      bad "${rel} NEEDED ${lib} (must be linked statically)"
    fi
  done
  if readelf -d "${elf}" | grep -qE '\(TEXTREL\)|TEXTREL'; then
    bad "${rel} has DT_TEXTREL (not built with -fPIC)"
  fi

  defined="$(objdump -T "${elf}" | awk '$0 !~ /\*UND\*/ && NF >= 6 {print $NF}' | grep -vE '^(Base|_init|_fini|_edata|_end|__bss_start)$' || true)"
  leaked="$(c++filt <<<"${defined}" | grep -E 'std::|__cxxabiv1|boost::|^__gnu_cxx' || true)"
  if [[ -n "${leaked}" ]]; then
    bad "${rel} exports $(wc -l <<<"${leaked}") std:: / __cxxabiv1 / boost symbols (static libstdc++ leak)"
    head -5 <<<"${leaked}" | sed 's/^/        /' >&2
  else
    ok "${rel} exports no std:: / __cxxabiv1 / boost symbols"
  fi
  if [[ "${rel}" == *.ext.so ]]; then
    if grep -qx 'GetSMExtAPI' <<<"${defined}"; then
      ok "${rel} exports GetSMExtAPI"
    else
      bad "${rel} does not export GetSMExtAPI"
    fi
    others="$(grep -vx 'GetSMExtAPI' <<<"${defined}" || true)"
    if [[ -n "${others}" ]]; then
      bad "${rel} exports more than GetSMExtAPI: $(head -5 <<<"${others}" | tr '\n' ' ')"
    fi
  fi
done < <(find "${TMP}" -type f -print0)
(( count > 0 )) || bad "no ELF files in the archive"
echo "Highest GLIBC symbol version referenced: ${max_glibc:-none} (floor ${GLIBC_FLOOR})"

python3 "${ROOT}/testing/scripts/check-unversioned-imports.py" "${TMP}" || fail=1

manifest="$(find "${TMP}/addons/sourcemod/licenses" -name 'css34-*.json' 2>/dev/null | head -n1 || true)"
if [[ -z "${manifest}" ]]; then
  bad "no addons/sourcemod/licenses/*/css34-*.json manifest"
else
  sm_manifest=""
  if [[ -n "${SM_PACKAGE:-}" ]]; then
    sm_manifest="${TMP}/sm-css34-package.json"
    tar -xzf "${SM_PACKAGE}" -O addons/sourcemod/css34-package.json >"${sm_manifest}"
  fi
  if ! python3 - "${manifest}" "${sm_manifest}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
need = ["name", "version", "source", "source_commit", "source_tree_sha256", "line",
        "sm_commit", "extension_api", "compiler"]
missing = [k for k in need if d.get(k) in ("", None)]
if missing:
    sys.exit("FAIL: {} missing {}".format(sys.argv[1].rsplit("/", 1)[-1], ", ".join(missing)))
if "10.2.1" not in d["compiler"]:
    sys.exit("FAIL: built with {}, not devtoolset-10 GCC 10.2.1".format(d["compiler"]))
if len(sys.argv) > 2 and sys.argv[2]:
    sm = json.load(open(sys.argv[2]))
    for mine, theirs in (("line", "line"), ("sm_commit", "sm_commit"), ("extension_api", "extension_api")):
        if str(d[mine]) != str(sm[theirs]):
            sys.exit("FAIL: {}={} but the SourceMod package has {}={}".format(mine, d[mine], theirs, sm[theirs]))
    if not int(sm["extension_api_min"]) <= int(d["extension_api"]) <= int(sm["extension_api"]):
        sys.exit("FAIL: extension API {} outside the package's {}..{}".format(
            d["extension_api"], sm["extension_api_min"], sm["extension_api"]))
    print("OK: matches the SourceMod package (line {}, sm_commit {}, extension API {})".format(
        d["line"], d["sm_commit"][:12], d["extension_api"]))
print("OK: {} {} from {}@{}".format(d["name"], d["version"], d["source"], d["source_commit"][:12]))
PY
  then
    fail=1
  fi
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Third-party ABI check FAILED"
  exit 1
fi
echo "Third-party ABI check PASSED"
