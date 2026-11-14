# AGENTS.md

A build system, not an app: it builds patched SourceMod + Metamod:Source packages for CS:S v34 and boots
them on a real `srcds`. Read [README.md](README.md), [docs/MAINTAINING.md](docs/MAINTAINING.md),
[docs/CHANGES.md](docs/CHANGES.md) and [testing/README.md](testing/README.md) first.

## Environment

- Builds and smoke tests run in Docker. If the daemon is not running:
  `sudo dockerd > /tmp/dockerd.log 2>&1 &` (wait a few seconds, then `sudo docker info`).
- Build: `CSS34_LINE=sm13-latest builder/docker/build.sh` (or `sm12-latest`); packages land in
  `packages/`. The script runs the pinned manylinux2014_i686 image under `linux32` and fixes
  `safe.directory` itself.
- Host tests need GCC, binutils and `expect`: `bash testing/scripts/run-host-tests.sh`. After workflow
  edits also run `actionlint` (`testing/scripts/install-actionlint.sh`).

## Rules

- Pins live only in `builder/lines.json`. After changing it: `builder/scripts/patch-series.sh refresh
  <line | MM_112>`, `python3 builder/lines.py gen`, `python3 builder/lines.py check`.
- Changes to upstream source go into the patch series, not into build scripts; document each patch in
  `docs/CHANGES.md`.
- Every new download in the builder goes through `fetch_pinned` (`builder/fetch-pinned.sh`) with a
  sha256, or offline (freeze) rebuilds break.
- A new unversioned import must be checked against the pinned providers (glibc 2.17 image, CS:S v34
  engine libraries) before it goes into `testing/unversioned-imports.txt`, never against the host libc.
- **Never delete a release or tag.** Mark it superseded or `known_bad` instead.
- Cloud agents cannot push tags: dispatch `release-tag.yml` for a rebuild (`-rN`).
- `sm11-oldstable` is frozen: fixes go to its freeze branch and a new `-rN` (docs/MAINTAINING.md).
