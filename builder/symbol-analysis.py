#!/usr/bin/env python3
"""Compare ELF symbols and section sizes between original and repro builds."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path


SDK_MODULES = [
    "addons/sourcemod/bin/sourcemod.1.ep1.so",
    "addons/sourcemod/bin/sourcemod.2.ep1.so",
    "addons/sourcemod/extensions/sdkhooks.ext.1.ep1.so",
    "addons/sourcemod/extensions/sdkhooks.ext.2.ep1.so",
    "addons/sourcemod/extensions/sdktools.ext.1.ep1.so",
    "addons/sourcemod/extensions/sdktools.ext.2.ep1.so",
    "addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so",
    "addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so",
]

SIMPLE_MODULES = [
    "addons/sourcemod/extensions/bintools.ext.so",
    "addons/sourcemod/extensions/geoip.ext.so",
    "addons/sourcemod/extensions/regex.ext.so",
    "addons/sourcemod/extensions/dbi.sqlite.ext.so",
]

EH_PREFIXES = (
    "__cxa_",
    "_Unwind_",
    "__gxx_personality",
    "_ZSt9terminate",
    "_ZTISt",
    "_ZTVSt",
    "_ZTVN10__cxxabiv1",
    "_ZNSt",
    "_ZdaPv",
    "_ZdlPv",
    "_Znaj",
    "_Znwj",
)

VALVE_HINTS = (
    "tier0",
    "vstdlib",
    "Error",
    "DevMsg",
    "Warning",
    "CommandLine",
    "CreateInterface",
    "GetCVar",
    "CVProf",
    "ConColor",
    "Plat_",
    "MemAlloc",
)


@dataclass
class FuncSym:
    name: str
    size: int
    bind: str


@dataclass
class ModuleReport:
    rel: str
    orig_size: int
    repro_size: int
    sections: dict[str, tuple[int, int]] = field(default_factory=dict)
    orig_und: set[str] = field(default_factory=set)
    repro_und: set[str] = field(default_factory=set)
    orig_funcs: dict[str, FuncSym] = field(default_factory=dict)
    repro_funcs: dict[str, FuncSym] = field(default_factory=dict)


def run(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)


def normalize_sym(name: str) -> str:
    return name.split("@@")[0].split("@")[0]


def read_sections(path: Path) -> dict[str, int]:
    out = run(["readelf", "-SW", str(path)])
    sections: dict[str, int] = {}
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("["):
            continue
        m = re.match(
            r"\[\s*\d+\]\s+(\S+)\s+\S+\s+[0-9a-fA-F]+\s+[0-9a-fA-F]+\s+([0-9a-fA-F]+)",
            line,
        )
        if m:
            sections[m.group(1)] = int(m.group(2), 16)
    return sections


def read_und(path: Path) -> set[str]:
    out = run(["nm", "-D", str(path)])
    return {normalize_sym(line.split()[-1]) for line in out.splitlines() if " U " in line}


def read_funcs(path: Path) -> dict[str, FuncSym]:
    out = run(["nm", "--size-sort", "-S", str(path)])
    funcs: dict[str, FuncSym] = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        size_s, bind, name = parts[-3], parts[-2], parts[-1]
        if bind not in ("T", "t", "W", "w"):
            continue
        try:
            size = int(size_s, 16)
        except ValueError:
            continue
        key = normalize_sym(name)
        prev = funcs.get(key)
        if prev is None or size > prev.size:
            funcs[key] = FuncSym(name=key, size=size, bind=bind)
    return funcs


def categorize_und(name: str) -> str:
    if any(name.startswith(p) or p in name for p in EH_PREFIXES):
        return "cxx-eh"
    if any(h in name for h in VALVE_HINTS):
        return "valve/tier0"
    if "GLIBC" in name or name in ("printf", "sprintf", "snprintf", "malloc", "free"):
        return "libc"
    if "pthread" in name or "dl_" in name:
        return "posix"
    return "other"


def demangle(name: str) -> str:
    try:
        out = subprocess.check_output(["c++filt", name], text=True, stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return name
    return out if out else name


def collect_sos(root: Path) -> dict[str, Path]:
    return {str(p.relative_to(root)): p for p in root.rglob("*.so")}


def analyze_module(orig: Path, repro: Path, rel: str) -> ModuleReport:
    orig_secs = read_sections(orig)
    repro_secs = read_sections(repro)
    sections = {}
    for sec in (".text", ".rodata", ".data", ".bss"):
        sections[sec] = (orig_secs.get(sec, 0), repro_secs.get(sec, 0))

    return ModuleReport(
        rel=rel,
        orig_size=orig.stat().st_size,
        repro_size=repro.stat().st_size,
        sections=sections,
        orig_und=read_und(orig),
        repro_und=read_und(repro),
        orig_funcs=read_funcs(orig),
        repro_funcs=read_funcs(repro),
    )


def print_section_table(reports: list[ModuleReport]) -> None:
    print("\n=== Section sizes (original vs repro) ===")
    print(f"{'module':<52} {'orig.text':>10} {'repro.text':>10} {'Δ.text':>10} {'Δ.file':>10}")
    print("-" * 96)
    for r in reports:
        ot, rt = r.sections.get(".text", (0, 0))
        print(
            f"{r.rel:<52} {ot:>10} {rt:>10} {ot - rt:>10} {r.orig_size - r.repro_size:>10}"
        )


def print_undiff(report: ModuleReport, limit: int = 20) -> None:
    only_orig = sorted(report.orig_und - report.repro_und)
    only_repro = sorted(report.repro_und - report.orig_und)
    print(f"\n--- UND imports: {report.rel} ---")
    print(f"orig={len(report.orig_und)} repro={len(report.repro_und)} "
          f"only-orig={len(only_orig)} only-repro={len(only_repro)}")

    buckets_o: dict[str, list[str]] = defaultdict(list)
    buckets_r: dict[str, list[str]] = defaultdict(list)
    for s in only_orig:
        buckets_o[categorize_und(s)].append(s)
    for s in only_repro:
        buckets_r[categorize_und(s)].append(s)

    print("  only in ORIGINAL:")
    for cat in sorted(buckets_o):
        print(f"    [{cat}] {len(buckets_o[cat])}")
        for s in buckets_o[cat][:limit]:
            print(f"      - {s}")

    print("  only in REPRO:")
    for cat in sorted(buckets_r):
        print(f"    [{cat}] {len(buckets_r[cat])}")
        for s in buckets_r[cat][:limit]:
            print(f"      - {s}")


def print_funcdiff(report: ModuleReport, limit: int = 15) -> None:
    only_orig = set(report.orig_funcs) - set(report.repro_funcs)
    only_repro = set(report.repro_funcs) - set(report.orig_funcs)
    common = set(report.orig_funcs) & set(report.repro_funcs)

    orig_only_bytes = sum(report.orig_funcs[s].size for s in only_orig)
    repro_only_bytes = sum(report.repro_funcs[s].size for s in only_repro)
    size_deltas = []
    for name in common:
        o = report.orig_funcs[name].size
        r = report.repro_funcs[name].size
        if o != r:
            size_deltas.append((abs(o - r), o - r, name))

    print(f"\n--- Defined functions: {report.rel} ---")
    print(
        f"orig funcs={len(report.orig_funcs)} repro={len(report.repro_funcs)} "
        f"only-orig={len(only_orig)} ({orig_only_bytes} B) "
        f"only-repro={len(only_repro)} ({repro_only_bytes} B) "
        f"size-mismatch={len(size_deltas)}"
    )

    if only_orig:
        top = sorted(((report.orig_funcs[s].size, s) for s in only_orig), reverse=True)[:limit]
        print("  largest only in ORIGINAL:")
        for size, name in top:
            print(f"    {size:6}  {demangle(name)}")

    if only_repro:
        top = sorted(((report.repro_funcs[s].size, s) for s in only_repro), reverse=True)[:limit]
        print("  largest only in REPRO:")
        for size, name in top:
            print(f"    {size:6}  {demangle(name)}")

    if size_deltas:
        top = sorted(size_deltas, reverse=True)[:limit]
        print("  largest size mismatches (orig - repro):")
        for _, delta, name in top:
            o = report.orig_funcs[name].size
            r = report.repro_funcs[name].size
            print(f"    {delta:+6}  orig={o:5} repro={r:5}  {demangle(name)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original_root", type=Path)
    parser.add_argument("repro_root", type=Path)
    parser.add_argument("--module", action="append", help="Analyze one module (repeatable)")
    parser.add_argument("--sdk-only", action="store_true", default=True)
    parser.add_argument("--all", dest="sdk_only", action="store_false")
    parser.add_argument("--detail", action="store_true", help="UND + function diffs per module")
    args = parser.parse_args()

    orig_files = collect_sos(args.original_root)
    repro_files = collect_sos(args.repro_root)

    if args.module:
        targets = args.module
    elif args.sdk_only:
        targets = SDK_MODULES + SIMPLE_MODULES
    else:
        targets = sorted(set(orig_files) & set(repro_files))

    reports: list[ModuleReport] = []
    for rel in targets:
        if rel not in orig_files or rel not in repro_files:
            print(f"MISSING {rel}", file=sys.stderr)
            continue
        reports.append(analyze_module(orig_files[rel], repro_files[rel], rel))

    print_section_table(reports)

    print("\n=== Summary ===")
    sdk_reports = [r for r in reports if r.rel in SDK_MODULES]
    if sdk_reports:
        text_gap = sum(r.sections.get(".text", (0, 0))[0] - r.sections[".text"][1] for r in sdk_reports)
        file_gap = sum(r.orig_size - r.repro_size for r in sdk_reports)
        print(f"SDK ep1 modules: orig .text exceeds repro by {text_gap} bytes ({text_gap/1024:.1f} KB)")
        print(f"SDK ep1 modules: orig file size exceeds repro by {file_gap} bytes ({file_gap/1024:.1f} KB)")
        print("Interpretation: original contains MORE compiled code in .text, not linker metadata.")

    if args.detail:
        for r in reports:
            if r.rel not in SDK_MODULES:
                continue
            print_undiff(r)
            print_funcdiff(r)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
