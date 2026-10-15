#!/usr/bin/env python3
"""Generate shell pins and check their existing consumers (no third-party deps)."""

import argparse
import difflib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_manifest(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    require(data["schema_version"] == 1, "unsupported schema_version")
    pins = data["pins"]
    require(isinstance(pins, dict) and pins, "pins must be a nonempty object")
    for prefix, fields in pins.items():
        require(re.fullmatch(r"(?:SM|MM)_[A-Z0-9_]+", prefix),
                "invalid pin prefix: " + prefix)
        required = {"commit", "rev", "major"} if prefix.startswith("SM_") else {
            "commit", "rev", "branch", "dirname", "mode"}
        optional = {"branch", "merge_master", "build_commit"} if prefix.startswith("SM_") else set()
        require(required <= fields.keys() <= required | optional,
                "missing or unknown fields in " + prefix)
        for field, value in fields.items():
            label = prefix + "." + field
            if field in {"rev", "major"}:
                require(type(value) is int and value > 0, label + " must be a positive integer")
            else:
                require(isinstance(value, str) and value and "\n" not in value,
                        label + " must be a nonempty single-line string")
                if field in {"commit", "merge_master", "build_commit"}:
                    require(re.fullmatch(r"[0-9a-f]{40}", value), label + " must be a full SHA")
    lines = data["lines"]
    require(data["default_line"] in lines, "default_line must name a line")
    for name, line in lines.items():
        require(re.fullmatch(r"[a-z0-9-]+", name), "invalid line name: " + name)
        require(line["status"] in {"active", "experimental", "retired", "frozen"},
                "invalid status for " + name)
        for component, prefix in (("sourcemod", "SM_"), ("metamod", "MM_")):
            ref = line[component]
            require(ref in pins and ref.startswith(prefix), "invalid pin reference for " + name)
    require(isinstance(data["known_bad"], dict), "known_bad must map release tags to reasons")
    for tag, reason in data["known_bad"].items():
        require(isinstance(reason, str) and reason.strip(), "missing known_bad reason for " + tag)
    return data


def render(data):
    rows = ["# Generated from builder/lines.json; DO NOT EDIT.",
            "# Regenerate with: python3 builder/lines.py gen", ""]
    for prefix, fields in data["pins"].items():
        for field, value in fields.items():
            rows.append("{}={}".format(prefix + "_" + field.upper(), shlex.quote(str(value))))
        rows.append("")
    rows.append("CSS34_LINE=${CSS34_LINE:-" + data["default_line"] + "}")
    return "\n".join(rows) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("gen", "check"))
    args = parser.parse_args()
    target = ROOT / "builder/versions.env"
    try:
        expected = render(load_manifest(ROOT / "builder/lines.json"))
        if args.command == "gen":
            target.write_text(expected, encoding="utf-8")
            print("Generated builder/versions.env")
            return 0
        actual = target.read_text(encoding="utf-8")
        if actual != expected:
            sys.stderr.writelines(difflib.unified_diff(
                actual.splitlines(keepends=True), expected.splitlines(keepends=True),
                fromfile="builder/versions.env", tofile="generated versions.env"))
            print("FAIL: stale versions.env; run python3 builder/lines.py gen", file=sys.stderr)
            return 1
        print("OK: builder/versions.env matches builder/lines.json", flush=True)
        # Keep the existing cross-file checks until T4.1 generates these copies.
        return subprocess.run(["bash", str(ROOT / "testing/scripts/check-version-copies.sh")],
                              cwd=ROOT).returncode
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
