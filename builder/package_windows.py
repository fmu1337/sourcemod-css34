#!/usr/bin/env python3
"""Package Windows SourceMod and Metamod trees into zip archives.

Zip members use '/' separators (Python zipfile). Each archive contains
addons/*/css34-package.json. Asset names carry the lines.json revision:

  sourcemod-<product>-git<sm_rev>-css34-windows.zip
  mmsource-<product>-git<mm_rev>-css34-windows.zip
"""

import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from contextlib import redirect_stderr
from pathlib import Path

BUILDER = Path(__file__).resolve().parent
REV_RE = re.compile(r"^[0-9]+$")
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)+$")
SM_NAME_RE = re.compile(r"^sourcemod-.+-git[0-9]+-css34-windows\.zip$")
MM_NAME_RE = re.compile(r"^mmsource-.+-git[0-9]+-css34-windows\.zip$")


def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    raise SystemExit(1)


def read_product(path):
    text = path.read_text(encoding="utf-8").strip()
    if not text or "\n" in text:
        fail("bad product.version: " + str(path))
    return text


def require_rev(name):
    rev = os.environ.get(name, "")
    if not REV_RE.fullmatch(rev):
        fail(name + " must be the lines.json revision (digits), got " + repr(rev))
    return rev


def sm_filename(product, rev):
    return "sourcemod-{}-git{}-css34-windows.zip".format(product.strip(), rev)


def mm_filename(product, rev):
    # "1.12.0-dev" → mmsource-1.12.0-git<rev>-css34-windows.zip
    base = product.split("-", 1)[0]
    return "mmsource-{}-git{}-css34-windows.zip".format(base, rev)


def zip_tree(root, archive):
    archive = Path(archive)
    if archive.exists():
        archive.unlink()
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(p for p in root.rglob("*") if p.is_file()):
            zf.write(path, path.relative_to(root).as_posix())
    return archive


def require_files(root, relative):
    missing = [rel for rel in relative if not (root / rel).is_file()]
    if missing:
        fail("missing package files: " + ", ".join(missing))


def rewrite_metamod_vdf(staging):
    vdf = staging / "addons" / "metamod.vdf"
    if not vdf.is_file():
        return
    text = vdf.read_text(encoding="utf-8")
    new, count = re.subn(
        r'"file"\s+"addons/metamod/bin/server"',
        '"file"\t"../cstrike/addons/metamod/bin/server"',
        text,
        count=1,
    )
    if count != 1:
        fail("metamod.vdf has no gameinfo file path to rewrite")
    vdf.write_text(new, encoding="utf-8", newline="\n")


def write_manifest(out_path, metamod_binary):
    script = BUILDER / "write-package-manifest.sh"
    subprocess.run(
        ["bash", str(script), str(out_path), metamod_binary],
        check=True,
    )


def core_name(package_dir, folder, candidates):
    for name in candidates:
        if (package_dir / folder / name).is_file():
            return name
    fail("missing " + " / ".join(candidates))


def stage_addons(package_dir, include_cfg):
    staging = Path(tempfile.mkdtemp(prefix="css34-winpkg-"))
    shutil.copytree(package_dir / "addons", staging / "addons")
    if include_cfg:
        shutil.copytree(package_dir / "cfg", staging / "cfg")
    return staging


