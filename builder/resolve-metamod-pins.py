#!/usr/bin/env python3
"""Resolve primary/secondary Metamod inputs from the validated line manifest.

Output: role, dirname, mode, branch, commit, revision, product version (TSV).
Consumers must capture this command's exit status before reading its output.
"""

import argparse
from pathlib import Path
import sys

import lines


def resolve(data, name):
    aliases = {
        "sm11": "sm11-oldstable", "oldstable": "sm11-oldstable",
        "sm12": "sm12-latest", "latest": "sm12-latest",
        "sm13": "sm13-latest", "bleeding": "sm13-latest",
        "dev": "sm13-dev",
    }
    name = aliases.get(name, name)
    if name not in data["lines"]:
        raise ValueError("unknown build line: " + name)
    line = data["lines"][name]
    rows = []
    for role, key in (("primary", "metamod"), ("secondary", "secondary_metamod")):
        if key not in line:
            continue
        pin = data["pins"][line[key]]
        row = [role, pin["dirname"], pin["mode"], pin["branch"], pin["commit"],
               str(pin["rev"]), lines.mm_version(pin["mode"])]
        if any("\t" in field or "\r" in field or "\n" in field for field in row):
            raise ValueError("invalid TSV field in " + line[key])
        rows.append("\t".join(row))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("line")
    parser.add_argument("--manifest", type=Path,
                        default=Path(__file__).resolve().parent / "lines.json")
    args = parser.parse_args()
    try:
        rows = resolve(lines.load_manifest(args.manifest), args.line)
    except (ValueError, KeyError, OSError) as error:
        print("FAIL: cannot resolve Metamod pins: " + str(error), file=sys.stderr)
        return 1
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
