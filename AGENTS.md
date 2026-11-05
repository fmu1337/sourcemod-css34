# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **build system** (not a long-running app). It compiles patched
**SourceMod + Metamod:Source** packages for **Counter-Strike: Source v34** — two
buildable lines selected by `CSS34_LINE` (`sm12-latest`, default `sm13-latest` =
SM 1.13.0.7478 + MM 1.12 git1228; pins in `builder/lines.json`; generated
`builder/versions.env`; `sm11-oldstable` is frozen) — and
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
  AMBuild, PIC zlib 1.3.1, MySQL / MariaDB SDKs; for sm13's Linux MySQL extension
  static OpenSSL 3.5 LTS and MariaDB Connector/C built from source, see
  `docs/PATCHES.md` "sm13 MySQL dependencies").
  SourceMod is no git submodule (T3.3): `builder/fetch-sourcemod.sh` checks out the
  line's pinned commit into `sourcemod/` (gitignored), resets and cleans it, and
  initializes its own submodules.
- Patches (T3.4): every buildable line has a git patch series in
  `builder/patches/series/<line>/` (`sm12-latest`, `sm13-latest`), and the MM 1.12
  pin has `builder/patches/series/MM_112/`; there is no scripted fallback. A
  series is `<repo>/NNNN-*.patch` per repository (its root, `sourcemod` or
  `metamod`, or a submodule path such as `sourcepawn`, `hl2sdk-manifests`),
  applied by `builder/patches/apply-series.sh` with `git apply --index`;
  `series.json` holds the upstream commit and the tree every repository must
  have afterwards (`git write-tree`), and `lines.py check` requires that commit
  to be the pin. After a pin bump run
  `builder/scripts/patch-series.sh refresh <line or MM_112>`; edit a patch by changing the
  checked-out tree and regenerating it the same way.
  `builder/scripts/check-patch-drift.sh` dry-runs a series on another upstream
  commit (`--sm-commit`, `--range`) with `git apply --3way`.
  Downloads come from github.com, bitbucket.org, cdn.mysql.com, archive.mariadb.org,
  vault.centos.org (build-time perl RPMs for OpenSSL), snapshot.debian.org and
  archive.debian.org — all reachable. Tarball downloads are sha256-pinned.
- Packages stay in `packages/` (or `PACKAGES_DIR`); the builder creates no root
  symlinks. Source `builder/package-paths.sh` with `CSS34_LINE` to resolve exact
  SM/MM archive paths (Linux tar.gz and Windows zip, both with `git<rev>`).
  Archived MM 2.0/KHook builds live in `archive/khook`;
  master rejects those build lines, while their published pointers stay intact.
- sm11 is **frozen** (T2.7, `docs/FREEZE.md`): `status: frozen`, `releasable: false`, a `frozen`
  block (tag, `sm11-freeze`, `sm11-freeze-inputs`, sha256 of every release asset). CI no longer
  builds it, a new sm11 tag is refused, and `frozen-verify.yml` re-checks its published files weekly
  (`lines.py frozen-gha`, `testing/scripts/verify-frozen-line.py`), with the line's text-only
  hotfix from `hotfixes/<line>/` installed over them (`HOTFIX_DIR`, `check-css34-gamedata.py
  --allow-custom` for `custom/*.txt` gamedata overrides). Its dual-core build code (SM 1.11
  patcher, `secondary_metamod` builds, the rom4s hl2sdk-ep1c SDK) left master with T3.3: rebuild it
  only from the `sm11-freeze` tag. The builder (`css34_require_buildable` in `resolve-version.sh`:
  SourceMod 1.12+ only) and `resolve-metamod-pins.py` refuse it; `resolve-version.sh` still resolves its
  pins for smoke expectations. `lines.py check` allows `secondary_metamod` only on a frozen line.
  A bug in a frozen line does not unfreeze it (`docs/FREEZE.md` "Fixing a frozen line"): a text-only
  fix (gamedata) ships in `hotfixes/<line>/` as a SourceMod `gamedata/<name>.games/custom/*.txt`
  override, the packages stay as published (`testing/scripts/test-frozen-hotfixes.py`); a fix in the
  binaries needs a refreeze (new `-rN` build, freeze tag and input archive).
- sm11 (D7): primary Metamod is the frozen MM 1.12 (git1227), secondary MM 1.10.7;
  its tag is `1.11.0.6970-mm1.12.0-dual` and `line-sm11-oldstable` also serves MM 1.10.7 as
  `mmsource-legacy-css34-linux.tar.gz` (`lines.py legacy-mm-asset <line>`, `update-line-pointer.sh`
  5th argument, a second `release-smoke.sh` in `smoke-pointer` and `frozen-verify.yml`).
