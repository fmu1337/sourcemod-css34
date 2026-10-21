#!/usr/bin/env python3
"""Point generate_headers.py at a lines.json revision.

Metamod is cloned with --depth 1, so `git rev-list --count HEAD` is 1 and
`meta version` prints `1.12.0-dev+1`. SOURCEMOD_GIT_REV / MMS_GIT_REV are
already exported by resolve-version.sh; this teaches generate_headers.py to
prefer that value when it is a positive integer. The commit id stays the
abbreviated SHA that upstream already prints.

MM 1.10's generator also drops the rev from the version string. With
--mm110-dev-suffix a dev tag becomes `-dev+<rev>` (1.10.7-dev+976), matching
the 1.12 string.
"""
import argparse
import sys
from pathlib import Path

COUNT_ANCHOR = (
    "def get_git_version():\n"
    "  revision_count = run_and_return(['git', 'rev-list', '--count', 'HEAD'])\n"
)
COUNT_MARKER = "css34: lines.json rev"

TAG_ANCHOR = "  if tag:\n    tag = '-' + tag\n"
TAG_MARKER = "css34: 1.10 dev rev suffix"


def pin_count(text: str, env_name: str) -> str:
    if COUNT_MARKER in text:
        return text
    if COUNT_ANCHOR not in text:
        raise SystemExit(
            f"FAIL: get_git_version() rev-list anchor not found (env {env_name})"
        )
    replacement = (
        "def get_git_version():\n"
        f"  # {COUNT_MARKER}. A --depth 1 clone makes git rev-list --count print 1.\n"
        f"  pinned = os.environ.get({env_name!r}, '').strip()\n"
        "  if pinned.isdigit():\n"
        "    revision_count = pinned\n"
        "  else:\n"
        "    revision_count = run_and_return(['git', 'rev-list', '--count', 'HEAD'])\n"
    )
    return text.replace(COUNT_ANCHOR, replacement, 1)


def pin_mm110_dev_suffix(text: str) -> str:
    if TAG_MARKER in text:
        return text
    if TAG_ANCHOR not in text:
        raise SystemExit("FAIL: MM 1.10 product-tag anchor not found in generate_headers.py")
    replacement = (
        f"  # {TAG_MARKER}. Upstream 1.10 omits the rev; 1.12 prints 1.12.0-dev+N.\n"
        "  if tag == 'dev':\n"
        "    tag = '-dev+' + count\n"
        "  elif tag:\n"
        "    tag = '-' + tag\n"
    )
    return text.replace(TAG_ANCHOR, replacement, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--env", required=True, choices=("MMS_GIT_REV", "SOURCEMOD_GIT_REV"))
    parser.add_argument("--mm110-dev-suffix", action="store_true")
    args = parser.parse_args()

    path = args.path
    if not path.is_file():
        raise SystemExit(f"FAIL: generate_headers.py not found: {path}")
    original = path.read_text()
    text = pin_count(original, args.env)
    if args.mm110_dev_suffix:
        text = pin_mm110_dev_suffix(text)
    if text == original:
        print(f"==> {path.name} already uses {args.env}")
        return
    path.write_text(text)
    print(f"==> {path.name} reads {args.env} for the build number")


if __name__ == "__main__":
    sys.exit(main() or 0)
