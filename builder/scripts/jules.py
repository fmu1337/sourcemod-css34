#!/usr/bin/env python3
"""Jules sessions for the upstream bump (T4.4): review every bump, propose a fix when one fails.

    jules.py prompt review|fix --target T --old SHA --new SHA --rev N [--context FILE]
        The prompt for a read-only review of a bump PR, or for a minimal fix of a bump
        that could not be applied (the conflict/check log goes in --context).
    jules.py start --title T --prompt-file F --branch B [--auto-pr]
        Create a session on this repository starting from branch B. Without --auto-pr
        Jules opens no pull request (review); with it, a finished code change becomes
        Jules' own PR (fix). Prints {"name": ..., "url": ...}.
    jules.py wait <session name> [--timeout S] [--interval S] [--out FILE]
        Poll until the session ends (or the timeout), then write a markdown report:
        state, session link, PR link if any, Jules' last message.

Safety is in the prompts and in what the workflow does with the result: Jules never
gets a token of this repository, starts from a branch it cannot push to unless it
opens its own PR, and nothing it produces is merged automatically.

Env: JULES_API_KEY (required for start/wait), JULES_API_URL (default
https://jules.googleapis.com/v1alpha), GITHUB_REPOSITORY (default
fmu1337/sourcemod-css34; the Jules source is sources/github/<owner>/<repo>).
"""
import argparse
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
TERMINAL = {"COMPLETED", "FAILED", "AWAITING_USER_FEEDBACK", "AWAITING_PLAN_APPROVAL", "PAUSED"}
COMMENT_LIMIT = 60000  # GitHub comments are capped at 65536 characters

SAFETY = """Hard rules (a human merges everything; CI must stay meaningful):
- Never change .github/, testing/, builder/scripts/, builder/lines.py, or any check,
  test or CI step, and never weaken, skip or delete a check to make something pass.
- Never touch frozen or archived lines (sm11-oldstable, sm13-mm20*), release tags or
  the published releases.
- Keep changes minimal and explain each one. If you are not sure a change is right,
  do not make it: describe it in your report instead."""


