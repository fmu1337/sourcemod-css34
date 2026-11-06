#!/usr/bin/env bash
# Static checks on the third-party extensions bundled in a SourceMod package
# (builder/third-party/*.sh; docs/EXTENSIONS.md "Third-party extensions"). Each one
# has addons/sourcemod/licenses/<name>/css34-<name>.json listing its files; this
# applies the ELF rules of check-package.sh to them, and stricter export rules:
#   - every ELF is 32-bit i386 and needs GLIBC <= GLIBC_FLOOR (2.17)
#   - no libstdc++.so.6 / libgcc_s.so.1 in NEEDED, no GLIBCXX_ / CXXABI_ imports
#   - no DT_TEXTREL; an extension exports GetSMExtAPI and nothing else
#     (no std:: / __cxxabiv1 / boost symbols from the static libstdc++ or asio)
#   - unversioned undefined imports only from testing/unversioned-imports.txt
#   - the manifest's line, SourceMod commit and extension API are the package's
#     (css34-package.json), which lists it under third_party
#   - the package of a line in SOCKET_LINES (builder/third-party/socket.env)
#     bundles Socket at SOCKET_VERSION / SOCKET_COMMIT
#
# Usage: check-third-party.sh <sourcemod package .tar.gz>   (default: $SM_PACKAGE)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE="${1:-${SM_PACKAGE:?usage: check-third-party.sh <sourcemod package .tar.gz>}}"
GLIBC_FLOOR="${GLIBC_FLOOR:-2.17}"
# shellcheck source=../../builder/third-party/socket.env
source "${ROOT}/builder/third-party/socket.env"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
fail=0
ok() { echo "OK: $*"; }
bad() { echo "FAIL: $*" >&2; fail=1; }
version_gt() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

tar -xzf "${PACKAGE}" -C "${TMP}/"
SM="${TMP}/addons/sourcemod"
echo "==> Third-party extensions in ${PACKAGE##*/}"
[[ -f "${SM}/css34-package.json" ]] || { bad "no addons/sourcemod/css34-package.json"; exit 1; }

# One "<manifest> <file>" line per bundled file; the manifest checks print to stderr.
if ! python3 - "${SM}" "${SOCKET_LINES}" "${SOCKET_VERSION}" "${SOCKET_COMMIT}" \
    >"${TMP}/files.txt" <<'PY'
import json, pathlib, sys
sm, socket_lines, socket_version, socket_commit = sys.argv[1:5]
root = pathlib.Path(sm).parent.parent
pkg = json.loads((pathlib.Path(sm) / "css34-package.json").read_text())
listed = {(t.get("name"), t.get("source_commit")) for t in pkg.get("third_party", [])}
failed = False
def bad(msg):
    global failed
    failed = True
    print("FAIL: " + msg, file=sys.stderr)
manifests = sorted(pathlib.Path(sm).glob("licenses/*/css34-*.json"))
found = {}
for m in manifests:
    rel = m.relative_to(root)
    d = json.loads(m.read_text())
    need = ["name", "version", "source", "source_commit", "source_tree_sha256", "line",
            "sm_commit", "extension_api", "compiler", "files"]
    missing = [k for k in need if d.get(k) in ("", None, [])]
    if missing:
        bad("{} missing {}".format(rel, ", ".join(missing)))
        continue
    found[d["name"]] = d
    if "10.2.1" not in d["compiler"]:
        bad("{}: built with {}, not devtoolset-10 GCC 10.2.1".format(rel, d["compiler"]))
    for mine, theirs in (("line", "line"), ("sm_commit", "sm_commit"), ("extension_api", "extension_api")):
        if str(d[mine]) != str(pkg[theirs]):
            bad("{}: {}={} but css34-package.json has {}={}".format(rel, mine, d[mine], theirs, pkg[theirs]))
    if (d["name"], d["source_commit"]) not in listed:
        bad("css34-package.json third_party does not list {} {}".format(d["name"], d["source_commit"]))
    for f in d["files"]:
        if not (root / f).is_file():
            bad("{} lists {}, which the package lacks".format(rel, f))
        else:
            print("{} {}".format(rel, f))
    print("OK: {} {} from {}@{} (line {}, extension API {})".format(
        d["name"], d["version"], d["source"], d["source_commit"][:12], d["line"],
        d["extension_api"]), file=sys.stderr)
if len(listed) != len(manifests):
    bad("css34-package.json lists {} third-party extension(s), the package has {} manifest(s)".format(
        len(listed), len(manifests)))
if pkg["line"] in socket_lines.split():
    s = found.get("Socket")
    if not s:
        bad("{} packages bundle the Socket extension (SOCKET_LINES): no licenses/socket/css34-socket.json".format(pkg["line"]))
    elif (s["version"], s["source_commit"]) != (socket_version, socket_commit):
        bad("Socket {}@{} is not the pin {}@{}".format(s["version"], s["source_commit"], socket_version, socket_commit))
    else:
        print("OK: {} bundles Socket {} (SOCKET_LINES)".format(pkg["line"], socket_version), file=sys.stderr)
sys.exit(1 if failed else 0)
PY
then
  fail=1
fi

mkdir -p "${TMP}/elves"
while read -r manifest rel; do
  elf="${TMP}/${rel}"
  head -c 4 "${elf}" | grep -q $'\x7fELF' || continue
  hdr="$(readelf -h "${elf}")"
  if grep -q 'ELF32' <<<"${hdr}" && grep -q 'Intel 80386' <<<"${hdr}"; then
    ok "${rel} is ELF32 i386"
  else
    bad "${rel} is not a 32-bit i386 ELF"
  fi
  [[ -x "${elf}" ]] || bad "${rel} is not executable in the package"

  elf_glibc="$(objdump -T "${elf}" | grep -oE 'GLIBC_[0-9.]+' | sed 's/GLIBC_//' | sort -V | tail -1 || true)"
  if [[ -n "${elf_glibc}" ]] && version_gt "${elf_glibc}" "${GLIBC_FLOOR}"; then
    bad "${rel} requires GLIBC_${elf_glibc} > ${GLIBC_FLOOR}"
  else
    ok "${rel} needs GLIBC_${elf_glibc:-none} <= ${GLIBC_FLOOR}"
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
  if readelf -d "${elf}" | grep -q 'TEXTREL'; then
    bad "${rel} has DT_TEXTREL (not built with -fPIC)"
  fi

  defined="$(objdump -T "${elf}" | awk '$0 !~ /\*UND\*/ && NF >= 6 {print $NF}' |
    grep -vE '^(Base|_init|_fini|_edata|_end|__bss_start)$' || true)"
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
    [[ -z "${others}" ]] || bad "${rel} exports more than GetSMExtAPI: $(head -5 <<<"${others}" | tr '\n' ' ')"
  fi
  cp "${elf}" "${TMP}/elves/$(basename "${rel}")"
done <"${TMP}/files.txt"

if compgen -G "${TMP}/elves/*" >/dev/null; then
  python3 "${ROOT}/testing/scripts/check-unversioned-imports.py" "${TMP}/elves" || fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Third-party extension check FAILED"
  exit 1
fi
echo "Third-party extension check PASSED"
