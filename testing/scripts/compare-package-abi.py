#!/usr/bin/env python3
"""Compare two builds of a package for ABI identity (T2.7 frozen-line rebuilds).

    compare-package-abi.py REFERENCE.tar.gz REBUILD.tar.gz

Fails unless both archives hold the same set of files and every ELF file has
the same exported dynamic symbols (name, type, version), the same DT_NEEDED
list and the same SONAME. css34-package.json must agree on everything but
build_date and css34_pack_commit. Files whose bytes differ (ELF included) are
listed as notes: builds embed dates, so byte identity is not the gate. Uses binutils
(nm, readelf), which read 32-bit ELF on any host.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

VOLATILE_MANIFEST_KEYS = {"build_date", "css34_pack_commit"}


def extract(archive: Path, dest: Path) -> dict[str, Path]:
    with tarfile.open(archive) as tf:
        members = [m for m in tf.getmembers() if m.isfile() or m.issym()]
        for m in members:
            if m.name.startswith("/") or ".." in Path(m.name).parts:
                raise SystemExit(f"FAIL: unsafe path {m.name!r} in {archive}")
        try:
            tf.extractall(dest, members=members, filter="data")
        except TypeError:  # Python without tarfile extraction filters
            tf.extractall(dest, members=members)
    return {m.name.removeprefix("./"): dest / m.name for m in members}


def is_elf(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    with open(path, "rb") as f:
        return f.read(4) == b"\x7fELF"


def exports(path: Path) -> set[str]:
    out = subprocess.run(["nm", "-D", "--defined-only", "--with-symbol-versions", "-P", str(path)],
                         capture_output=True, text=True, check=True).stdout
    # -P: "name type value size"; the value differs between builds, the type does not.
    return {" ".join(line.split()[:2]) for line in out.splitlines() if line.strip()}


def dynamic(path: Path) -> tuple[list[str], str]:
    out = subprocess.run(["readelf", "-dW", str(path)], capture_output=True, text=True, check=True).stdout
    needed, soname = [], ""
    for line in out.splitlines():
        if "(NEEDED)" in line:
            needed.append(line.split("[", 1)[1].rstrip("]"))
        elif "(SONAME)" in line:
            soname = line.split("[", 1)[1].rstrip("]")
    return needed, soname


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() and not path.is_symlink() else "link"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    ref_archive, new_archive = Path(sys.argv[1]), Path(sys.argv[2])
    failures: list[str] = []
    notes: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        ref = extract(ref_archive, Path(tmp) / "ref")
        new = extract(new_archive, Path(tmp) / "new")
        for name in sorted(set(ref) - set(new)):
            failures.append(f"only in {ref_archive.name}: {name}")
        for name in sorted(set(new) - set(ref)):
            failures.append(f"only in {new_archive.name}: {name}")
        elves = 0
        for name in sorted(set(ref) & set(new)):
            a, b = ref[name], new[name]
            if is_elf(a) or is_elf(b):
                elves += 1
                if not (is_elf(a) and is_elf(b)):
                    failures.append(f"{name}: ELF in one package only")
                    continue
                ea, eb = exports(a), exports(b)
                if ea != eb:
                    failures.append(f"{name}: exports differ (-{len(ea - eb)} +{len(eb - ea)}): "
                                    + ", ".join(sorted(ea ^ eb)[:8]))
                da, db = dynamic(a), dynamic(b)
                if da != db:
                    failures.append(f"{name}: NEEDED/SONAME {da} != {db}")
                if sha(a) != sha(b):
                    notes.append(name)
            elif name.endswith("css34-package.json"):
                ma, mb = json.loads(a.read_text()), json.loads(b.read_text())
                for key in sorted((set(ma) | set(mb)) - VOLATILE_MANIFEST_KEYS):
                    if ma.get(key) != mb.get(key):
                        failures.append(f"{name}: {key} {ma.get(key)!r} != {mb.get(key)!r}")
            elif sha(a) != sha(b):
                notes.append(name)
        print(f"compared {len(set(ref) & set(new))} files, {elves} ELF: "
              f"{ref_archive.name} vs {new_archive.name}")
    for n in notes:
        print(f"NOTE: bytes differ (not an ABI gate): {n}")
    for f in failures:
        print(f"FAIL: {f}", file=sys.stderr)
    if failures:
        return 1
    print("OK: same files, exports, NEEDED and SONAME")
    return 0


if __name__ == "__main__":
    sys.exit(main())
