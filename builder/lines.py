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
        allowed = {"sourcemod", "metamod", "status", "pointer", "role", "extra_tags"}
        require(set(line) <= allowed, "unknown fields on line " + name)
        require(isinstance(line.get("pointer", False), bool), name + ".pointer must be a bool")
        if "role" in line:
            require(isinstance(line["role"], str) and line["role"].strip(),
                    name + ".role must be a nonempty string")
        for tag in line.get("extra_tags", []):
            require(isinstance(tag, str) and re.fullmatch(r"[A-Za-z0-9._-]+", tag),
                    "invalid extra tag on " + name)
        for component, prefix in (("sourcemod", "SM_"), ("metamod", "MM_")):
            ref = line[component]
            require(ref in pins and ref.startswith(prefix), "invalid pin reference for " + name)
    require(isinstance(data["known_bad"], dict), "known_bad must map release tags to reasons")
    for tag, reason in data["known_bad"].items():
        require(isinstance(reason, str) and reason.strip(), "missing known_bad reason for " + tag)
    return data


def mm_version(mode):
    return {"1.10": "1.10.7", "1.11": "1.11.0", "1.12": "1.12.0", "2.0": "2.0.0"}[mode]


def mm_tag_part(name, mode):
    if mode == "1.10":
        return "mm1.10.7"
    if mode == "1.12":
        return "mm1.12.0"
    if mode == "2.0" and "khook" in name:
        return "mm2.0.0-khook"
    if mode == "2.0":
        return "mm2.0.0"
    raise ValueError("unsupported metamod mode for " + name)


def line_parts(data, name):
    line = data["lines"][name]
    sm = data["pins"][line["sourcemod"]]
    mm = data["pins"][line["metamod"]]
    sm_version = "1.{}.0.{}".format(sm["major"], sm["rev"])
    sm_commit = sm.get("build_commit", sm["commit"])
    return {
        "line": name,
        "status": line["status"],
        "pointer": bool(line.get("pointer", False)),
        "role": line.get("role", line["status"]),
        "sm_expect": sm_version,
        "mm_expect": mm_version(mm["mode"]),
        "sm_commit": sm_commit,
        "mm_commit": mm["commit"],
        "sm_short": sm_commit[:8],
        "mm_short": mm["commit"][:8],
        "mm_rev": mm["rev"],
        "mm_mode": mm["mode"],
        "tag": "{}-{}".format(sm_version, mm_tag_part(name, mm["mode"])),
        "extra_tags": list(line.get("extra_tags", [])),
        "default": name == data["default_line"],
    }


def ci_rows(data):
    return [line_parts(data, name) for name, line in data["lines"].items()
            if line["status"] == "active"]


def row_expect(row, with_commits):
    item = {"line": row["line"], "sm_expect": row["sm_expect"], "mm_expect": row["mm_expect"]}
    if with_commits:
        item["sm_commit"] = row["sm_commit"]
        item["mm_commit"] = row["mm_commit"]
    return item


def ci_matrix(data):
    rows = ci_rows(data)
    default = line_parts(data, data["default_line"])
    require(default["status"] == "active", "default_line must be an active CI line")
    debian = []
    for row in rows:
        item = row_expect(row, True)
        item["image"] = "debian:11"
        debian.append(item)
    latest = row_expect(default, True)
    latest["image"] = "debian:latest"
    debian.append(latest)
    rhel = row_expect(default, True)
    rhel["image"] = "rockylinux:9"
    release = []
    for row in rows:
        if row["mm_mode"] != "1.12":
            continue
        release.append({
            "line": row["line"],
            "tag": row["tag"],
            "sm_asset": "sourcemod-{}-git{}-css34-linux.tar.gz".format(
                row["sm_expect"].rsplit(".", 1)[0], row["sm_expect"].rsplit(".", 1)[1]),
            "mm_asset": "mmsource-{}-dev-css34-linux.tar.gz".format(row["mm_expect"]),
            "sm_expect": row["sm_expect"],
            "mm_expect": row["mm_expect"],
        })
    return {
        "build": [row_expect(row, True) for row in rows],
        "debian": debian,
        "botplay": [row_expect(row, False) for row in rows],
        "rhel": [rhel],
        "host": [row_expect(default, True)],
        "windows": [{
            **row_expect(default, False),
            "exts": "CS Tools,SDK Tools,BinTools",
            "load_exts": "",
        }],
        "release_botplay": release,
        "botplay_extra": {
            "image": ["debian:11", "debian:12", "rockylinux:9"],
            "line": [default["line"]],
            "include": [
                {"image": "debian:11", "image_id": "debian11"},
                {"image": "debian:12", "image_id": "debian12"},
                {"image": "rockylinux:9", "image_id": "rocky9"},
                row_expect(default, False),
            ],
        },
    }


def render_ci_matrix(data):
    return json.dumps(ci_matrix(data), indent=2) + "\n"


