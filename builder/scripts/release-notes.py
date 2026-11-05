#!/usr/bin/env python3
"""Release notes for a css34 tag, generated from the tag commit's pins (T4.3).

    python3 builder/scripts/release-notes.py <tag> [--repo owner/name] [--commit sha]

Everything comes from files at the tag commit: builder/lines.json (pins, line,
bridge Metamod, known-bad tags), builder/docker/build.sh (Linux build image),
builder/windows-toolchain.env (MSVC toolset and Windows SDK) and
builder/patches/series/ (the patch series the build applied). The tag must be
one lines.json generates (`<sm version>-<mm part>[-rN]`); any other tag fails.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def load_lines(root):
    spec = importlib.util.spec_from_file_location("css34_lines", root / "builder/lines.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    try:
        return mod, mod.load_manifest(root / "builder/lines.json")
    except ValueError as err:
        raise SystemExit("FAIL: builder/lines.json: {}".format(err))


def line_for_tag(mod, data, tag):
    base = re.sub(r"-r[0-9]+$", "", tag)
    for name, line in data["lines"].items():
        part = mod.line_parts(data, name)
        if base == part["tag"] or base in part["extra_tags"]:
            return base, part
    raise SystemExit("FAIL: tag {} matches no line pin in builder/lines.json".format(tag))


def linux_image(root):
    text = (root / "builder/docker/build.sh").read_text()
    match = re.search(r'ML2014_IMAGE:-([^}"]+)', text)
    if not match:
        raise SystemExit("FAIL: no manylinux image in builder/docker/build.sh")
    return match.group(1)


def windows_toolchain(root):
    env = {}
    for raw in (root / "builder/windows-toolchain.env").read_text().splitlines():
        if "=" in raw and not raw.lstrip().startswith("#"):
            key, value = raw.split("=", 1)
            env[key.strip()] = value.strip()
    return env["MSVC_TOOLSET_PREFIX"], env["WINDOWS_SDK_PIN"]


def series_for(root, line, mm_commit):
    found = []
    for manifest in sorted((root / "builder/patches/series").glob("*/series.json")):
        data = json.loads(manifest.read_text())
        if data.get("line") == line or (data.get("root") == "metamod" and data.get("commit") == mm_commit):
            patches = sorted(p for p in manifest.parent.rglob("*.patch"))
            found.append((manifest.parent.name, len(patches)))
    return found


def render(tag, repo, commit, root=ROOT):
    mod, data = load_lines(root)
    base, part = line_for_tag(mod, data, tag)
    name = part["line"]
    line = data["lines"][name]
    if base in data["known_bad"]:
        raise SystemExit("FAIL: {} is known-bad: {}".format(base, data["known_bad"][base]))
    gh = "https://github.com/"
    sm_url = gh + "alliedmodders/sourcemod/commit/" + part["sm_commit"]
    mm_url = gh + "alliedmodders/metamod-source/commit/" + part["mm_commit"]
    msvc, sdk = windows_toolchain(root)
    out = []
    out.append("CS:S v34 (build 4044) packages for `{}`: line `{}` ({}{}).".format(
        tag, name, part["role"],
        ", default line" if part["default"] and "default" not in part["role"] else ""))
    out.append("")
    out.append("Published as a **prerelease**; promoted only after the public-URL smoke "
               "and botplay pass, and only then served by `line-{}`.".format(name)
               if part["pointer"] else
               "Published as a **prerelease**; promoted only after the public-URL smoke "
               "and botplay pass.")
    out.append("")
    out.append("**Pins** (`builder/lines.json`)")
    out.append("")
    out.append("| Component | Version | Upstream commit |")
    out.append("|-----------|---------|-----------------|")
    out.append("| SourceMod | {} | [`{}`]({}) |".format(part["sm_expect"], part["sm_short"], sm_url))
    out.append("| Metamod:Source | {} git{} | [`{}`]({}) |".format(
        part["mm_expect"], part["mm_rev"], part["mm_short"], mm_url))
    if "bridge_mm_commit" in part:
        out.append("| Legacy-plugin bridge (`metamod.1.ep1`, PLAPI 7-12) | {} git{} | [`{}`]({}) |".format(
            mod.mm_version("1.10"), part["bridge_mm_rev"], part["bridge_mm_commit"][:8],
            gh + "alliedmodders/metamod-source/commit/" + part["bridge_mm_commit"]))
    if commit:
        out.append("| css34 pack | `{}` | [`{}`]({}{}/commit/{}) |".format(
            tag, commit[:8], gh, repo, commit))
    out.append("")
    out.append("**Toolchain**")
    out.append("")
    out.append("- Linux: `{}` (manylinux2014 i686, glibc 2.17, devtoolset-10 GCC 10). "
               "Packages need **glibc 2.17** or newer (`min_glibc` in `css34-package.json`).".format(
                   linux_image(root)))
    if line.get("windows", False):
        out.append("- Windows: MSVC x86 toolset {} with Windows SDK {} (exact versions in "
                   "`css34-package.json`).".format(msvc, sdk))
    series = series_for(root, name, part["mm_commit"])
    if series:
        out.append("- Patches: git patch series {} (`builder/patches/series/`, "
                   "see `docs/PATCHES.md`).".format(
                       ", ".join("`{}` ({} patches)".format(s, n) for s, n in series)))
    out.append("")
    smoke = [item["image"] for item in line.get("smoke", [])]
    weekly = list(data.get("weekly_smoke", []))
    if smoke or weekly:
        out.append("**Tested**: smoke on {}; release smoke of the public URLs on {}; "
                   "botplay on `{}`.".format(
                       ", ".join("`{}`".format(i) for i in smoke) or "-",
                       ", ".join("`{}`".format(i) for i in weekly) or "-",
                       data.get("weekly_botplay_image", "-")))
        out.append("")
    sm_minor = int(part["sm_expect"].split(".")[1])
    if sm_minor >= 13:
        out.append("**Extensions built for SourceMod 1.12 or older do not load.** SourceMod 1.13 loads only "
                   "extensions built with 1.13 headers (extension API 9 or newer, `extension_api_min`–"
                   "`extension_api` in `VERSIONS.txt`; older ones fail with `Extension version is too "
                   "old to load`), and an extension rebuilt with them does not load on 1.12 either. Rebuild third-party "
                   "extensions with this release's SourceMod, Metamod and hl2sdk episode1 trees in the "
                   "same build image: [docs/EXTENSIONS.md]({0}{1}/blob/{2}/docs/EXTENSIONS.md) "
                   "(recipe, flags, and `undefined symbol: Msg`: link `tier0_i486.so`).".format(
                       gh, repo, commit or "master"))
    else:
        out.append("**Extensions**: SourceMod 1.{} loads extension API 8 and older; extensions "
                   "rebuilt for 1.13 (API 9/11) do not load here. Recipe: "
                   "[docs/EXTENSIONS.md]({}{}/blob/{}/docs/EXTENSIONS.md).".format(
                       sm_minor, gh, repo, commit or "master"))
    out.append("")
    out.append("**Assets**: SourceMod and Metamod:Source for Linux (`.tar.gz`){}. The asset names "
               "carry the revision (`git<rev>`), which changes with every pin bump; the same files "
               "are also attached under fixed names (`sourcemod-css34-linux.tar.gz` and "
               "`mmsource-css34-linux.tar.gz`, the names `line-{}` serves{}), and `VERSIONS.txt` "
               "lists the exact versions, asset names and sha256 (`key=value`). `SHA256SUMS` "
               "(every asset) is uploaded last; it and `SHA256SUMS.linux` list both the "
               "revisioned and the fixed names, so check the files you downloaded with "
               "`sha256sum -c --ignore-missing SHA256SUMS`.".format(
                   " and Windows (`.zip`, may follow the Linux packages)" if line.get("windows") else "",
                   name, "; `sourcemod-css34-windows.zip`, `mmsource-css34-windows.zip`"
                   if line.get("windows") else ""))
    out.append("")
    out.append("Published releases are never deleted. When `line-{}` moves on, this release gets a "
               "*superseded* note and its asset URLs keep working; for the current build use the "
               "`line-{}` pointer.".format(name, name))
    out.append("")
    if data["known_bad"]:
        out.append("**Known-bad tags** (do not install; kept as prereleases):")
        out.append("")
        for bad, reason in sorted(data["known_bad"].items()):
            out.append("- `{}`: {}".format(bad, reason))
        out.append("")
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tag")
    parser.add_argument("--repo", default="fmu1337/sourcemod-css34")
    parser.add_argument("--commit", default="")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    sys.stdout.write(render(args.tag, args.repo, args.commit, args.root))


if __name__ == "__main__":
    main()
