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
- **Shipping / smoke-test-compatible package** (what `ci.yml` and
  `release.yml` build): `CSS34_LINE=<line> builder/docker/build.sh`.
  Image `quay.io/pypa/manylinux2014_i686@sha256:30305867f278896ee117b0d162a8e4f9b7b16819e6590f6139e14c5ed5b23fdd`
  (CentOS 7.9 i686, glibc 2.17, devtoolset-10 GCC 10.2.1). Python for AMBuild is
  `/opt/python/cp311-cp311/bin/python`. The script runs under `linux32` so
  AMBuild sees i686.
- `builder/run/linux.sh` uses `CC` / `CXX` from the environment. `build.sh`
  sets them to devtoolset-10 `gcc` / `g++`.
- `git config --global --add safe.directory '*'` inside the container (the repo
  is bind-mounted and owned by uid 1000, git blocks submodule ops otherwise).
  `build.sh` does this itself.
- The builder self-provisions deps into `deps/` (pinned hl2sdk episode1,
  rom4s/hl2sdk-ep1c, AMBuild, static OpenSSL 1.1.1w, PIC zlib 1.3.1,
  MySQL / MariaDB SDKs).
  Downloads come from github.com, bitbucket.org, cdn.mysql.com, www.openssl.org,
  snapshot.debian.org and archive.debian.org — all reachable. Tarball downloads
  are sha256-pinned.
- Packages stay in `packages/` (or `PACKAGES_DIR`); the builder creates no root
  symlinks. Source `builder/package-paths.sh` with `CSS34_LINE` to resolve exact
  SM/MM archive paths (Linux tar.gz and Windows zip, both with `git<rev>`).
  Archived MM 2.0/KHook builds live in `archive/khook`;
  master rejects those build lines, while their published pointers stay intact.
- sm11's primary and secondary Metamod inputs are resolved from `metamod` and
  `secondary_metamod` in `builder/lines.json` by `builder/resolve-metamod-pins.py`.
  Checkout, Linux/Windows dual-MM builds, and the package verifier share this
  resolver; unknown lines and invalid pin references are errors.
- Windows (`builder/run/windows.sh`) builds on `windows-2022` with MSVC toolset
  `14.44` (`-vcvars_ver=14.44`) and Windows SDK `10.0.26100.0`
  (`builder/windows-toolchain.env`). `builder/package_windows.py` writes the zips
  (POSIX `/` paths, `css34-package.json` inside, full toolset and SDK versions
  in the manifest). `sm11-oldstable`, `sm12-latest` and `sm13-latest` have `"windows": true`;
  sm11 Windows builds both cores and both Metamod zips, and `wine-smoke` runs on each.

### Verifying / testing
- **Static ABI check** (the "ABI / export checks" step of `build-linux` in
  `ci.yml`, "Static package checks" in `release.yml`): `SM_PACKAGE=<pkg>
  testing/scripts/check-package.sh` and `MM_PACKAGE=<pkg>
  testing/scripts/check-metamod-package.sh`. Uses host `binutils` (reads 32-bit
  ELF fine). The **manylinux2014** package must PASS with `GLIBC_FLOOR=2.17`
  (the default): every ELF ≤ GLIBC 2.17, logic.so exports no `std::` /
  `__cxxabiv1`, and no Metamod `.so` needs `libstdc++.so.6`. A package built
  outside this manylinux image still fails those checks. Unversioned undefined
  imports in every SM/MM ELF are checked against `testing/unversioned-imports.txt`;
  verify additions against the pinned providers, never the host libc.
- **Host regression tests** (GCC, binutils and Expect required):
  `python3 testing/scripts/test-glibc-imports.py` and
  `python3 testing/scripts/test-console-probe.py`. These test ABI rejection,
  optimized hidden erasure, patch drift and continued console diagnostics.
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
- **Dual-core SM 1.11 gates** (T2.4): each matrix row names the Metamod build it
  installs (`mm_variant`, `mm_package`) and the core that must run
  (`expect_core`). `sm11-oldstable` smokes every per-PR image on MM 1.10.7
  (`1.ep1`) and MM 1.12 (`2.ep1`), switches between them on the first image with
  `testing/scripts/switch-metamod.sh`, and runs botplay on both. `smoke-test.sh`
  takes `SMOKE_EXPECT_CORE=1.ep1|2.ep1`: DHooks ships only as
  `dhooks.ext.2.ep1`, so it must load exactly on the 2.ep1 core.
  `check-sm11-build-log.sh` checks the include roots and 0 `WARN` lines in the
  1.11 build log, and `plapi-runtime` requires the published
  `1.11.0.6970-mm1.10.7` package to fail the PLAPI probe.

### Lint
Run `actionlint` after workflow edits. The ABI export
check (`check-package.sh`) is the closest static verification of build output.

### Version pin bumps (Jules / agents)
Daily SM/MM tip bumps: follow `docs/JULES_DAILY_VERSION_BUMP.md`. After editing
pins in `builder/lines.json`, run `python3 builder/lines.py gen` then
`python3 builder/lines.py check` (also enforced by
`.github/workflows/ci.yml` on PRs). `gen` rewrites `builder/versions.env`,
`builder/generated/ci-matrix.json`, `builder/generated/tag-map.sh`, and the README pin
tables. `ci.yml` builds its matrices in the `plan` job
(`builder/scripts/ci_planner.py`, which also lists the jobs the run requires) and
ends in one `gate` job (`builder/scripts/ci_gate.py`); `release.yml` still loads its
matrices from `python3 builder/lines.py gha`. Planner and gate are covered by
`python3 testing/scripts/test-ci-planner-gate.py`. Upstream tip probe:
`builder/scripts/resolve-upstream-tips.sh`.
