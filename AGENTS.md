# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **build system** (not a long-running app). It compiles patched
**SourceMod + Metamod:Source** packages for **Counter-Strike: Source v34** — three
lines selected by `CSS34_LINE` (default `sm13-latest` = SM 1.13.0.7472 + MM 1.12
git1226; pins in `builder/lines.json`; generated `builder/versions.env`) — and
smoke-tests them on a real `srcds`
dedicated server. See `README.md`, `docs/README.md`, `testing/README.md`, and
`.github/workflows/` for the canonical commands; the notes below only cover
non-obvious environment caveats.

### Docker is required and must be started each session
The host is **Ubuntu 24.04**, which has **no `gcc-9` multilib** toolchain. All
builds and smoke tests therefore run **inside containers** (`ubuntu:22.04` /
`debian:11`). Docker is pre-installed in the VM snapshot, but the daemon is a
service and is **not** started by the update script. Start it once per session
(it also needs the Docker-29 + fuse-overlayfs config already written to
`/etc/docker/daemon.json`), and note the current user is not in the `docker`
group, so `docker` needs `sudo`:

```bash
sudo dockerd > /tmp/dockerd.log 2>&1 &   # wait ~5s, then: sudo docker info
```

### Building the packages (the "app")
- **Shipping / smoke-test-compatible package** (what `test-server.yml`,
  `release.yml` and `build.yml` build): `CSS34_LINE=<line> builder/docker/build.sh`.
  Image `quay.io/pypa/manylinux2014_i686@sha256:30305867f278896ee117b0d162a8e4f9b7b16819e6590f6139e14c5ed5b23fdd`
  (CentOS 7.9 i686, glibc 2.17, devtoolset-10 GCC 10.2.1). Python for AMBuild is
  `/opt/python/cp311-cp311/bin/python`. The script runs under `linux32` so
  AMBuild sees i686. `builder/docker/legacy-build.sh` is a wrapper that calls
  `build.sh` (removed in T1.4).
- `builder/run/linux.sh` still knows the old clang-9 path (`USE_CLANG9=1` by
  default outside the manylinux image). Inside manylinux it forces `USE_CLANG9=0`
  and `gcc`/`g++` from devtoolset-10. Do not export `gcc-9` there.
- `git config --global --add safe.directory '*'` inside the container (the repo
  is bind-mounted and owned by uid 1000, git blocks submodule ops otherwise).
  `build.sh` does this itself.
- The builder self-provisions deps into `deps/` (pinned hl2sdk episode1,
  rom4s/hl2sdk-ep1c, AMBuild, static OpenSSL 1.1.1w, MySQL / MariaDB SDKs).
  Downloads come from github.com, bitbucket.org, cdn.mysql.com, www.openssl.org,
  snapshot.debian.org and archive.debian.org — all reachable. Tarball downloads
  are sha256-pinned.
- Packages stay in `packages/` (or `PACKAGES_DIR`); the builder creates no root
  symlinks. Source `builder/package-paths.sh` with `CSS34_LINE` to resolve exact
  SM/MM archive paths. Archived MM 2.0/KHook builds live in `archive/khook`;
  master rejects those build lines, while their published pointers stay intact.

### Verifying / testing
- **Static ABI check** (the "ABI / export checks" step of `build-linux` in
  `test-server.yml`, "Static package checks" in `release.yml`): `SM_PACKAGE=<pkg>
  testing/scripts/check-package.sh` and `MM_PACKAGE=<pkg>
  testing/scripts/check-metamod-package.sh`. Uses host `binutils` (reads 32-bit
  ELF fine). The **manylinux2014** package must PASS with `GLIBC_FLOOR=2.17`
  (the default): every ELF ≤ GLIBC 2.17, logic.so exports no `std::` /
  `__cxxabiv1`, and no Metamod `.so` needs `libstdc++.so.6`. A jammy-native
  package still fails those checks.
- **Full smoke test** (CI primary gate `test-built-debian`): prepare the server
  tree on the host (`fetch-server.sh` → `apply-valve-rc-fix.sh` →
  `apply-srcds-patch.sh` → `KEEP_MAPS=de_dust2,de_inferno,de_nuke trim-server-maps.sh`,
  needs `unrar`), then boot `srcds` inside a pinned image from `builder/lines.json`
  (`centos:7`, `ubuntu:24.04`, or `debian:13` on every PR; older images are the
  weekly/release matrix) running `install-deps.sh` → `install-addons.sh` →
  `smoke-test.sh` with `SM_PACKAGE` / `MM_PACKAGE` set (without them
  `install-addons.sh` falls back to downloading rom4s 6572 + MM 1.10.6). The
  559 MB server zip is cached under `.ci-cache/`. It boots a 32-bit `srcds_i686`
  and probes `meta version` / `sm version` / `sm exts load dbi.mysql.ext` /
  `sm exts load dbi.pgsql.ext` / `sm exts list` / `sm plugins list` via `expect`
  (~2 min). Pass `CSS34_LINE=<line>` (or the `*_EXPECT` variables) so the expected
  versions match the package. `meta version` must contain `+<MM_REV>` and
  `Build ID: <MM_REV>:<sha prefix>`; `sm version` must be `<major>.<SM_REV>`
  (the revs come from `builder/lines.json`). Image digests live only in
  `builder/lines.json`; `python3 builder/lines.py gen` writes the matrix.

### Lint
Run `actionlint` after workflow edits. The ABI export
check (`check-package.sh`) is the closest static verification of build output.

### Version pin bumps (Jules / agents)
Daily SM/MM tip bumps: follow `docs/JULES_DAILY_VERSION_BUMP.md`. After editing
pins in `builder/lines.json`, run `python3 builder/lines.py gen` then
`python3 builder/lines.py check` (also enforced by
`.github/workflows/version-pins.yml` on PRs). `gen` rewrites `builder/versions.env`,
`builder/generated/ci-matrix.json`, `builder/generated/tag-map.sh`, and the README pin
tables. Workflows load the matrices from `python3 builder/lines.py gha`. Upstream tip probe:
`builder/scripts/resolve-upstream-tips.sh`.
