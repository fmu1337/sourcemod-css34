#!/usr/bin/env python3
"""ELF-aware byte diff between original rom4s release and a repro build."""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ElfSection:
    name: str
    offset: int
    size: int
    section_type: str


@dataclass
class BinaryDiff:
    rel: str
    orig_size: int
    repro_size: int
    diff_bytes: int
    diff_pct: float
    section_diffs: dict[str, int]
    first_offsets: list[int]
    build_id_orig: str | None
    build_id_repro: str | None
    note_tags: list[str]


def sha256_short(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:16]


def read_elf_sections(path: Path) -> list[ElfSection]:
    out = subprocess.check_output(["readelf", "-SW", str(path)], text=True)
    sections: list[ElfSection] = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("["):
            continue
        m = re.match(
            r"\[\s*\d+\]\s+(\S+)\s+(\S+)\s+[0-9a-fA-F]+\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)",
            line,
        )
        if not m:
            continue
        sections.append(
            ElfSection(
                name=m.group(1),
                section_type=m.group(2),
                offset=int(m.group(3), 16),
                size=int(m.group(4), 16),
            )
        )
    return sections


def read_build_id(path: Path) -> str | None:
    try:
        out = subprocess.check_output(["readelf", "-n", str(path)], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return None
    m = re.search(r"Build ID:\s*([0-9a-f]+)", out)
    return m.group(1) if m else None


def readelf_summary(path: Path) -> dict[str, str]:
    hdr = subprocess.check_output(["readelf", "-h", str(path)], text=True)
    fields: dict[str, str] = {}
    for key in ("Type", "Machine", "Entry point address", "Number of section headers"):
        m = re.search(rf"{re.escape(key)}:\s+(.+)", hdr)
        if m:
            fields[key] = m.group(1).strip()
    return fields


def map_offset(sections: list[ElfSection], offset: int) -> str:
    for sec in sections:
        if sec.offset <= offset < sec.offset + sec.size:
            return sec.name
    return ".outside"


def diff_pair(orig: Path, repro: Path, rel: str) -> BinaryDiff:
    ob = orig.read_bytes()
    rb = repro.read_bytes()
    sections = read_elf_sections(orig)
    n = min(len(ob), len(rb))
    diff_offsets = [i for i in range(n) if ob[i] != rb[i]]
    if len(ob) != len(rb):
        diff_offsets.extend(range(n, max(len(ob), len(rb))))

    section_diffs: Counter[str] = Counter()
    for off in diff_offsets[:500_000]:
        section_diffs[map_offset(sections, off if off < n else n - 1)] += 1

    notes: list[str] = []
    bid_o = read_build_id(orig)
    bid_r = read_build_id(repro)
    if bid_o and bid_r and bid_o != bid_r:
        notes.append("build-id")

    o_hdr = readelf_summary(orig)
    r_hdr = readelf_summary(repro)
    if o_hdr.get("Entry point address") != r_hdr.get("Entry point address"):
        notes.append("entry-point")

    total = max(len(ob), len(rb))
    return BinaryDiff(
        rel=rel,
        orig_size=len(ob),
        repro_size=len(rb),
        diff_bytes=len(diff_offsets),
        diff_pct=100.0 * len(diff_offsets) / total if total else 0.0,
        section_diffs=dict(section_diffs),
        first_offsets=diff_offsets[:12],
        build_id_orig=bid_o,
        build_id_repro=bid_r,
        note_tags=notes,
    )


def collect_sos(root: Path) -> dict[str, Path]:
    return {str(p.relative_to(root)): p for p in root.rglob("*.so")}


def sym_count(path: Path) -> int:
    out = subprocess.check_output(["readelf", "-s", str(path)], text=True, stderr=subprocess.DEVNULL)
    return sum(1 for line in out.splitlines() if " FUNC " in line or " OBJECT " in line)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original_root", type=Path, help="extracted original package root")
    parser.add_argument("repro_root", type=Path, help="extracted repro package root")
    parser.add_argument("--detail", metavar="REL", help="section breakdown for one .so")
    args = parser.parse_args()

    orig_files = collect_sos(args.original_root)
    repro_files = collect_sos(args.repro_root)
    all_rels = sorted(set(orig_files) | set(repro_files))

    diffs: list[BinaryDiff] = []
    for rel in all_rels:
        if rel not in orig_files or rel not in repro_files:
            print(f"MISSING {rel}", file=sys.stderr)
            continue
        diffs.append(diff_pair(orig_files[rel], repro_files[rel], rel))

    diffs.sort(key=lambda d: (d.orig_size != d.repro_size, d.diff_pct), reverse=True)

    print(f"{'module':<52} {'orig':>9} {'repro':>9} {'diff':>8} {'%':>6}  tag")
    print("-" * 95)
    size_match = 0
    for d in diffs:
        tag = "SIZE" if d.orig_size == d.repro_size else "DIFF"
        if tag == "SIZE":
            size_match += 1
        print(
            f"{d.rel:<52} {d.orig_size:>9} {d.repro_size:>9} "
            f"{d.diff_bytes:>8} {d.diff_pct:>5.2f}%  {tag}"
        )

    print()
    print(f"Summary: 0 byte-identical, {size_match} same-size / {len(diffs)} total")

    # Same-size modules: where do bytes differ?
    print("\n=== Same-size modules: differing ELF sections ===")
    for d in sorted(diffs, key=lambda x: x.rel):
        if d.orig_size != d.repro_size:
            continue
        top = sorted(d.section_diffs.items(), key=lambda kv: kv[1], reverse=True)[:6]
        sec_str = ", ".join(f"{k}:{v}" for k, v in top) if top else "(no byte diffs)"
        print(f"\n{d.rel} ({d.diff_bytes} bytes, {d.diff_pct:.2f}%)")
        print(f"  build-id  orig={d.build_id_orig} repro={d.build_id_repro}")
        print(f"  sections  {sec_str}")
        if d.first_offsets:
            print(f"  first off {d.first_offsets[:8]}")

    if args.detail:
        rel = args.detail
        if rel not in orig_files or rel not in repro_files:
            print(f"Unknown module: {rel}", file=sys.stderr)
            return 1
        o, r = orig_files[rel], repro_files[rel]
        print(f"\n=== Detail: {rel} ===")
        print("orig hdr:", readelf_summary(o))
        print("repro hdr:", readelf_summary(r))
        print("orig symbols:", sym_count(o), "repro symbols:", sym_count(r))
        d = diff_pair(o, r, rel)
        for sec, cnt in sorted(d.section_diffs.items(), key=lambda kv: kv[1], reverse=True):
            pct = 100.0 * cnt / d.diff_bytes if d.diff_bytes else 0
            print(f"  {sec:20} {cnt:>8} ({pct:5.1f}%)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
