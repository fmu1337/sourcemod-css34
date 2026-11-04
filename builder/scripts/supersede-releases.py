#!/usr/bin/env python3
"""Mark the older build releases of a line as superseded (never delete them).

    python3 builder/scripts/supersede-releases.py --line <line> --served <tag>
        [--repo owner/name] [--dry-run]

Published releases are kept forever, so external links and CI that pinned a tag
keep working. When line-<line> moves to <served>, every other build release of
the same family (same SourceMod major.minor and Metamod part, any -rN) that was
created before <served> gets a banner at the top of its notes:
"Superseded by <served> ... use line-<line>". The banner is rewritten when the
successor changes, and removed from <served> itself (a rollback). Assets, tags,
the prerelease flag and GitHub "Latest" are left alone.

Needs `gh` with GH_TOKEN (contents: write).
"""
import argparse
import json
import re
import subprocess
import sys

MARKER = "<!-- css34-superseded -->"
END = "<!-- /css34-superseded -->"
# <major>.<minor>.<patch>.<rev>-mm<mm version><variant>[-rN]
TAG_RE = re.compile(r"^(\d+)\.(\d+)\.\d+\.\d+-(mm[0-9.]+)(.*?)(-r\d+)?$")


def family(tag):
    """'1.13.0.7478-mm1.12.0-r5' -> '1.13-mm1.12.0'; None for a non-build tag."""
    match = TAG_RE.match(tag or "")
    if not match:
        return None
    major, minor, mm, variant, _ = match.groups()
    return "{}.{}-{}{}".format(major, minor, mm, variant)


def strip_banner(body):
    body = body or ""
    start = body.find(MARKER)
    if start < 0:
        return body
    end = body.find(END, start)
    if end < 0:
        return body
    return (body[:start] + body[end + len(END):]).lstrip("\n")


def banner(served, line, repo, date):
    url = "https://github.com/{}/releases/tag/{}".format(repo, served)
    return "\n".join([
        MARKER,
        "> [!NOTE]",
        "> **Superseded** by [`{}`]({}) ({}). This release stays published and its"
        " asset URLs keep working.".format(served, url, date),
        "> For the current build use the `line-{}` pointer (fixed asset names).".format(line),
        END,
        "",
        "",
    ])


def plan(releases, line, served, repo):
    """[(id, tag, new_body)] for every release whose notes must change."""
    fam = family(served)
    if fam is None:
        raise SystemExit("FAIL: {} is not a build release tag".format(served))
    by_tag = {r["tag_name"]: r for r in releases}
    if served not in by_tag:
        raise SystemExit("FAIL: no release for the served tag {}".format(served))
    cut = by_tag[served]["created_at"]
    date = cut[:10]
    changes = []
    for rel in sorted(releases, key=lambda r: r["created_at"]):
        tag = rel["tag_name"]
        if rel.get("draft") or family(tag) != fam:
            continue
        old = rel.get("body") or ""
        clean = strip_banner(old)
        if tag == served:
            new = clean
        elif rel["created_at"] < cut:
            new = banner(served, line, repo, date) + clean
        else:
            continue  # a newer candidate (e.g. a failed smoke) is not superseded by an older build
        if new != old:
            changes.append((rel["id"], tag, new))
    return changes


def gh_releases(repo):
    out = subprocess.run(
        ["gh", "api", "--paginate", "repos/{}/releases?per_page=100".format(repo),
         "-q", ".[] | {id, tag_name, created_at, draft, body}"],
        check=True, capture_output=True, text=True).stdout
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--line", required=True)
    parser.add_argument("--served", required=True)
    parser.add_argument("--repo", default="fmu1337/sourcemod-css34")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    changes = plan(gh_releases(args.repo), args.line, args.served, args.repo)
    if not changes:
        print("nothing to mark: every older {} release already names {}".format(
            family(args.served), args.served))
    for rel_id, tag, body in changes:
        what = "unmarked (served)" if tag == args.served else "superseded by " + args.served
        if args.dry_run:
            print("dry run: {} would be {}".format(tag, what))
            continue
        subprocess.run(["gh", "api", "-X", "PATCH", "repos/{}/releases/{}".format(args.repo, rel_id),
                        "-f", "body=" + body], check=True, stdout=subprocess.DEVNULL)
        print("{}: {}".format(tag, what))


if __name__ == "__main__":
    sys.exit(main())
