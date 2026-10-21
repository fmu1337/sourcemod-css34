#!/usr/bin/env python3
"""Generate shell pins, CI matrices, the release tag map, and README tables.

No third-party dependencies. `gen` rewrites the generated copies, `check`
fails when they drift, and `gha` prints GitHub Actions outputs.
"""

import argparse
import difflib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

LINE_FIELDS = {
    "sourcemod", "metamod", "status", "pointer", "releasable", "role",
    "install_role", "extra_tags", "smoke", "rhel_image", "host_smoke",
    "windows", "botplay_extra_images", "sm_note", "mm_note",
}
GENERATED = (
    ("builder/versions.env", "versions"),
    ("builder/generated/ci-matrix.json", "matrix"),
    ("builder/generated/tag-map.sh", "tags"),
    ("README.md", "readme"),
)
WINDOWS_EXTS = "CS Tools,SDK Tools,BinTools"
IMAGE_RE = re.compile(r"[a-z0-9][a-z0-9._:/-]*")
TAG_RE = re.compile(r"[A-Za-z0-9._-]+")


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
        require(set(line) <= LINE_FIELDS, "unknown fields on line " + name)
        require(isinstance(line.get("pointer", False), bool), name + ".pointer must be a bool")
        require(isinstance(line.get("releasable", True), bool), name + ".releasable must be a bool")
        require(isinstance(line.get("host_smoke", False), bool), name + ".host_smoke must be a bool")
        require(isinstance(line.get("windows", False), bool), name + ".windows must be a bool")
        for key in ("role", "install_role", "sm_note", "mm_note", "rhel_image"):
            if key in line:
                require(isinstance(line[key], str) and line[key].strip() and "\n" not in line[key],
                        name + "." + key + " must be a nonempty single-line string")
        if "rhel_image" in line:
            require(IMAGE_RE.fullmatch(line["rhel_image"]), "invalid rhel image on " + name)
        for tag in line.get("extra_tags", []):
            require(isinstance(tag, str) and TAG_RE.fullmatch(tag), "invalid extra tag on " + name)
        images = []
        for entry in line.get("smoke", []):
            require(isinstance(entry, dict) and set(entry) <= {"image", "allow_failure"},
                    "invalid smoke entry on " + name)
            image = entry["image"]
            require(isinstance(image, str) and IMAGE_RE.fullmatch(image),
                    "invalid smoke image on " + name)
            require(image != "debian:latest",
                    name + " must not list debian:latest (it duplicates debian:13)")
            require(image not in images, name + " lists image " + image + " twice")
            images.append(image)
            if "allow_failure" in entry:
                require(isinstance(entry["allow_failure"], bool),
                        name + " allow_failure for " + image + " must be a bool")
        if "rhel_image" in line and line["rhel_image"] in images:
            raise ValueError(name + " lists image " + line["rhel_image"] + " twice")
        for entry in line.get("botplay_extra_images", []):
            require(isinstance(entry, dict) and set(entry) == {"image", "image_id"},
                    "invalid botplay_extra image on " + name)
            require(IMAGE_RE.fullmatch(entry["image"]), "invalid botplay_extra image on " + name)
            require(re.fullmatch(r"[a-z0-9]+", entry["image_id"]),
                    "invalid botplay_extra image_id on " + name)
        if line["status"] == "active":
            require(line.get("smoke"), "active line " + name + " needs smoke images")
        for component, prefix in (("sourcemod", "SM_"), ("metamod", "MM_")):
            ref = line[component]
            require(ref in pins and ref.startswith(prefix), "invalid pin reference for " + name)
    require(isinstance(data["known_bad"], dict), "known_bad must map release tags to reasons")
    for tag, reason in data["known_bad"].items():
        require(TAG_RE.fullmatch(tag), "invalid known_bad tag " + tag)
        require(isinstance(reason, str) and reason.strip(), "missing known_bad reason for " + tag)
    require(line_parts(data, data["default_line"])["status"] == "active",
            "default_line must be an active CI line")
    for name in lines:
        part = line_parts(data, name)
        for tag in [part["tag"]] + part["extra_tags"]:
            if tag in data["known_bad"] and part["pointer"]:
                raise ValueError("known-bad tag " + tag + " is pinned on pointer line " + name)
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
        "releasable": bool(line.get("releasable", True)),
        "role": line.get("role", line["status"]),
        "install_role": line.get("install_role", line.get("role", line["status"])),
        "sm_note": line.get("sm_note", ""),
        "mm_note": line.get("mm_note", ""),
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


