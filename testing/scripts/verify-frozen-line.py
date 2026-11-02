#!/usr/bin/env python3
"""Verify a frozen line's published files (T2.7, frozen-verify.yml).

    verify-frozen-line.py --base https://github.com/<repo>/releases/download \\
        --repo-git https://github.com/<repo> --line sm11-oldstable --tag <frozen tag> \\
        --freeze-tag sm11-freeze --inputs-release sm11-freeze-inputs \\
        --assets '<json name -> sha256>' --pointer-assets '<json pointer name -> asset>'

The arguments are a row of `python3 builder/lines.py frozen-gha`. Fails unless:
  * the frozen tag's SHA256SUMS lists every asset of lines.json with the same
    sha256, and every asset downloads with that sha256;
  * line-<line> serves the frozen tag with smoke=pass, and each pointer file is
    byte-identical to its release asset (SHA256SUMS and download);
  * the input archive release has MANIFEST.json for this line, whose
    builder_commit is the freeze tag's commit, and SHA256SUMS agrees with the
    MANIFEST's asset list (the archive itself is not downloaded).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)
    print(f"FAIL: {message}", file=sys.stderr)


def ok(message: str) -> None:
    print(f"OK: {message}")


def fetch(url: str) -> bytes:
    last = None
    for _ in range(4):
        try:
            with urllib.request.urlopen(url, timeout=120) as resp:
                return resp.read()
        except OSError as error:  # URLError is an OSError
            last = error
    raise OSError(f"{url}: {last}")


def sums(text: str) -> dict[str, str]:
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2:
            out[parts[1].lstrip("*")] = parts[0]
    return out


def tag_commit(repo_git: str, tag: str) -> str:
    out = subprocess.run(["git", "ls-remote", repo_git, f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"],
                         capture_output=True, text=True, check=True).stdout
    refs = dict(reversed(line.split("\t")) for line in out.splitlines() if "\t" in line)
    return refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}", "")


def main() -> int:
    ap = argparse.ArgumentParser()
    for name in ("base", "repo-git", "line", "tag", "freeze-tag", "inputs-release", "assets", "pointer-assets"):
        ap.add_argument(f"--{name}", required=True)
    args = ap.parse_args()
    assets: dict[str, str] = json.loads(args.assets)
    pointer: dict[str, str] = json.loads(args.pointer_assets)
    base = args.base.rstrip("/")

    # 1. The frozen release.
    try:
        published = sums(fetch(f"{base}/{args.tag}/SHA256SUMS").decode())
    except OSError as error:
        fail(f"{args.tag}/SHA256SUMS: {error}")
        published = {}
    for name, digest in sorted(assets.items()):
        if published.get(name) != digest:
            fail(f"{args.tag}/SHA256SUMS lists {name} as {published.get(name)}, lines.json says {digest}")
            continue
        try:
            got = hashlib.sha256(fetch(f"{base}/{args.tag}/{name}")).hexdigest()
        except OSError as error:
            fail(f"{args.tag}/{name}: {error}")
            continue
        if got != digest:
            fail(f"{args.tag}/{name} downloads as {got}, expected {digest}")
        else:
            ok(f"{args.tag}/{name} {digest[:16]}")

    # 2. The line pointer.
    ptr = f"line-{args.line}"
    try:
        entry = json.loads(fetch(f"{base}/{ptr}/lines.json")).get(args.line) or {}
        if entry.get("tag") != args.tag or entry.get("smoke") != "pass":
            fail(f"{ptr} serves {entry.get('tag')!r} smoke={entry.get('smoke')!r}, expected {args.tag} smoke=pass")
        else:
            ok(f"{ptr} serves {args.tag} (smoke: pass)")
        ptr_sums = sums(fetch(f"{base}/{ptr}/SHA256SUMS").decode())
    except (OSError, ValueError) as error:
        fail(f"{ptr}: {error}")
        ptr_sums = {}
    for name, asset in sorted(pointer.items()):
        want = assets.get(asset)
        if ptr_sums.get(name) != want:
            fail(f"{ptr}/SHA256SUMS lists {name} as {ptr_sums.get(name)}, expected {asset} ({want})")
            continue
        try:
            got = hashlib.sha256(fetch(f"{base}/{ptr}/{name}")).hexdigest()
        except OSError as error:
            fail(f"{ptr}/{name}: {error}")
            continue
        if got != want:
            fail(f"{ptr}/{name} downloads as {got}, expected {asset} ({want})")
        else:
            ok(f"{ptr}/{name} = {asset}")

    # 3. The input archive.
    rel = args.inputs_release
    try:
        in_sums = sums(fetch(f"{base}/{rel}/SHA256SUMS").decode())
        raw = fetch(f"{base}/{rel}/MANIFEST.json")
        manifest = json.loads(raw)
    except (OSError, ValueError) as error:
        fail(f"{rel}: {error}")
        in_sums, raw, manifest = {}, b"", {}
    if manifest:
        if in_sums.get("MANIFEST.json") != hashlib.sha256(raw).hexdigest():
            fail(f"{rel}/MANIFEST.json does not match its SHA256SUMS entry")
        if manifest.get("line") != args.line:
            fail(f"{rel}/MANIFEST.json is for line {manifest.get('line')!r}")
        try:
            commit = tag_commit(args.repo_git, args.freeze_tag)
        except subprocess.CalledProcessError as error:
            commit = ""
            fail(f"git ls-remote {args.repo_git}: {error.stderr.strip()}")
        if not commit:
            fail(f"tag {args.freeze_tag} does not exist")
        elif manifest.get("builder_commit") != commit:
            fail(f"{rel} was collected at {manifest.get('builder_commit')}, {args.freeze_tag} is {commit}")
        else:
            ok(f"{rel} was collected at {args.freeze_tag} ({commit[:12]})")
        listed = manifest.get("assets") or {}
        for name, digest in sorted(listed.items()):
            if in_sums.get(name) != digest:
                fail(f"{rel}: {name} is {in_sums.get(name)} in SHA256SUMS, {digest} in MANIFEST.json")
        for required in ("build-image.tar.zst",):
            if required not in listed:
                fail(f"{rel} has no {required}")
        if not any(name.startswith("git-") for name in listed):
            fail(f"{rel} has no git mirrors")
        if listed and not failures:
            ok(f"{rel}: {len(listed)} archived inputs listed in MANIFEST.json and SHA256SUMS")

    if failures:
        print(f"Frozen line {args.line}: {len(failures)} problem(s)", file=sys.stderr)
        return 1
    print(f"Frozen line {args.line}: published files match lines.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
