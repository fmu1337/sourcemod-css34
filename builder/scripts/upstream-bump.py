#!/usr/bin/env python3
"""Upstream bump plumbing for .github/workflows/upstream-bump.yml (T4.4).

    upstream-bump.py plan [--cache DIR]
        JSON list of the tracked targets whose pin is behind its upstream branch tip.
    upstream-bump.py apply <target> <commit> <rev>
        Move the target's pin in builder/lines.json, refresh its patch series
        (builder/scripts/patch-series.sh refresh), run `lines.py gen`.
    upstream-bump.py body <target> <old commit> <new commit> [--cache DIR] [--drift FILE]
        Markdown PR body: upstream log, risky paths, affected lines and tags.
    upstream-bump.py release-tags <old lines.json> <new lines.json> --existing FILE
        Tags to push after a merge: one per releasable pointer line whose
        SourceMod/Metamod/bridge pins moved, `-r<N>` when the base tag exists.
    upstream-bump.py next-tag <line> --lines FILE --existing FILE
        The next release tag of one releasable pointer line for the lines.json in
        FILE (a packaging rebuild: `-r<N>` when the base tag exists), for
        .github/workflows/release-tag.yml.

Tracked targets are TARGETS below (the lines' upstream branches). Upstream
URLs can be redirected for tests with CSS34_UPSTREAM_<REPO> (REPO: SOURCEMOD,
METAMOD_SOURCE), e.g. file:///tmp/sm.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

# target -> lines.json pin, upstream repository and branch, patch series to refresh.
TARGETS = {
    "sm12-latest": {"pin": "SM_LATEST", "repo": "sourcemod", "branch": "1.12-dev",
                    "series": ["sm12-latest"]},
    "sm13-latest": {"pin": "SM_LATEST_13", "repo": "sourcemod", "branch": "master",
                    "series": ["sm13-latest"]},
    "MM_112": {"pin": "MM_112", "repo": "metamod-source", "branch": "1.12-dev",
               "series": ["MM_112"]},
}

# Upstream paths a bump reviewer must look at even when no series patch touches them.
RISKY = (
    re.compile(r"^gamedata/"),
    re.compile(r"^extensions/(sdktools|sdkhooks|cstrike)/"),
    re.compile(r"^core/(logic/)?(GameConfigs|sourcemm_api|smn_entities|HalfLife2)"),
    re.compile(r"^(AMBuildScript|configure\.py|product\.version|pushbuild\.txt)$"),
    re.compile(r"^(hl2sdk-manifests|sourcepawn|public/amtl|public/safetyhook)$"),
    re.compile(r"^core/(provider|sourcehook|metamod)"),
    re.compile(r"^support/buildbot/"),
)


def git(*args, cwd=None, check=True):
    res = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and res.returncode != 0:
        raise SystemExit("FAIL: git {}: {}".format(" ".join(args), res.stderr.strip()))
    return res.stdout.strip()


def upstream_url(repo):
    env = "CSS34_UPSTREAM_" + repo.upper().replace("-", "_")
    return os.environ.get(env) or "https://github.com/alliedmodders/{}.git".format(repo)


def lines_module(root):
    spec = importlib.util.spec_from_file_location("css34_lines_bump", root / "builder/lines.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def mirror(repo, cache):
    """A blob-less clone of <repo> in <cache> (full history: rev counts are build numbers)."""
    path = cache / repo
    if not (path / ".git").is_dir():
        path.parent.mkdir(parents=True, exist_ok=True)
        git("clone", "--quiet", "--filter=blob:none", "--no-checkout", upstream_url(repo), str(path))
    else:
        git("remote", "set-url", "origin", upstream_url(repo), cwd=path)
    return path


def tip(repo, branch, cache):
    path = mirror(repo, cache)
    git("fetch", "--quiet", "origin", "+refs/heads/{0}:refs/remotes/origin/{0}".format(branch), cwd=path)
    sha = git("rev-parse", "origin/" + branch, cwd=path)
    return sha, int(git("rev-list", "--count", sha, cwd=path))


def plan(root, cache):
    data = json.loads((root / "builder/lines.json").read_text())
    out = []
    for target, spec in TARGETS.items():
        pin = data["pins"][spec["pin"]]
        sha, rev = tip(spec["repo"], spec["branch"], cache)
        if sha == pin["commit"]:
            continue
        path = cache / spec["repo"]
        # Never move a pin backwards or sideways (a force-pushed upstream branch).
        ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", pin["commit"], sha],
                                  cwd=path).returncode == 0
        out.append({"target": target, "pin": spec["pin"], "repo": spec["repo"],
                    "branch": spec["branch"], "old_commit": pin["commit"], "old_rev": pin["rev"],
                    "new_commit": sha, "new_rev": rev, "fast_forward": ancestor,
                    "series": spec["series"]})
    return out


def apply(root, target, commit, rev, workdir=None):
    spec = TARGETS[target]
    path = root / "builder/lines.json"
    text = path.read_text()
    data = json.loads(text)
    if json.dumps(data, indent=2, ensure_ascii=False) + "\n" != text:
        raise SystemExit("FAIL: builder/lines.json is not in its canonical format (json indent 2)")
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or int(rev) <= 0:
        raise SystemExit("FAIL: bad commit/rev {} {}".format(commit, rev))
    pin = data["pins"][spec["pin"]]
    pin["commit"], pin["rev"] = commit, int(rev)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    for series in spec["series"]:
        args = ["bash", str(root / "builder/scripts/patch-series.sh"), "refresh", series]
        if workdir:
            args.append(str(Path(workdir) / series))
        if subprocess.run(args, cwd=root).returncode != 0:
            raise SystemExit("FAIL: patch series {} does not apply to {} {}; see the conflict above".format(
                series, spec["repo"], commit[:12]))
    if subprocess.run([sys.executable, str(root / "builder/lines.py"), "gen"], cwd=root).returncode != 0:
        raise SystemExit("FAIL: python3 builder/lines.py gen")


def affected(root, data, pin_name):
    """(line, tag) of every releasable active line that uses <pin_name>."""
    mod = lines_module(root)
    rows = []
    for name, line in data["lines"].items():
        if line.get("status") != "active" or not line.get("releasable", True):
            continue
        if pin_name in (line.get("sourcemod"), line.get("metamod"), line.get("bridge_metamod")):
            rows.append((name, mod.line_parts(data, name)["tag"]))
    return rows


def series_files(root, series):
    files = set()
    base = root / "builder/patches/series" / series
    top = json.loads((base / "series.json").read_text()).get("root", "sourcemod")
    for patch in sorted((base / top).glob("*.patch")):
        for match in re.finditer(r"^diff --git a/(\S+) b/", patch.read_text(errors="replace"), re.M):
            files.add(match.group(1))
    return files


def body(root, target, old, new, cache, drift=None):
    spec = TARGETS[target]
    data = json.loads((root / "builder/lines.json").read_text())
    path = mirror(spec["repo"], cache)
    git("fetch", "--quiet", "origin", "+refs/heads/{0}:refs/remotes/origin/{0}".format(spec["branch"]), cwd=path)
    log = git("log", "--oneline", "--no-decorate", "{}..{}".format(old, new), cwd=path).splitlines()
    changed = git("diff", "--name-only", old, new, cwd=path).splitlines()
    patched = set()
    for series in spec["series"]:
        patched |= series_files(root, series)
    risky = sorted(f for f in changed if f in patched or any(r.search(f) for r in RISKY))
    url = upstream_url(spec["repo"]).replace(".git", "")
    pin = data["pins"][spec["pin"]]
    out = ["Weekly upstream bump (T4.4, `.github/workflows/upstream-bump.yml`).", ""]
    out.append("**{}**: `{}` {} → {} ([`{}..{}`]({}/compare/{}...{})), {} commit(s) on `{}`.".format(
        target, spec["pin"], old[:8], new[:8], old[:8], new[:8], url, old, new, len(log), spec["branch"]))
    out.append("")
    out.append("Pin now: commit `{}`, rev {}. Patch series refreshed: {}.".format(
        pin["commit"], pin["rev"], ", ".join("`{}`".format(s) for s in spec["series"])))
    rows = affected(root, data, spec["pin"])
    if rows:
        out.append("")
        out.append("Lines rebuilt by this bump, and the tag pushed after merge (`release.yml`: "
                   "prerelease → smoke → promote → pointer):")
        out.append("")
        for name, tag in rows:
            out.append("- `{}` → `{}` (`-r<N>` if that tag exists)".format(name, tag))
    out.append("")
    out.append("### Risky upstream paths ({})".format(len(risky)))
    out.append("")
    if risky:
        out.append("Files this bump changes that a css34 patch touches (`P`) or that hold gamedata, "
                   "build or SDK-binding code:")
        out.append("")
        for f in risky[:100]:
            out.append("- {}`{}`".format("**P** " if f in patched else "", f))
        if len(risky) > 100:
            out.append("- … {} more".format(len(risky) - 100))
    else:
        out.append("None.")
    if drift:
        out.append("")
        out.append("### Checks before this PR")
        out.append("")
        out.append(Path(drift).read_text().strip())
    out.append("")
    out.append("<details><summary>Upstream log ({} commits)</summary>".format(len(log)))
    out.append("")
    out.append("```")
    out.extend(log[:300])
    if len(log) > 300:
        out.append("… {} more".format(len(log) - 300))
    out.append("```")
    out.append("</details>")
    out.append("")
    out.append("CI on this PR builds, smokes and botplays every affected line. Merge it to release; "
               "do not edit `builder/lines.json` pins by hand.")
    return "\n".join(out) + "\n"


def release_tags(root, old_json, new_json, existing):
    mod = lines_module(root)
    old = json.loads(old_json)
    new = json.loads(new_json)
    tags = []
    for name, line in new["lines"].items():
        if line.get("status") != "active" or not line.get("releasable", True) or not line.get("pointer", False):
            continue
        part = mod.line_parts(new, name)
        before = None
        if name in old.get("lines", {}) and old["lines"][name].get("status") == "active":
            before = mod.line_parts(old, name)
        keys = ("sm_commit", "mm_commit", "bridge_mm_commit")
        if before is not None and all(before.get(k) == part.get(k) for k in keys):
            continue
        base = part["tag"]
        if base in new.get("known_bad", {}):
            raise SystemExit("FAIL: {} is known-bad".format(base))
        tags.append(next_free_tag(base, existing))
    return tags


def next_free_tag(base, existing):
    """<base> when no tag of it exists, else <base>-r<highest N + 1> (the base counts as r1)."""
    taken = [t for t in existing if t == base or re.fullmatch(re.escape(base) + r"-r[0-9]+", t)]
    if not taken:
        return base
    numbers = [int(t.rsplit("-r", 1)[1]) for t in taken if t != base]
    return "{}-r{}".format(base, max(numbers + [1]) + 1)


def next_tag(root, lines_json, name, existing):
    """Next tag of <name> for a hand-requested release (release-tag.yml)."""
    mod = lines_module(root)
    data = json.loads(lines_json)
    line = data.get("lines", {}).get(name)
    if line is None:
        raise SystemExit("FAIL: unknown line {!r}".format(name))
    if line.get("status") != "active" or not line.get("releasable", True) or not line.get("pointer", False):
        raise SystemExit("FAIL: {} is not a releasable pointer line (status {}, releasable {}, pointer {})".format(
            name, line.get("status"), line.get("releasable", True), line.get("pointer", False)))
    base = mod.line_parts(data, name)["tag"]
    if base in data.get("known_bad", {}):
        raise SystemExit("FAIL: {} is known-bad".format(base))
    return next_free_tag(base, existing)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=ROOT)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--cache", type=Path)
    p = sub.add_parser("apply")
    p.add_argument("target", choices=sorted(TARGETS))
    p.add_argument("commit")
    p.add_argument("rev")
    p.add_argument("--workdir")
    p = sub.add_parser("body")
    p.add_argument("target", choices=sorted(TARGETS))
    p.add_argument("old")
    p.add_argument("new")
    p.add_argument("--cache", type=Path)
    p.add_argument("--drift")
    p = sub.add_parser("release-tags")
    p.add_argument("old_json", type=Path)
    p.add_argument("new_json", type=Path)
    p.add_argument("--existing", type=Path, required=True)
    p = sub.add_parser("next-tag")
    p.add_argument("line")
    p.add_argument("--lines", type=Path, required=True)
    p.add_argument("--existing", type=Path, required=True)
    args = parser.parse_args()
    cache = getattr(args, "cache", None) or Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())) / "css34-upstream"
    if args.cmd == "plan":
        print(json.dumps(plan(args.root, cache), indent=2))
    elif args.cmd == "apply":
        apply(args.root, args.target, args.commit, args.rev, args.workdir)
    elif args.cmd == "body":
        sys.stdout.write(body(args.root, args.target, args.old, args.new, cache, args.drift))
    elif args.cmd == "release-tags":
        existing = args.existing.read_text().split()
        old_text = args.old_json.read_text() if args.old_json.is_file() else "{}"
        for tag in release_tags(args.root, old_text, args.new_json.read_text(), existing):
            print(tag)
    elif args.cmd == "next-tag":
        print(next_tag(args.root, args.lines.read_text(), args.line, args.existing.read_text().split()))


if __name__ == "__main__":
    main()
