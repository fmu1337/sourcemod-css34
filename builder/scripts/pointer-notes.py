#!/usr/bin/env python3
"""Title and notes of a line-<line> pointer release, from its lines.json entry.

    python3 builder/scripts/pointer-notes.py --line <line> --lines-json <file>
        [--sums SHA256SUMS] [--repo owner/name] [--title]

GitHub shows a release's first publication date, which for a pointer is the day
the pointer was created. So update-line-pointer.sh rewrites the title and notes on
every move: what the pointer serves now, since when, the versions, and the sha256
of every served file. With --title only the title is printed.
"""
import argparse
import json
from pathlib import Path
import sys


def api_text(entry, repo="fmu1337/sourcemod-css34"):
    hi = entry.get("extension_api")
    if hi is None:
        return "-"
    hi, lo = int(hi), int(entry.get("extension_api_min") or 1)
    if lo < 9:
        return "up to {} (extensions built with SourceMod 1.12 or older headers)".format(hi)
    return ("{}–{} (extensions need SourceMod 1.13 headers; ones built for 1.12 or older do not load, "
            "see [docs/EXTENSIONS.md](https://github.com/{}/blob/master/docs/EXTENSIONS.md))"
            .format(lo, hi, repo))


def title(line, entry):
    served = entry.get("tag")
    return "line-{} → {}".format(line, served) if served else "line-{} (no passing build yet)".format(line)


def notes(line, entry, sums, repo):
    gh = "https://github.com/{}".format(repo)
    ptr = "line-{}".format(line)
    base = "{}/releases/download/{}".format(gh, ptr)
    served = entry.get("tag")
    out = ["Stable pointer for line `{}`. The asset names below never change; this page is "
           "rewritten every time the pointer moves.".format(line), ""]
    if served:
        when = (entry.get("updated") or "").replace("T", " ").replace("Z", " UTC")
        out += [
            "**Now serves [`{0}`]({1}/releases/tag/{0})** since {2} (smoke: {3}).".format(
                served, gh, when or "?", entry.get("smoke", "?")),
            "",
            "| | |",
            "|--|--|",
            "| SourceMod | {} ([`{}`](https://github.com/alliedmodders/sourcemod/commit/{})) |".format(
                entry.get("sm_version", "?"), str(entry.get("sm_commit", ""))[:8], entry.get("sm_commit", "")),
            "| Metamod:Source | {} ([`{}`](https://github.com/alliedmodders/metamod-source/commit/{})) |".format(
                entry.get("mm_version", "?"), str(entry.get("mm_commit", ""))[:8], entry.get("mm_commit", "")),
            "| Metamod core | `{}` |".format(entry.get("metamod_binary", "?")),
            "| Extension API | {} |".format(api_text(entry, repo)),
            "",
        ]
    else:
        out += ["**No build of this line has passed the release smoke yet**; the pointer serves no packages.", ""]
    candidate = entry.get("candidate")
    if candidate and candidate.get("tag") and candidate.get("tag") != served:
        out += ["Last candidate [`{0}`]({1}/releases/tag/{0}) failed the release smoke ({2}); "
                "the pointer kept serving the build above.".format(
                    candidate["tag"], gh, candidate.get("updated", "?")), ""]
    if sums:
        out += ["| File | SHA-256 |", "|------|---------|"]
        for name, digest in sums:
            out.append("| [`{0}`]({1}/{0}) | `{2}` |".format(name, base, digest))
        out.append("")
    out += ["Machine-readable: [`lines.json`]({0}/lines.json), [`VERSIONS.txt`]({0}/VERSIONS.txt) "
            "(`key=value`: versions, original asset names, sha256), "
            "[`SHA256SUMS`]({0}/SHA256SUMS).".format(base)]
    return "\n".join(out) + "\n"


def read_sums(path):
    rows = []
    for raw in Path(path).read_text().splitlines():
        parts = raw.split()
        if len(parts) == 2:
            rows.append((parts[1].lstrip("*"), parts[0]))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--line", required=True)
    parser.add_argument("--lines-json", required=True, type=Path)
    parser.add_argument("--sums", type=Path)
    parser.add_argument("--repo", default="fmu1337/sourcemod-css34")
    parser.add_argument("--title", action="store_true")
    args = parser.parse_args()
    entry = json.loads(args.lines_json.read_text()).get(args.line) or {}
    if args.title:
        print(title(args.line, entry))
        return
    sums = read_sums(args.sums) if args.sums and args.sums.exists() else []
    sys.stdout.write(notes(args.line, entry, sums, args.repo))


if __name__ == "__main__":
    main()
