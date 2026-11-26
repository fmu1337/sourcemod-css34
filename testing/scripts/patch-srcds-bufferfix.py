#!/usr/bin/env python3
"""
Patch CS:S v34 dedicated-server binaries for modern glibc (BufferFix / srcds_patch).

Reproduces the essential edits from bruno_args' `srcds_patch` without shipping
pre-patched `.so` blobs:

1. engine_{amd,i486,i686}.so and cstrike/bin/server_i486.so
   - Retarget every ELF32 relocation that referenced `memcpy` to `memmove`
     (R_386_* in .rel.dyn / .rel.plt).
   - Zero the primary `memcpy` `.dynsym` entry and its `.gnu.version` slot so
     the dynamic linker no longer binds `memcpy` for those sites.

2. bin/steamclient_i486.so (optional noise suppression)
   - Replace three `push "Assertion Failed: !\\"Implement me!\\""; call`
     sequences with `jmp +0x0a` + NOPs (same as the hlmod rar).

Background: overlapping `memcpy` on modern glibc → hangs / `Unknown command ":"`.
`memmove` is defined for overlaps. See testing/docs/bufferfix.md.

Usage:
  python3 testing/scripts/patch-srcds-bufferfix.py /path/to/server-root
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# ELF32 constants
PT_DYNAMIC = 2
SHT_REL = 9
SHT_RELA = 4
SHT_DYNSYM = 11
SHT_GNU_VERSYM = 0x6FFFFFFF
DT_NULL = 0
DT_STRTAB = 5
DT_SYMTAB = 6
DT_STRSZ = 10
EM_386 = 3

# steamclient: mov DWORD PTR [esp], imm32 ; call rel32(-4)
# imm32 is the "Assertion Failed: !"Implement me!"" string VA in this binary.
STEAM_ASSERT_PAT = bytes.fromhex("c70424cca95e00e8fcffffff")
STEAM_ASSERT_REPL = bytes.fromhex("eb0a90909090909090909090")
# Only the three sites muted by srcds_patch (skip other uses of the same string).
STEAM_ASSERT_AFTER = (
    bytes.fromhex("8b45088b4018c9c3"),  # mov eax,[ebp+8]; mov eax,[eax+18]; leave; ret
    bytes.fromhex("83c4205b5e5dc389"),  # add esp,20; pop ebx; pop esi; pop ebp; ret
)


def _u16(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def _u32(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]


def _read_cstr(data: bytes, off: int) -> str:
    end = data.find(b"\x00", off)
    if end < 0:
        end = len(data)
    return data[off:end].decode("latin1", errors="replace")


def patch_memcpy_relocs(data: bytearray) -> dict:
    """Retarget memcpy→memmove relocs; zero memcpy dynsym + versym. Mutates data."""
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    if data[4] != 1:
        raise ValueError("only ELF32 supported")
    if _u16(data, 18) != EM_386:
        raise ValueError("not an i386 ELF")

    e_shoff = _u32(data, 32)
    e_shentsize = _u16(data, 46)
    e_shnum = _u16(data, 48)
    e_shstrndx = _u16(data, 50)

    def shdr(i: int) -> dict:
        o = e_shoff + i * e_shentsize
        return {
            "name_off": _u32(data, o + 0),
            "type": _u32(data, o + 4),
            "offset": _u32(data, o + 16),
            "size": _u32(data, o + 20),
            "link": _u32(data, o + 24),
            "entsize": _u32(data, o + 36),
        }

    shstr = shdr(e_shstrndx)
    sections = []
    for i in range(e_shnum):
        s = shdr(i)
        s["name"] = _read_cstr(data, shstr["offset"] + s["name_off"])
        s["index"] = i
        sections.append(s)

    dynsym = next((s for s in sections if s["name"] == ".dynsym"), None)
    dynstr = next((s for s in sections if s["name"] == ".dynstr"), None)
    versym = next((s for s in sections if s["name"] == ".gnu.version"), None)
    if not dynsym or not dynstr:
        raise ValueError("missing .dynsym/.dynstr")

    entsz = dynsym["entsize"] or 16
    nsym = dynsym["size"] // entsz
    memcpy_idx = memmove_idx = None
    for i in range(nsym):
        o = dynsym["offset"] + i * entsz
        name = _read_cstr(data, dynstr["offset"] + _u32(data, o))
        if name == "memcpy" and memcpy_idx is None:
            memcpy_idx = i
        elif name == "memmove" and memmove_idx is None:
            memmove_idx = i
    if memmove_idx is None:
        raise ValueError("no memmove in .dynsym")
    if memcpy_idx is None:
        # A tree this script already patched: memcpy's entry is zeroed (an
        # all-zero symbol past the reserved index 0), so nothing is left to do.
        for i in range(1, nsym):
            o = dynsym["offset"] + i * entsz
            if not any(data[o : o + entsz]):
                return {"already": True}
        raise ValueError("no memcpy in .dynsym and no zeroed entry: unexpected input")

    retargeted = 0
    for sec in sections:
        if sec["type"] != SHT_REL:
            continue
        if sec["name"] not in (".rel.dyn", ".rel.plt"):
            continue
        rel_entsz = sec["entsize"] or 8
        nrel = sec["size"] // rel_entsz
        for j in range(nrel):
            ro = sec["offset"] + j * rel_entsz
            r_info = _u32(data, ro + 4)
            r_sym = r_info >> 8
            r_type = r_info & 0xFF
            if r_sym != memcpy_idx:
                continue
            struct.pack_into("<I", data, ro + 4, (memmove_idx << 8) | r_type)
            retargeted += 1

    if retargeted == 0:
        raise ValueError("memcpy is in .dynsym but no relocation uses it: unexpected input")

    # Zero primary memcpy dynsym entry (16 bytes).
    so = dynsym["offset"] + memcpy_idx * entsz
    data[so : so + entsz] = b"\x00" * entsz

    versym_cleared = False
    if versym and versym["entsize"] in (0, 2):
        vo = versym["offset"] + memcpy_idx * 2
        if vo + 2 <= len(data):
            struct.pack_into("<H", data, vo, 0)
            versym_cleared = True

    return {
        "retargeted": retargeted,
        "memcpy_idx": memcpy_idx,
        "memmove_idx": memmove_idx,
        "versym_cleared": versym_cleared,
    }


def _count_sites(data: bytes, pattern: bytes) -> list[int]:
    sites = []
    start = 0
    while True:
        i = data.find(pattern, start)
        if i < 0:
            return sites
        if bytes(data[i + 12 : i + 20]) in STEAM_ASSERT_AFTER:
            sites.append(i)
            start = i + 12
        else:
            start = i + 1


def patch_steamclient_asserts(data: bytearray) -> tuple[int, int]:
    """Mute the Implement-me assertion call sites. Returns (muted now, muted before)."""
    stock = _count_sites(data, STEAM_ASSERT_PAT)
    done = _count_sites(data, STEAM_ASSERT_REPL)
    for i in stock:
        data[i : i + 12] = STEAM_ASSERT_REPL
    return len(stock), len(done)


ENGINE_FILES = (
    "bin/engine_amd.so",
    "bin/engine_i486.so",
    "bin/engine_i686.so",
)
SERVER_FILE = "cstrike/bin/server_i486.so"
STEAMCLIENT_FILE = "bin/steamclient_i486.so"


def patch_tree(server_dir: Path, *, steamclient: bool = True) -> int:
    rc = 0
    for rel in ENGINE_FILES + (SERVER_FILE,):
        path = server_dir / rel
        if not path.is_file():
            print(f"SKIP missing {rel}", file=sys.stderr)
            rc = 1
            continue
        data = bytearray(path.read_bytes())
        try:
            info = patch_memcpy_relocs(data)
        except (ValueError, struct.error, IndexError) as err:
            print(f"FAIL {rel}: {err}", file=sys.stderr)
            rc = 1
            continue
        if info.get("already"):
            print(f"OK {rel}: already patched")
            continue
        path.write_bytes(data)
        print(
            f"OK {rel}: retargeted {info['retargeted']} memcpy→memmove "
            f"(sym {info['memcpy_idx']}→{info['memmove_idx']}, "
            f"versym_cleared={info['versym_cleared']})"
        )

    if steamclient:
        path = server_dir / STEAMCLIENT_FILE
        if path.is_file():
            data = bytearray(path.read_bytes())
            n, before = patch_steamclient_asserts(data)
            if n + before != 3:
                print(
                    f"FAIL {STEAMCLIENT_FILE}: expected 3 assertion sites, "
                    f"found {n} stock + {before} patched",
                    file=sys.stderr,
                )
                return 1
            if n:
                path.write_bytes(data)
            print(f"OK {STEAMCLIENT_FILE}: muted {n} assertion site(s), {before} already muted")
        else:
            print(f"SKIP missing {STEAMCLIENT_FILE}", file=sys.stderr)
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "server_dir",
        type=Path,
        help="CS:S v34 server root (contains bin/ and cstrike/)",
    )
    ap.add_argument(
        "--no-steamclient",
        action="store_true",
        help="Skip steamclient assertion muting",
    )
    args = ap.parse_args()
    if not args.server_dir.is_dir():
        print(f"not a directory: {args.server_dir}", file=sys.stderr)
        return 2
    return patch_tree(args.server_dir, steamclient=not args.no_steamclient)


if __name__ == "__main__":
    sys.exit(main())