- A buildable line's Metamod inputs come from `metamod` (MM 1.12) and `bridge_metamod` (MM 1.10) in
  `builder/lines.json`, resolved by `builder/resolve-metamod-pins.py`. Checkout, the Linux/Windows
  builds and the package verifier share this resolver; unknown lines and invalid pin references are
  errors. The builder holds no pinned commits of its own (`check-version-copies.sh`).
- Windows (`builder/run/windows.sh`) builds on `windows-2022` with MSVC toolset
  `14.44` (`-vcvars_ver=14.44`) and Windows SDK `10.0.26100.0`
  (`builder/windows-toolchain.env`). `builder/package_windows.py` writes the zips
  (POSIX `/` paths, `css34-package.json` inside, full toolset and SDK versions
  in the manifest). `sm12-latest` and `sm13-latest` have `"windows": true`; `build-windows`
  (native Windows smoke, every PR) and the weekly `wine-smoke` run one row per line. Both
  workflows build through `.github/actions/build-windows`, which reads the pins from
  `builder/windows-toolchain.env`.

### Verifying / testing
- **Static ABI check** (the "Static package checks" step of
  `.github/actions/build-linux`, used by `build-linux` in `ci.yml` and `linux` in
  `release.yml`): `SM_PACKAGE=<pkg>
  testing/scripts/check-package.sh` and `MM_PACKAGE=<pkg>
  testing/scripts/check-metamod-package.sh`. Uses host `binutils` (reads 32-bit
  ELF fine). The **manylinux2014** package must PASS with `GLIBC_FLOOR=2.17`
  (the default): every ELF ≤ GLIBC 2.17, logic.so exports no `std::` /
  `__cxxabiv1`, and no Metamod `.so` needs `libstdc++.so.6`. A package built
  outside this manylinux image still fails those checks. Unversioned undefined
  imports in every SM/MM ELF are checked against `testing/unversioned-imports.txt`;
  verify additions against the pinned providers, never the host libc.
- **Host regression tests** (GCC, binutils and Expect required):
  `bash testing/scripts/run-host-tests.sh` runs every `testing/scripts/test-*.py` /
  `test-*.sh` plus the negative smoke check (CI `hygiene`); name tests to run a subset, e.g.
  `python3 testing/scripts/test-glibc-imports.py` and
  `python3 testing/scripts/test-console-probe.py`. These test ABI rejection,
  optimized hidden erasure, patch drift and continued console diagnostics.
- **Full smoke test** (CI job `smoke`; the server tree comes from
  `.github/actions/server-tree`): prepare the server
  tree on the host (`fetch-server.sh` → `apply-valve-rc-fix.sh` →
  `apply-srcds-patch.sh` → `KEEP_MAPS=de_dust2,de_inferno,de_nuke trim-server-maps.sh`,
  needs `unrar`), then boot `srcds` inside a pinned image from `builder/lines.json`
  (`centos:7`, `ubuntu:24.04`, or `debian:13` on every PR; older images are the
  weekly suite and release matrix) running `install-deps.sh` → `install-addons.sh` →
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
- **Prebuilt test images**: `test-images.yml` bakes `install-deps.sh` into each smoke/botplay
  image (`ghcr.io/fmu1337/css34-test`, `testing/docker/test-image.Dockerfile`);
  `lines.json` `test_images` records `ref` / `base` / `deps_hash`, and matrix rows carry
  `image` (prebuilt when current) and `base_image` (fallback,
  `testing/scripts/pull-test-image.sh`). In such an image `install-deps.sh` is a no-op
  (marker `/etc/css34-install-deps.sha256`). Editing `install-deps.sh` makes the entries
  stale: `lines.py check` fails until `python3 builder/lines.py test-images-prune` and `gen`;
  after the merge the workflow rebuilds and opens the `test-images/update` PR.
  Details: `testing/README.md` "Prebuilt test images".
- **Core gates**: each matrix row names the Metamod package it installs (`mm_package`)
  and the core that must run (`expect_core`, `2.ep1`). `smoke-test.sh` takes
  `SMOKE_EXPECT_CORE=1.ep1|2.ep1` (`1.ep1` only for the frozen sm11 pointer's
  `mmsource-legacy`), and `host-checks` probes the PLAPI of every built core
  (`check-core-plapi.sh`) and smoke-tests on the runner host.