def render_tag_map(data):
    rows = ["# Generated from builder/lines.json; DO NOT EDIT.",
            "# Regenerate with: python3 builder/lines.py gen",
            "css34_line_for_tag() {",
            "  case \"$1\" in"]
    for name in data["lines"]:
        part = line_parts(data, name)
        tags = [part["tag"]] + part["extra_tags"]
        pattern = "|".join(tags)
        rows.append("    {}) printf '%s\\n' {} ;;".format(pattern, name))
    rows.extend([
        "    *) return 1 ;;",
        "  esac",
        "}",
        "",
        "css34_line_has_pointer() {",
        "  case \"$1\" in",
    ])
    pointers = [name for name, line in data["lines"].items() if line.get("pointer")]
    require(pointers, "at least one line must publish a pointer")
    rows.append("    {}) return 0 ;;".format("|".join(pointers)))
    rows.extend(["    *) return 1 ;;", "  esac", "}", ""])
    return "\n".join(rows)


def render_readme_tables(data):
    install = ["| `<line>` | SourceMod | Metamod | Role |",
               "|----------|-----------|---------|------|"]
    versions = ["| Line (`CSS34_LINE`) | SourceMod | Metamod | Role |",
                "|---------------------|-----------|---------|------|"]
    names = list(data["lines"])
    if data["default_line"] in names:
        names.remove(data["default_line"])
        names.insert(0, data["default_line"])
    for name in names:
        if name == "sm13-dev":
            continue
        part = line_parts(data, name)
        sm = "**{}**".format(part["sm_expect"]) if part["default"] else part["sm_expect"]
        if part["mm_mode"] == "1.12":
            mm = "1.12.0 git{}".format(part["mm_rev"])
        elif part["mm_mode"] == "1.10":
            mm = "1.10-dev git{}".format(part["mm_rev"])
        else:
            mm = "2.0.0 git{}".format(part["mm_rev"])
        if part["mm_mode"] == "2.0" and "khook" in name:
            mm += " (KHook)"
        elif part["mm_mode"] == "2.0":
            mm += " (last SourceHook MM 2.0)"
        if part["pointer"]:
            install.append("| `{}` | {} | {} | {} |".format(name, sm, mm, part["role"]))
        versions.append("| `{}` | {} (`{}…`) | {} (`{}…`) | {} |".format(
            name, sm, part["sm_short"], mm, part["mm_short"], part["role"]))
    return "\n".join(install) + "\n", "\n".join(versions) + "\n"


def replace_block(text, begin, end, body):
    start = text.find(begin)
    stop = text.find(end)
    require(start != -1 and stop != -1 and start < stop, "missing README markers " + begin)
    return text[:start] + begin + "\n" + body + text[stop:]


def render_readme(data, current):
    install, versions = render_readme_tables(data)
    current = replace_block(current, "<!-- lines-install:begin -->", "<!-- lines-install:end -->", install)
    return replace_block(current, "<!-- lines-versions:begin -->", "<!-- lines-versions:end -->", versions)


def render(data):
    rows = ["# Generated from builder/lines.json; DO NOT EDIT.",
            "# Regenerate with: python3 builder/lines.py gen", ""]
    for prefix, fields in data["pins"].items():
        for field, value in fields.items():
            rows.append("{}={}".format(prefix + "_" + field.upper(), shlex.quote(str(value))))
        rows.append("")
    rows.append("CSS34_LINE=${CSS34_LINE:-" + data["default_line"] + "}")
    return "\n".join(rows) + "\n"


GENERATED = (
    ("builder/versions.env", "versions"),
    ("builder/generated/ci-matrix.json", "matrix"),
    ("builder/generated/tag-map.sh", "tags"),
    ("README.md", "readme"),
)


def generated_text(data, kind, current=""):
    if kind == "versions":
        return render(data)
    if kind == "matrix":
        return render_ci_matrix(data)
    if kind == "tags":
        return render_tag_map(data)
    if kind == "readme":
        return render_readme(data, current)
    raise ValueError(kind)


def emit_gha(data):
    matrix = ci_matrix(data)
    for key in ("build", "debian", "botplay", "rhel", "host", "windows", "release_botplay", "botplay_extra"):
        print("{}<<EOF".format(key))
        print(json.dumps(matrix[key], separators=(",", ":")))
        print("EOF")
    print("default_line={}".format(data["default_line"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("gen", "check", "gha"))
    args = parser.parse_args()
    try:
        data = load_manifest(ROOT / "builder/lines.json")
        if args.command == "gha":
            emit_gha(data)
            return 0
        stale = False
        for relative, kind in GENERATED:
            path = ROOT / relative
            current = path.read_text(encoding="utf-8") if kind == "readme" else ""
            expected = generated_text(data, kind, current)
            if args.command == "gen":
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(expected, encoding="utf-8")
                print("Generated " + relative)
                continue
            actual = path.read_text(encoding="utf-8")
            if actual != expected:
                stale = True
                sys.stderr.writelines(difflib.unified_diff(
                    actual.splitlines(keepends=True), expected.splitlines(keepends=True),
                    fromfile=relative, tofile="generated " + relative))
                print("FAIL: stale {}; run python3 builder/lines.py gen".format(relative),
                      file=sys.stderr)
        if args.command == "gen":
            return 0
        if stale:
            return 1
        print("OK: generated files match builder/lines.json", flush=True)
        return subprocess.run(["bash", str(ROOT / "testing/scripts/check-version-copies.sh")],
                              cwd=ROOT).returncode
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