def active_rows(data):
    return [line_parts(data, name) for name, line in data["lines"].items()
            if line["status"] == "active"]


def row_expect(row, with_commits):
    item = {"line": row["line"], "sm_expect": row["sm_expect"], "mm_expect": row["mm_expect"]}
    if with_commits:
        item["sm_commit"] = row["sm_commit"]
        item["mm_commit"] = row["mm_commit"]
    return item


def debian_rows(data):
    """Image-major order: every active line for debian:11, then ubuntu:24.04, then debian:13."""
    order = []
    by_image = {}
    for name, line in data["lines"].items():
        if line["status"] != "active":
            continue
        part = line_parts(data, name)
        for entry in line["smoke"]:
            image = entry["image"]
            if image not in by_image:
                order.append(image)
                by_image[image] = []
            item = row_expect(part, True)
            item["image"] = image
            item["allow_failure"] = bool(entry.get("allow_failure", False))
            by_image[image].append(item)
    rows = []
    for image in order:
        rows.extend(by_image[image])
    return rows


def ci_matrix(data):
    rows = active_rows(data)
    default = line_parts(data, data["default_line"])
    rhel = []
    host = []
    windows = []
    for name, line in data["lines"].items():
        part = line_parts(data, name)
        if line.get("rhel_image"):
            item = row_expect(part, True)
            item["image"] = line["rhel_image"]
            rhel.append(item)
        if line.get("host_smoke"):
            host.append(row_expect(part, True))
        if line.get("windows"):
            item = row_expect(part, False)
            item["exts"] = WINDOWS_EXTS
            item["load_exts"] = ""
            windows.append(item)
    require(rhel and host and windows, "rhel, host, and windows matrices must be non-empty")
    release = []
    for row in rows:
        if row["mm_mode"] != "1.12":
            continue
        base, rev = row["sm_expect"].rsplit(".", 1)
        release.append({
            "line": row["line"],
            "tag": row["tag"],
            "sm_asset": "sourcemod-{}-git{}-css34-linux.tar.gz".format(base, rev),
            "mm_asset": "mmsource-{}-dev-css34-linux.tar.gz".format(row["mm_expect"]),
            "sm_expect": row["sm_expect"],
            "mm_expect": row["mm_expect"],
        })
    require(release, "release botplay matrix must be non-empty")
    return {
        "build": [row_expect(row, True) for row in rows],
        "debian": debian_rows(data),
        "botplay": [row_expect(row, False) for row in rows],
        "rhel": rhel,
        "host": host,
        "windows": windows,
        "release_botplay": release,
        "botplay_extra": botplay_extra_matrix(data),
    }


def botplay_extra_matrix(data):
    chosen = []
    images = None
    for name, line in data["lines"].items():
        extra = line.get("botplay_extra_images")
        if not extra:
            continue
        if images is None:
            images = extra
        elif extra != images:
            raise ValueError("botplay_extra_images must match across lines")
        chosen.append(name)
    require(chosen, "botplay_extra matrix is empty")
    include = [{"image": item["image"], "image_id": item["image_id"]} for item in images]
    for name in chosen:
        include.append(row_expect(line_parts(data, name), False))
    return {
        "image": [item["image"] for item in images],
        "line": chosen,
        "include": include,
    }


def render_ci_matrix(data):
    return json.dumps(ci_matrix(data), indent=2) + "\n"


def shell_case_arm(pattern, body):
    return "    {}) {} ;;".format(pattern, body)


def render_tag_map(data):
    rows = ["# Generated from builder/lines.json; DO NOT EDIT.",
            "# Regenerate with: python3 builder/lines.py gen",
            "css34_line_for_tag() {",
            '  case "$1" in']
    for name in data["lines"]:
        part = line_parts(data, name)
        pattern = "|".join([part["tag"]] + part["extra_tags"])
        rows.append(shell_case_arm(pattern, "printf '%s\\n' " + name))
    rows.extend([
        "    *) return 1 ;;",
        "  esac",
        "}",
        "",
        "css34_line_has_pointer() {",
        '  case "$1" in',
    ])
    pointers = [name for name, line in data["lines"].items() if line.get("pointer")]
    require(pointers, "at least one line must publish a pointer")
    rows.append(shell_case_arm("|".join(pointers), "return 0"))
    rows.extend(["    *) return 1 ;;", "  esac", "}", ""])
    blocked = [name for name, line in data["lines"].items() if not line.get("releasable", True)]
    rows.extend(["css34_line_can_release() {", '  case "$1" in'])
    if blocked:
        rows.append(shell_case_arm("|".join(blocked), "return 1"))
    rows.extend(["    *) return 0 ;;", "  esac", "}", ""])
    rows.extend(["css34_tag_is_known_bad() {", '  case "$1" in'])
    known = sorted(data["known_bad"])
    require(known, "known_bad must not be empty")
    rows.append(shell_case_arm("|".join(known), "return 0"))
    rows.extend(["    *) return 1 ;;", "  esac", "}", ""])
    return "\n".join(rows)