- **Legacy-plugin bridge** (T2.9, #144): MM 1.12 (`metamod.2.ep1`) hands
  PLAPI 7-12 plugins to the MM 1.10 legacy core (`metamod.1.ep1`) from its own
  `bin/` directory, as rom4s's MM 1.12 git1159 does. Code:
  `builder/patches/mm-oldbridge/` applied by `apply-mmsource-oldbridge.sh`
  (fail-closed, from `apply-mmsource-css34.sh` and, for MM 1.12 only,
  `checkout-deps.sh` after the `MM_112` patch series, `docs/PATCHES.md`). A line's MM 1.10 legacy core comes from
  `bridge_metamod` in `lines.json` (`sm12-latest`, `sm13-latest`; role `bridge` in
  `resolve-metamod-pins.py`: built first, its `metamod.1.ep1` copied into the MM 1.12
  package, never packaged itself).
  `verify-line-metamod-packages.sh` requires that core inside the MM 1.12 package,
  built from the bridge pin, with `legacy_bridge: true`. The PLAPI 11 test plugin
  `css34_legacy_probe` lands in `packages/test-plugins/` (never released). Matrix
  rows with `legacy_bridge=1` run
  `testing/scripts/legacy-bridge-test.sh` (Linux) and `LEGACY_PROBE` in
  `wine-smoke-test.sh` (Windows).

### Frozen lines (T2.7)
`builder/freeze/collect-inputs.sh` archives every input of an online build (git
mirrors of each pinned commit, `fetch_pinned` downloads, the saved build image,
`MANIFEST.json`); `builder/freeze/build-offline.sh` rebuilds from that archive
with `--network none` (`CSS34_INPUTS_DIR` in `builder/docker/build.sh`), and
`testing/scripts/compare-package-abi.py` must find the same files, exports,
NEEDED and SONAME. Every new download in the builder must go through
`fetch_pinned` (`builder/fetch-pinned.sh`) with a sha256, or offline rebuilds
break. Workflows `freeze-inputs.yml` (publishing waits for the `frozen-release` environment) and
`frozen-verify.yml` (weekly); details in `docs/FREEZE.md`.

### Releases are never deleted
Other repositories pin release URLs, so a published release or tag is never deleted (README
"Release retention"; 12 were deleted on 2026-11-03 and broke consumers). After a pointer move
`release.yml` marks the line's older releases *superseded* (`builder/scripts/supersede-releases.py`);
broken builds go to `known_bad`. `release-maintenance.yml` has no delete mode, and `gh release delete`
is not a maintenance step. Every tag release also carries fixed-name copies of its packages and
`VERSIONS.txt` (`release-versions.py`); pointer pages are rewritten on each move (`pointer-notes.py`).

### Lint
Run `actionlint` after workflow edits (`testing/scripts/install-actionlint.sh` installs
the pinned, sha256-checked version CI uses). The ABI export
check (`check-package.sh`) is the closest static verification of build output.

### Version pin bumps (T4.4)
`.github/workflows/upstream-bump.yml` does them: weekly (or on dispatch) it opens
or updates one PR per lagging target (`bump/sm12-latest`, `bump/sm13-latest`,
`bump/MM_112`) through `builder/scripts/upstream-bump.py` (`plan`, `apply`,
`body`), and after such a PR is merged its `release` job pushes the moved lines'
tags (`release-tags`; `-r<N>` when the base tag exists), which `release.yml`
builds as prereleases and promotes. It needs the owner's GitHub App
(`vars.BUMP_APP_ID`, `secrets.BUMP_APP_KEY`) so that CI and `release.yml` run.
With `secrets.JULES_API_KEY`, `builder/scripts/jules.py` adds a read-only Jules
review to every new bump PR (posted as a comment), and when a bump cannot be
applied asks Jules for a minimal fix in its own PR against master; Jules gets no
token of this repository and nothing it produces merges automatically.
A packaging rebuild of the current pins (`-r<N>`) goes through
`.github/workflows/release-tag.yml` (dispatch: `line`, `sha` on master, optional
`expected_tag`; `upstream-bump.py next-tag` computes the tag from that commit's
`lines.json`, refuses frozen/retired lines, known-bad tags and an already tagged
commit, and the same GitHub App pushes it). Cloud agent sessions cannot push tags
themselves; they dispatch this workflow.
By hand: edit the pin in `builder/lines.json`, run
`builder/scripts/patch-series.sh refresh <series>` (it reads the pin from
`lines.json`; `gen` refuses to run until the series matches), then
`python3 builder/lines.py gen` and `python3 builder/lines.py check` (also enforced by
`.github/workflows/ci.yml` on PRs). `gen` rewrites `builder/versions.env`,
`builder/generated/ci-matrix.json`, `builder/generated/tag-map.sh`, and the README pin
tables. `ci.yml` builds its matrices in the `plan` job
(`builder/scripts/ci_planner.py`, which also lists the jobs the run requires) and
ends in one `gate` job (`builder/scripts/ci_gate.py`). Suites: `pr` (PRs, master pushes)
and `weekly` (Monday schedule or dispatch `suite=weekly`: old OS smoke, centos:7 botplay,
Wine smoke); dispatch also takes `css34_line`. `release.yml` takes its OS rows from
`lines.py` `ci_matrix` (`release-pins`). Planner and gate are covered by
`python3 testing/scripts/test-ci-planner-gate.py`. Upstream tip probe:
`builder/scripts/resolve-upstream-tips.sh`.