def bump_spec(target):
    import importlib.util
    spec = importlib.util.spec_from_file_location("upstream_bump", ROOT / "builder/scripts/upstream-bump.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.TARGETS[target]


def prompt(kind, target, old, new, rev, context):
    spec = bump_spec(target)
    repo = spec["repo"]
    series = ", ".join("builder/patches/series/{}/".format(s) for s in spec["series"])
    compare = "https://github.com/alliedmodders/{}/compare/{}...{}".format(repo, old, new)
    head = (
        "Repository fmu1337/sourcemod-css34 builds SourceMod and Metamod:Source for Counter-Strike: Source v34 "
        "(legacy Source engine, SDK episode1, 32-bit Linux and Windows). Upstream code is patched by git patch "
        "series ({series}) applied to the exact pinned upstream commit; pins live in builder/lines.json. "
        "Read docs/MAINTAINING.md and docs/CHANGES.md first.\n\n"
        "This is an upstream bump of `{target}`: lines.json pin `{pin}` moves from alliedmodders/{repo} "
        "{old} to {new} (rev {rev}, branch {branch}). Upstream diff: {compare}\n"
    ).format(series=series, target=target, pin=spec["pin"], repo=repo, old=old, new=new, rev=rev,
             branch=spec["branch"], compare=compare)
    ctx = ""
    if context:
        ctx = "\nContext from the bump workflow:\n\n" + Path(context).read_text(errors="replace")[-30000:] + "\n"
    if kind == "review":
        task = (
            "\nTASK (read-only review): the branch you start on already carries the bump; CI runs on its PR. "
            "Do NOT modify any file and do NOT create commits or pull requests. Study the upstream changes "
            "between the two commits and how they meet this repository:\n"
            "1. files our patch series touch (diff --git headers in the .patch files);\n"
            "2. gamedata lookups (GetOffset/GetMemSig/GetKeyValue/GetAddress) against "
            "builder/assets/gamedata/ and testing/scripts/check-css34-gamedata.py;\n"
            "3. engine/SDK bindings that differ on episode1 (core/, extensions/sdktools, sdkhooks, cstrike);\n"
            "4. build changes (AMBuildScript, configure.py, submodule bumps such as sourcepawn, hl2sdk-manifests).\n"
            "Answer with a short report in this shape:\n"
            "## What changed upstream that matters for CS:S v34\n"
            "## Risks and what to check on a test server\n"
            "## Changes needed in this repository (file and what), or \"nothing to change\"\n"
        )
    else:
        task = (
            "\nTASK (fix): the automated bump could not be applied; the workflow log is below. Make the "
            "smallest change that lets the bump through, on a new branch from master:\n"
            "1. set pins.{pin}.commit = {new} and pins.{pin}.rev = {rev} in builder/lines.json;\n"
            "2. run builder/scripts/patch-series.sh refresh <series> for {series_list}; where a patch no "
            "longer applies, adapt that patch to the new upstream code (keep what it is for, see "
            "docs/CHANGES.md), then rerun the refresh;\n"
            "3. if gamedata lookups changed, extend builder/assets/gamedata/ with CS:S v34 values only when "
            "you can justify them; otherwise leave it and report;\n"
            "4. run python3 builder/lines.py gen and python3 builder/lines.py check.\n"
            "Only builder/lines.json, builder/patches/series/**, the files lines.py gen writes, "
            "builder/assets/gamedata/** and docs/CHANGES.md may change. In the PR description list every "
            "patch you changed and why. If you cannot fix it safely, make no code change and explain what "
            "blocks it.\n"
        ).format(pin=spec["pin"], new=new, rev=rev, series_list=", ".join(spec["series"]))
    return head + task + "\n" + SAFETY + "\n" + ctx


def api(method, path, body=None):
    key = os.environ.get("JULES_API_KEY", "")
    if not key:
        raise SystemExit("FAIL: JULES_API_KEY is not set")
    base = os.environ.get("JULES_API_URL", "https://jules.googleapis.com/v1alpha").rstrip("/")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + "/" + path.lstrip("/"), data=data, method=method,
                                 headers={"X-Goog-Api-Key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:500]
        raise SystemExit("FAIL: Jules API {} {}: HTTP {} {}".format(method, path, err.code, detail))


def source():
    repo = os.environ.get("GITHUB_REPOSITORY", "fmu1337/sourcemod-css34")
    return "sources/github/" + repo


def session_url(session):
    return session.get("url") or ""


def find(title, pages=3):
    """An existing session with exactly this title (the newest pages only), or None."""
    token = ""
    for _ in range(pages):
        page = api("GET", "sessions?pageSize=100" + ("&pageToken=" + token if token else ""))
        for session in page.get("sessions", []):
            if session.get("title") == title:
                return session
        token = page.get("nextPageToken", "")
        if not token:
            return None
    return None


def start(title, prompt_text, branch, auto_pr, skip_if_exists=False):
    if skip_if_exists:
        existing = find(title)
        if existing:
            return {"name": existing.get("name", ""), "url": session_url(existing), "existing": True}
    body = {"title": title, "prompt": prompt_text,
            "sourceContext": {"source": source(), "githubRepoContext": {"startingBranch": branch}}}
    if auto_pr:
        body["automationMode"] = "AUTO_CREATE_PR"
    session = api("POST", "sessions", body)
    name = session.get("name") or "sessions/" + str(session.get("id", ""))
    return {"name": name, "url": session_url(session), "existing": False}


def activities(name):
    out, token = [], ""
    while True:
        page = api("GET", "{}/activities?pageSize=100{}".format(name, "&pageToken=" + token if token else ""))
        out.extend(page.get("activities", []))
        token = page.get("nextPageToken", "")
        if not token:
            return out


def wait(name, timeout, interval):
    deadline = time.monotonic() + timeout
    session = api("GET", name)
    while session.get("state") not in TERMINAL and time.monotonic() < deadline:
        time.sleep(interval)
        session = api("GET", name)
    state = session.get("state", "UNKNOWN")
    messages = [a["agentMessaged"].get("agentMessage", "") for a in activities(name) if "agentMessaged" in a]
    prs = [o["pullRequest"]["url"] for o in session.get("outputs", []) if o.get("pullRequest", {}).get("url")]
    url = session_url(session)
    link = "[session]({})".format(url) if url else "session `{}`".format(name)
    lines = ["**Jules** ({}): state `{}`{}.".format(
        link, state, "" if state in TERMINAL else " (still running when the workflow stopped waiting)")]
    for pr in prs:
        lines.append("Jules opened {} (review it like any PR; nothing merges automatically).".format(pr))
    lines.append("")
    lines.append(messages[-1].strip() if messages else "_No report from Jules yet; see the session._")
    text = "\n".join(lines) + "\n"
    if len(text) > COMMENT_LIMIT:
        text = text[:COMMENT_LIMIT] + "\n\n… (truncated; full report in the session)\n"
    return state, text


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prompt")
    p.add_argument("kind", choices=("review", "fix"))
    p.add_argument("--target", required=True)
    p.add_argument("--old", required=True)
    p.add_argument("--new", required=True)
    p.add_argument("--rev", required=True)
    p.add_argument("--context")
    p = sub.add_parser("start")
    p.add_argument("--title", required=True)
    p.add_argument("--prompt-file", required=True, type=Path)
    p.add_argument("--branch", required=True)
    p.add_argument("--auto-pr", action="store_true")
    p.add_argument("--skip-if-exists", action="store_true",
                   help="reuse a session with the same title instead of starting another")
    p = sub.add_parser("wait")
    p.add_argument("name")
    p.add_argument("--timeout", type=float, default=2400)
    p.add_argument("--interval", type=float, default=60)
    p.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.cmd == "prompt":
        sys.stdout.write(prompt(args.kind, args.target, args.old, args.new, args.rev, args.context))
    elif args.cmd == "start":
        print(json.dumps(start(args.title, args.prompt_file.read_text(), args.branch, args.auto_pr,
                               args.skip_if_exists)))
    else:
        state, text = wait(args.name, args.timeout, args.interval)
        if args.out:
            args.out.write_text(text)
        else:
            sys.stdout.write(text)
        print("state=" + state, file=sys.stderr)


if __name__ == "__main__":
    main()
