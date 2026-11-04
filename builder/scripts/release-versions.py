#!/usr/bin/env python3
"""VERSIONS.txt: the exact versions and files of one release (or of a line pointer).

    python3 builder/scripts/release-versions.py --tag <tag> --sm-linux <tar.gz> --mm-linux <tar.gz>
        [--sm-windows <zip>] [--mm-windows <zip>] [--mm-legacy-linux <tar.gz>]
        [--pointer line-<line>] [--repo owner/name]

Every build release and every line-<line> pointer carries this file next to its
packages, so a script can find the asset names (they carry git<rev>, which moves on
every pin bump) and their sha256 without parsing release notes:

    curl -fsSL .../releases/download/<tag or line-<line>>/VERSIONS.txt

The format is `key=value`, one per line, with `#` comments: `source` it in sh, or
`grep '^sm_linux='`. Versions come from the packages' own css34-package.json.
`stable_*` keys name the fixed alias of each package (the same bytes), uploaded to
every release and served by the line pointers.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import zipfile

STABLE = {
    "sm_linux": "sourcemod-css34-linux.tar.gz",
    "mm_linux": "mmsource-css34-linux.tar.gz",
    "sm_windows": "sourcemod-css34-windows.zip",
    "mm_windows": "mmsource-css34-windows.zip",
    "mm_legacy_linux": "mmsource-legacy-css34-linux.tar.gz",
}
MANIFEST = {
    "sm": "addons/sourcemod/css34-package.json",
    "mm": "addons/metamod/css34-package.json",
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest(path, member):
    path = str(path)
    try:
        if path.endswith(".zip"):
            with zipfile.ZipFile(path) as zf:
                return json.loads(zf.read(member).decode("utf-8"))
        with tarfile.open(path, "r:gz") as tf:
            fh = tf.extractfile(member)
            return json.load(io.TextIOWrapper(fh, encoding="utf-8"))
    except (KeyError, OSError, ValueError, tarfile.TarError, zipfile.BadZipFile) as err:
        raise SystemExit("FAIL: {}: no readable {} ({})".format(path, member, err))


def render(tag, files, pointer="", repo="fmu1337/sourcemod-css34"):
    """files: {role: path}; each file is recorded under its own basename."""
    sm = manifest(files["sm_linux"], MANIFEST["sm"])
    mm = manifest(files["mm_linux"], MANIFEST["mm"])
    for key in ("mm_version", "mm_commit"):
        if sm.get(key) != mm.get(key):
            raise SystemExit("FAIL: SM and MM packages disagree on {}: {!r} vs {!r}".format(
                key, sm.get(key), mm.get(key)))
    where = pointer or tag
    out = [
        "# css34 {} {}: exact versions of the packages next to this file.".format(
            "line pointer" if pointer else "release", where),
        "# key=value; `source` it in sh or grep a key. Asset names change with every pin bump,",
        "# the stable_* names never do. Base URL: https://github.com/{}/releases/download/{}/".format(
            repo, where),
        "tag={}".format(tag),
    ]
    if pointer:
        out.append("pointer={}".format(pointer))
    out.append("line={}".format(sm.get("line", "")))
    for key in ("sm_version", "sm_commit", "mm_version", "mm_commit", "metamod_binary",
                "extension_api", "extension_api_min", "min_glibc", "css34_pack_commit", "build_date"):
        if key in sm:
            out.append("{}={}".format(key, sm[key]))
    if "metamod_binaries" in mm:
        out.append("metamod_binaries={}".format(",".join(mm["metamod_binaries"])))
    if "legacy_bridge" in mm:
        out.append("legacy_bridge={}".format("true" if mm["legacy_bridge"] else "false"))
    if files.get("sm_windows"):
        win = manifest(files["sm_windows"], MANIFEST["sm"])
        for key in ("msvc_toolset", "windows_sdk"):
            if key in win:
                out.append("{}={}".format(key, win[key]))
    for role in ("sm_linux", "mm_linux", "mm_legacy_linux", "sm_windows", "mm_windows"):
        path = files.get(role)
        if not path:
            continue
        out.append("{}={}".format(role, os.path.basename(path)))
        out.append("{}_sha256={}".format(role, sha256(path)))
        out.append("stable_{}={}".format(role, STABLE[role]))
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tag", required=True)
    parser.add_argument("--pointer", default="")
    parser.add_argument("--repo", default="fmu1337/sourcemod-css34")
    parser.add_argument("--sm-linux", required=True, type=Path)
    parser.add_argument("--mm-linux", required=True, type=Path)
    parser.add_argument("--mm-legacy-linux", type=Path)
    parser.add_argument("--sm-windows", type=Path)
    parser.add_argument("--mm-windows", type=Path)
    args = parser.parse_args()
    files = {role: getattr(args, role) for role in STABLE if getattr(args, role)}
    sys.stdout.write(render(args.tag, files, args.pointer, args.repo))


if __name__ == "__main__":
    main()
