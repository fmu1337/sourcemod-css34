#!/usr/bin/env python3
"""Stamps for the built Linux dependency prefixes (CI deps cache).

checkout-deps.sh builds static PIC zlib, OpenSSL 3.5 LTS and MariaDB
Connector/C from pinned sources and unpacks the pinned MySQL 5.6 SDK into
deps/. ci.yml's build-linux restores those prefixes with actions/cache
(.github/actions/build-linux, input deps-cache); release.yml and the freeze
path never do. Whatever the source of a prefix, the builder reuses it only when
the stamp inside it records the same inputs digest as this build; anything else
(no stamp, another digest, a missing file, a freeze build) rebuilds it.

The digest covers everything that determines the prefixes' contents:
  - the build image (CSS34_BUILD_IMAGE, set by builder/docker/build.sh from the
    image reference it runs, a sha256 digest);
  - the deps directory path (OpenSSL embeds its OPENSSLDIR);
  - the exact bytes of INPUT_FILES: the scripts that fetch, configure and build
    the prefixes, which also hold every version and sha256 pin they use.
The SourceMod and Metamod pins do not change these prefixes; the SourceMod pin
only decides which of them a line needs (configure.py --mariadb-path), so it
goes into the CI cache key, not into the digest.

  deps_cache.py digest [--root R] [--image I] [--deps-dir D]
  deps_cache.py check PREFIX DIGEST [FILE...]   exit 0: reuse, 1: rebuild
  deps_cache.py stamp PREFIX DIGEST
  deps_cache.py key --line L --sm-commit C [--root R] [--image I] [--deps-dir D]
  deps_cache.py paths [--deps-dir-rel deps]     the cached prefixes, one per line
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAMP_NAME = '.css34-deps-stamp.json'
# Bump to invalidate every stamp and CI cache entry at once.
SCHEMA = 1
# builder/docker/build.sh runs the build with this deps directory.
CONTAINER_DEPS_DIR = '/workspace/deps'

# Repository files whose bytes decide the prefixes. checkout-deps.sh holds the
# versions, URLs, sha256 pins and configure/build commands; fetch-pinned.sh
# downloads and verifies; patch-openssl-getentropy.py patches OpenSSL (run by
# py.sh); build.sh chooses the image and the container environment (CC, CXX,
# linux32, devtoolset-10); this file decides reuse.
INPUT_FILES = (
    'builder/checkout-deps.sh',
    'builder/fetch-pinned.sh',
    'builder/py.sh',
    'builder/patches/patch-openssl-getentropy.py',
    'builder/docker/build.sh',
    'builder/deps_cache.py',
)

# The prefixes checkout-deps.sh stamps (relative to deps/). build-perl is only
# a build tool of OpenSSL and is not cached.
PREFIXES = (
    'zlib',
    'openssl',
    'mariadb-connector-c-3.4.9-x86',
    'mysql-5.5',
)

IMAGE_RE = re.compile(r'^IMAGE="\$\{ML2014_IMAGE:-([^}"]+)\}"$', re.M)


def default_image(root: Path) -> str:
    """The image builder/docker/build.sh runs (ML2014_IMAGE overrides it)."""
    env = os.environ.get('ML2014_IMAGE')
    if env:
        return env
    text = (root / 'builder/docker/build.sh').read_text(encoding='utf-8')
    found = IMAGE_RE.findall(text)
    if len(found) != 1:
        raise SystemExit('FAIL: cannot read the default image from builder/docker/build.sh')
    return found[0]


def inputs(root: Path, image: str, deps_dir: str) -> dict:
    files = {}
    for rel in INPUT_FILES:
        path = root / rel
        if not path.is_file():
            raise SystemExit(f'FAIL: deps cache input {rel} is missing')
        files[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {'schema': SCHEMA, 'image': image, 'deps_dir': deps_dir, 'files': files}


def digest_of(data: dict) -> str:
    blob = json.dumps(data, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(blob).hexdigest()


def compute_digest(root: Path, image: str | None, deps_dir: str) -> str:
    return digest_of(inputs(root, image or default_image(root), deps_dir))


def reuse_decision(prefix: Path, digest: str, files: list[str], env=None) -> tuple[bool, str]:
    """(reuse, reason) for a prefix found in deps/."""
    env = os.environ if env is None else env
    if env.get('CSS34_OFFLINE', '0') == '1' or env.get('CSS34_SAVE_DOWNLOADS'):
        return False, 'freeze build (offline or collecting inputs): never reuse'
    if env.get('CSS34_DEPS_REBUILD', '0') == '1':
        return False, 'CSS34_DEPS_REBUILD=1'
    if not prefix.is_dir():
        return False, 'not present'
    stamp = prefix / STAMP_NAME
    if not stamp.is_file():
        return False, 'no stamp'
    try:
        recorded = json.loads(stamp.read_text(encoding='utf-8'))
    except (OSError, ValueError) as exc:
        return False, f'unreadable stamp ({exc})'
    if not isinstance(recorded, dict) or recorded.get('digest') != digest:
        got = recorded.get('digest') if isinstance(recorded, dict) else None
        return False, f'stamp digest {str(got)[:12]} != inputs {digest[:12]}'
    if recorded.get('prefix') != prefix.name:
        return False, f'stamp names prefix {recorded.get("prefix")!r}'
    for rel in files:
        if not (prefix / rel).is_file():
            return False, f'missing {rel}'
    return True, f'stamp matches inputs {digest[:12]}'


def write_stamp(prefix: Path, digest: str) -> None:
    if not prefix.is_dir():
        raise SystemExit(f'FAIL: cannot stamp {prefix}: not a directory')
    data = {'digest': digest, 'prefix': prefix.name, 'schema': SCHEMA}
    tmp = prefix / (STAMP_NAME + '.tmp')
    tmp.write_text(json.dumps(data, sort_keys=True) + '\n', encoding='utf-8')
    tmp.replace(prefix / STAMP_NAME)


def cache_key(line: str, sm_commit: str, digest: str) -> str:
    if not re.fullmatch(r'[A-Za-z0-9._-]+', line):
        raise SystemExit(f'FAIL: bad line name {line!r}')
    if not re.fullmatch(r'[0-9a-f]{40}', sm_commit):
        raise SystemExit(f'FAIL: SourceMod commit must be 40 hex digits, got {sm_commit!r}')
    return f'css34-deps-v{SCHEMA}-{line}-sm{sm_commit[:12]}-{digest}'


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest='cmd', required=True)

    def common(p):
        p.add_argument('--root', type=Path, default=ROOT)
        p.add_argument('--image', default=os.environ.get('CSS34_BUILD_IMAGE') or None)
        p.add_argument('--deps-dir', default=None)

    p = sub.add_parser('digest')
    common(p)
    p = sub.add_parser('check')
    p.add_argument('prefix', type=Path)
    p.add_argument('digest')
    p.add_argument('files', nargs='*')
    p = sub.add_parser('stamp')
    p.add_argument('prefix', type=Path)
    p.add_argument('digest')
    p = sub.add_parser('key')
    common(p)
    p.add_argument('--line', required=True)
    p.add_argument('--sm-commit', required=True)
    p = sub.add_parser('paths')
    p.add_argument('--deps-dir-rel', default='deps')
    args = ap.parse_args(argv)

    if args.cmd == 'digest':
        deps_dir = args.deps_dir or CONTAINER_DEPS_DIR
        print(compute_digest(args.root.resolve(), args.image, deps_dir))
    elif args.cmd == 'check':
        reuse, reason = reuse_decision(args.prefix, args.digest, args.files)
        verb = 'reusing' if reuse else 'building'
        print(f'==> deps cache: {verb} {args.prefix.name}: {reason}', file=sys.stderr)
        return 0 if reuse else 1
    elif args.cmd == 'stamp':
        write_stamp(args.prefix, args.digest)
    elif args.cmd == 'key':
        deps_dir = args.deps_dir or CONTAINER_DEPS_DIR
        print(cache_key(args.line, args.sm_commit,
                        compute_digest(args.root.resolve(), args.image, deps_dir)))
    elif args.cmd == 'paths':
        for name in PREFIXES:
            print(f'{args.deps_dir_rel}/{name}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