def package_metamod(package_dir, output_dir, mms_dir):
    package_dir = Path(package_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    mm_core = core_name(
        package_dir,
        Path("addons/metamod/bin"),
        ("metamod.2.ep1.dll", "metamod.1.ep1.dll"),
    )
    require_files(package_dir, [
        "addons/metamod.vdf",
        "addons/metamod/bin/" + mm_core,
        "addons/metamod/bin/server.dll",
    ])
    product = read_product(Path(mms_dir) / "product.version")
    rev = require_rev("MMS_GIT_REV")
    archive = output_dir / mm_filename(product, rev)
    staging = stage_addons(package_dir, include_cfg=False)
    try:
        rewrite_metamod_vdf(staging)
        write_manifest(
            staging / "addons/metamod/css34-package.json",
            mm_core[:-4],
        )
        require_files(staging, ["addons/metamod/css34-package.json"])
        zip_tree(staging, archive)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    print(archive.resolve().as_posix())
    return archive


def package_sourcemod(package_dir, output_dir, sourcemod_dir):
    package_dir = Path(package_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    has2 = (package_dir / "addons/sourcemod/bin/sourcemod.2.ep1.dll").is_file()
    has1 = (package_dir / "addons/sourcemod/bin/sourcemod.1.ep1.dll").is_file()
    if has2:
        core = "sourcemod.2.ep1.dll"
        cstrike = "game.cstrike.ext.2.ep1.dll"
        sdkhooks = "sdkhooks.ext.2.ep1.dll"
        mm_binary = "metamod.2.ep1"
    elif has1:
        core = "sourcemod.1.ep1.dll"
        cstrike = "game.cstrike.ext.1.ep1.dll"
        sdkhooks = "sdkhooks.ext.1.ep1.dll"
        mm_binary = "metamod.1.ep1"
    else:
        fail("missing sourcemod.1.ep1.dll / sourcemod.2.ep1.dll")
    required = [
        "addons/metamod/sourcemod.vdf",
        "addons/sourcemod/bin/" + core,
        "addons/sourcemod/extensions/dbi.mysql.ext.dll",
        "addons/sourcemod/extensions/dbi.sqlite.ext.dll",
        "addons/sourcemod/extensions/" + cstrike,
        "addons/sourcemod/extensions/" + sdkhooks,
        "addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt",
        "addons/sourcemod/scripting/include/version_auto.inc",
        "cfg/sourcemod/sourcemod.cfg",
    ]
    major = os.environ.get("SOURCEMOD_MAJOR", "")
    if major.isdigit() and int(major) >= 12:
        required.append("addons/sourcemod/extensions/dhooks.ext.dll")
    require_files(package_dir, required)
    product = read_product(Path(sourcemod_dir) / "product.version")
    rev = require_rev("SOURCEMOD_GIT_REV")
    archive = output_dir / sm_filename(product, rev)
    staging = stage_addons(package_dir, include_cfg=True)
    try:
        write_manifest(staging / "addons/sourcemod/css34-package.json", mm_binary)
        require_files(staging, ["addons/sourcemod/css34-package.json"])
        zip_tree(staging, archive)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    print(archive.resolve().as_posix())
    return archive


def archive_names(path):
    with zipfile.ZipFile(path) as zf:
        return zf.namelist()


def manifest_bytes(path, suffix):
    with zipfile.ZipFile(path) as zf:
        matches = [name for name in zf.namelist() if name.endswith(suffix)]
        if len(matches) != 1:
            fail(path.name + " manifest count for " + suffix + ": " + str(matches))
        return zf.read(matches[0])


def check_archive(path):
    path = Path(path)
    if not path.is_file():
        fail("not a file: " + str(path))
    name = path.name
    if name.startswith("sourcemod-"):
        if not SM_NAME_RE.fullmatch(name):
            fail("SourceMod asset name must carry the revision: " + name)
        manifest_suffix = "addons/sourcemod/css34-package.json"
    elif name.startswith("mmsource-"):
        if not MM_NAME_RE.fullmatch(name):
            fail("Metamod asset name must carry the revision: " + name)
        manifest_suffix = "addons/metamod/css34-package.json"
    else:
        fail("unexpected windows asset: " + name)
    try:
        names = archive_names(path)
    except zipfile.BadZipFile as error:
        fail(name + " is not a zip: " + str(error))
    bad = [item for item in names if "\\" in item or item.startswith("/") or ".." in item.split("/")]
    if bad:
        fail(name + " has non-POSIX member names: " + ", ".join(bad[:5]))
    if manifest_suffix not in names:
        fail(name + " missing " + manifest_suffix)
    data = json.loads(manifest_bytes(path, manifest_suffix))
    for key in ("msvc_toolset", "windows_sdk"):
        value = data.get(key, "")
        if not isinstance(value, str) or not VERSION_RE.fullmatch(value):
            fail(name + " css34-package.json " + key + "=" + repr(value))
    print("OK: {} ({} members, msvc_toolset={}, windows_sdk={})".format(
        name, len(names), data["msvc_toolset"], data["windows_sdk"]))
    print_listing(path, names)


def print_listing(path, names):
    """Same member names `unzip -l` shows, one per line, for the CI log."""
    print("---- unzip -l {} ----".format(path.name))
    for item in names:
        print(item)
    print("---- end {} ----".format(path.name))


def self_test():
    pin = (BUILDER / "windows-toolchain.env").read_text(encoding="utf-8")
    prefix = "MSVC_TOOLSET_PREFIX=14.44"
    sdk = "WINDOWS_SDK_PIN=10.0.26100.0"
    if prefix not in pin or sdk not in pin:
        fail("windows-toolchain.env pin changed; update the workflows with it")
    for relative in (".github/workflows/build.yml", ".github/workflows/release.yml"):
        text = (BUILDER.parent / relative).read_text(encoding="utf-8")
        if "runs-on: windows-2022" not in text:
            fail(relative + " must run on windows-2022")
        if 'toolset: "14.44"' not in text or "sdk: 10.0.26100.0" not in text:
            fail(relative + " must pass -vcvars_ver=14.44 and Windows SDK 10.0.26100.0")
    if mm_filename("1.12.0-dev", "1226") != "mmsource-1.12.0-git1226-css34-windows.zip":
        fail("mm filename")
    if sm_filename("1.13.0", "7472") != "sourcemod-1.13.0-git7472-css34-windows.zip":
        fail("sm filename")
    with tempfile.TemporaryDirectory(prefix="css34-winpkg-test-") as tmp:
        tmp = Path(tmp)
        sm_src = tmp / "sourcemod"
        mm_src = tmp / "mmsource"
        sm_pkg = tmp / "sm-package"
        mm_pkg = tmp / "mm-package"
        out = tmp / "out"
        (sm_src).mkdir()
        (mm_src).mkdir()
        (sm_src / "product.version").write_text("1.13.0\n", encoding="utf-8")
        (mm_src / "product.version").write_text("1.12.0-dev\n", encoding="utf-8")
        ext = sm_src / "public"
        ext.mkdir()
        (ext / "IExtensionSys.h").write_text(
            "#define SMINTERFACE_EXTENSIONAPI_VERSION 9\n"
            "#define SMINTERFACE_EXTENSIONAPI_VERSION_MIN 7\n",
            encoding="utf-8",
        )
        for rel in (
            "addons/metamod/sourcemod.vdf",
            "addons/sourcemod/bin/sourcemod.2.ep1.dll",
            "addons/sourcemod/extensions/dbi.mysql.ext.dll",
            "addons/sourcemod/extensions/dbi.sqlite.ext.dll",
            "addons/sourcemod/extensions/game.cstrike.ext.2.ep1.dll",
            "addons/sourcemod/extensions/sdkhooks.ext.2.ep1.dll",
            "addons/sourcemod/extensions/dhooks.ext.dll",
            "addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt",
            "addons/sourcemod/scripting/include/version_auto.inc",
            "cfg/sourcemod/sourcemod.cfg",
        ):
            path = sm_pkg / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("x", encoding="utf-8")
        (mm_pkg / "addons/metamod.vdf").parent.mkdir(parents=True, exist_ok=True)
        (mm_pkg / "addons/metamod.vdf").write_text(
            '"file" "addons/metamod/bin/server"\n', encoding="utf-8")
        for rel in ("addons/metamod/bin/metamod.2.ep1.dll", "addons/metamod/bin/server.dll"):
            path = mm_pkg / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"MZ")
        env = os.environ.copy()
        env.update({
            "SOURCEMOD_DIR": str(sm_src),
            "SOURCEMOD_GIT_REV": "7472",
            "SOURCEMOD_COMMIT": "a" * 40,
            "SOURCEMOD_MAJOR": "13",
            "MMS_DIR": str(mm_src),
            "MMS_GIT_REV": "1226",
            "MMS_COMMIT": "b" * 40,
            "CSS34_LINE": "sm13-latest",
            "BUILD_PLATFORM": "windows",
            "BUILD_DATE": "2026-01-01T00:00:00Z",
            "MSVC_TOOLSET": "14.44.35207",
            "WINDOWS_SDK": "10.0.26100.0",
            "WDIR": str(BUILDER.parent),
        })
        old = os.environ
        os.environ.clear()
        os.environ.update(env)
        try:
            sm_zip = package_sourcemod(sm_pkg, out, sm_src)
            mm_zip = package_metamod(mm_pkg, out, mm_src)
            check_archive(sm_zip)
            check_archive(mm_zip)
            with zipfile.ZipFile(mm_zip) as zf:
                vdf = zf.read("addons/metamod.vdf").decode("utf-8")
            if "../cstrike/addons/metamod/bin/server" not in vdf:
                fail("vdf rewrite missing")
            if "\\" in vdf:
                fail("vdf contains a backslash")
            if shutil.which("unzip"):
                for archive in (sm_zip, mm_zip):
                    listing = subprocess.check_output(["unzip", "-l", str(archive)], text=True)
                    if "\\" in listing:
                        fail("unzip -l shows a backslash in " + archive.name)
                    if "css34-package.json" not in listing:
                        fail("unzip -l missing css34-package.json in " + archive.name)
        finally:
            os.environ.clear()
            os.environ.update(old)
        bad = tmp / "sourcemod-1.13.0-git1-css34-windows.zip"
        with zipfile.ZipFile(bad, "w") as zf:
            info = zipfile.ZipInfo("addons\\sourcemod\\css34-package.json")
            zf.writestr(info, b"{}")
        buf = io.StringIO()
        with redirect_stderr(buf):
            try:
                check_archive(bad)
            except SystemExit:
                if "non-POSIX" not in buf.getvalue():
                    fail("expected non-POSIX rejection, got " + buf.getvalue())
            else:
                fail("backslash zip was accepted")
    print("OK: package_windows self-test")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    meta = sub.add_parser("metamod")
    meta.add_argument("--package-dir", required=True)
    meta.add_argument("--output-dir", required=True)
    meta.add_argument("--mms-dir", required=True)
    sm = sub.add_parser("sourcemod")
    sm.add_argument("--package-dir", required=True)
    sm.add_argument("--output-dir", required=True)
    sm.add_argument("--sourcemod-dir", required=True)
    check = sub.add_parser("check")
    check.add_argument("archives", nargs="+")
    sub.add_parser("self-test")
    args = parser.parse_args(argv)
    if args.cmd == "metamod":
        package_metamod(args.package_dir, args.output_dir, args.mms_dir)
    elif args.cmd == "sourcemod":
        package_sourcemod(args.package_dir, args.output_dir, args.sourcemod_dir)
    elif args.cmd == "check":
        for archive in args.archives:
            check_archive(archive)
    else:
        self_test()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
