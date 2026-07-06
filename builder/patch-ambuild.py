#!/usr/bin/env python3
"""Patch SourceMod build scripts for CSS v34 (ep1 + episode1 SDKs)."""

from __future__ import annotations

import sys
from pathlib import Path


MARKER = "'ep1':  SDK('HL2SDK', '1.ep1', '1', 'EPISODEONE', WinLinux, 'ep1'),"
ANCHOR = "'episode1':  SDK('HL2SDK', '2.ep1', '1', 'EPISODEONE', WinLinux, 'episode1'),"
PATH_BLOCK_OLD = """    if sdk.name == 'episode1' or sdk.name == 'darkm':
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])
    else:
      paths.append(['public', 'game', 'server'])
      paths.append(['public', 'toolframework'])
      paths.append(['game', 'shared'])
      paths.append(['common'])"""
PATH_BLOCK_NEW = """    if sdk.name == 'episode1' or sdk.name == 'darkm' or sdk.name == 'ep1':
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])
    else:
      paths.append(['public', 'game', 'server'])
      paths.append(['public', 'toolframework'])
      paths.append(['game', 'shared'])
      paths.append(['common'])"""
LIB_BLOCK_OLD = "      if sdk.name == 'episode1':"
LIB_BLOCK_NEW = "      if sdk.name in ['episode1', 'ep1']:"
GCC_FLAGS_OLD = "      '-Wno-array-bounds',\n      '-msse',"
GCC_FLAGS_NEW = "      '-Wno-array-bounds',\n      '-Wno-stringop-overflow',\n      '-Wno-error=stringop-overflow',\n      '-Wno-stringop-truncation',\n      '-Wno-error=stringop-truncation',\n      '-Wno-format-truncation',\n      '-Wno-error=format-truncation',\n      '-msse',"


def main() -> int:
    script = Path(sys.argv[1] if len(sys.argv) > 1 else "sourcemod/AMBuildScript")
    text = script.read_text(encoding="utf-8")

    if MARKER not in text:
        if ANCHOR not in text:
            print(f"Could not find episode1 SDK anchor in {script}", file=sys.stderr)
            return 1

        text = text.replace(
            ANCHOR,
            ANCHOR + "\n  " + MARKER,
            1,
        )

    if PATH_BLOCK_OLD in text:
        text = text.replace(PATH_BLOCK_OLD, PATH_BLOCK_NEW, 1)
    elif PATH_BLOCK_NEW not in text:
        print("Could not patch SDK include paths in AMBuildScript", file=sys.stderr)
        return 1

    if LIB_BLOCK_OLD in text:
        text = text.replace(LIB_BLOCK_OLD, LIB_BLOCK_NEW, 1)

    if GCC_FLAGS_OLD in text and GCC_FLAGS_NEW not in text:
        text = text.replace(GCC_FLAGS_OLD, GCC_FLAGS_NEW, 1)

    script.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
