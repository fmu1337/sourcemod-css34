#!/usr/bin/env python3
"""Append SH_DECL_EXTERN* macros (modern SM) adapted for SourceHook v4 ABI."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    sh = Path(os.environ["MMS_CSS34_SH_H"])
    root = Path(os.environ["MMS_CSS34_ROOT"])
    if "SH_DECL_EXTERN0_void" in sh.read_text():
        print("==> SH_DECL_EXTERN* already present")
        return 0

    modern = subprocess.check_output(
        ["git", "-C", str(root), "show", "HEAD:core/sourcehook/sourcehook.h"],
        text=True,
    )
    lines = modern.splitlines()
    macros: list[str] = []
    i = 0
    while i < len(lines):
        if lines[i].startswith("#define SH_DECL_EXTERN"):
            start = i
            while i < len(lines) and lines[i].rstrip().endswith("\\"):
                i += 1
            i += 1
            mac = "\n".join(lines[start:i])
            mac = mac.replace(
                "void *iface, ::SourceHook::ISourceHook::AddHookMode mode, bool post,",
                "void *iface, bool post,",
            )
            mlines = mac.split("\n")
            out: list[str] = []
            j = 0
            while j < len(mlines):
                line = mlines[j]
                out.append(line)
                if "__SourceHook_FHAdd##ifacetype##ifacefunc" in line:
                    block = [line]
                    while "handler);" not in mlines[j]:
                        j += 1
                        block.append(mlines[j])
                        out.append(mlines[j])
                    if not out[-1].rstrip().endswith("\\"):
                        out[-1] = out[-1].rstrip() + " \\"
                    for bl in block:
                        vl = bl.replace("__SourceHook_FHAdd", "__SourceHook_FHVPAdd")
                        vl = vl.replace("handler);", "handler, bool direct);")
                        out.append(vl if vl.rstrip().endswith("\\") else vl.rstrip() + " \\")
                j += 1
            macros.append("\n".join(out))
            continue
        i += 1

    if len(macros) < 40:
        print(f"Expected many SH_DECL_EXTERN macros, got {len(macros)}", file=sys.stderr)
        return 1

    text = sh.read_text()
    idx = text.rfind("#endif")
    if idx < 0:
        print("No #endif in sourcehook.h", file=sys.stderr)
        return 1
    insertion = (
        "\n\n/* SH_DECL_EXTERN* + FHVPAdd adapted for SH v4 AddHook ABI */\n"
        + "\n\n".join(macros)
        + "\n\n"
    )
    sh.write_text(text[:idx] + insertion + text[idx:])
    print(f"==> Appended {len(macros)} SH_DECL_EXTERN macros")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