def mm_text(part, style):
    if part["mm_mode"] == "1.10":
        text = "1.10-dev git{}".format(part["mm_rev"])
    elif part["mm_mode"] == "1.12":
        text = "1.12.0 git{}" if style == "install" else "1.12 git{}"
        text = text.format(part["mm_rev"])
    else:
        text = "2.0.0 git{}" if style == "install" else "2.0 git{}"
        text = text.format(part["mm_rev"])
    if part["mm_note"]:
        text += " " + part["mm_note"]
    return text


def version_names(data):
    return [name for name in data["lines"] if name != "sm13-dev"]


def install_names(data):
    preferred = [data["default_line"], "sm12-latest", "sm13-mm20-khook", "sm13-mm20"]
    names = []
    for name in preferred + list(data["lines"]):
        if name in names or name not in data["lines"] or name == "sm13-dev":
            continue
        if data["lines"][name].get("pointer"):
            names.append(name)
    return names


def render_readme_tables(data):
    install = ["| `<line>` | SourceMod | Metamod | Role |",
               "|----------|-----------|---------|------|"]
    for name in install_names(data):
        part = line_parts(data, name)
        sm = part["sm_expect"]
        if part["sm_note"]:
            sm += " " + part["sm_note"]
        install.append("| `{}` | {} | {} | {} |".format(
            name, sm, mm_text(part, "install"), part["install_role"]))
    versions = ["| Line (`CSS34_LINE`) | SourceMod | Metamod | Role |",
                "|---------------------|-----------|---------|------|"]
    for name in version_names(data):
        part = line_parts(data, name)
        sm = part["sm_expect"]
        mm = mm_text(part, "version")
        if part["status"] != "retired":
            sm = "**{}**".format(sm)
            mm = "**{}**".format(mm)
        if part["sm_note"]:
            sm += " " + part["sm_note"]
        versions.append("| `{}` | {} (`{}…`) | {} (`{}…`) | {} |".format(
            name, sm, part["sm_short"], mm, part["mm_short"], part["role"]))
    return "\n".join(install) + "\n", "\n".join(versions) + "\n"


def replace_block(text, begin, end, body):
    start = text.find(begin)
    stop = text.find(end)
    require(start != -1 and stop > start, "missing README markers " + begin)
    return text[:start] + begin + "\n" + body + text[stop:]


def render_readme(data, current):
    install, versions = render_readme_tables(data)
    current = replace_block(current, "<!-- lines-install:begin -->", "<!-- lines-install:end -->", install)
    return replace_block(current, "<!-- lines-versions:begin -->", "<!-- lines-versions:end -->", versions)


def render_versions(data):
    rows = ["# Generated from builder/lines.json; DO NOT EDIT.",
            "# Regenerate with: python3 builder/lines.py gen", ""]
    for prefix, fields in data["pins"].items():
        for field, value in fields.items():
            rows.append("{}={}".format(prefix + "_" + field.upper(), shlex.quote(str(value))))
        rows.append("")
    rows.append("CSS34_LINE=${CSS34_LINE:-" + data["default_line"] + "}")
    return "\n".join(rows) + "\n"


def generated_text(data, kind, current=""):
    if kind == "versions":
        return render_versions(data)
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
        planned = []
        for relative, kind in GENERATED:
            path = ROOT / relative
            current = path.read_text(encoding="utf-8") if kind == "readme" else ""
            planned.append((relative, path, generated_text(data, kind, current)))
        if args.command == "gen":
            for relative, path, expected in planned:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(expected, encoding="utf-8")
                print("Generated " + relative)
            return 0
        stale = False
        for relative, path, expected in planned:
            actual = path.read_text(encoding="utf-8")
            if actual != expected:
                stale = True
                sys.stderr.writelines(difflib.unified_diff(
                    actual.splitlines(keepends=True), expected.splitlines(keepends=True),
                    fromfile=relative, tofile="generated " + relative))
                print("FAIL: stale {}; run python3 builder/lines.py gen".format(relative),
                      file=sys.stderr)
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
