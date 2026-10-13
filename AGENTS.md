# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **build system** (not a long-running app). It compiles patched
**SourceMod + Metamod:Source** packages for **Counter-Strike: Source v34** — five
lines selected by `CSS34_LINE` (default `sm13-latest` = SM 1.13.0.7472 + MM 1.12
git1226; pins in `builder/versions.env`) — and smoke-tests them on a real `srcds`
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
- **Shipping / smoke-test-compatible package** (what `test-server.yml` and
  `release.yml` build): `CSS34_LINE=<line> builder/docker/legacy-build.sh`. It builds
  in `debian:11` with the i386 gcc-4.9 sysroot for `sourcemod.logic.so`. This is
  the package that passes the ABI check and boots on legacy glibc. Prefer this
  whenever you need a package that actually loads in `srcds`.
- **`build.yml` Linux equivalent** (jammy-native, compile check only): run
  `builder/run/linux.sh` inside `ubuntu:22.04` with `SKIP_APT_INSTALL=1`,
  `WDIR/DEPS_DIR/PACKAGES_DIR=/workspace/...`. Note: with the default
  `USE_CLANG9=1`, `builder/run/linux.sh` compiles with **clang-9** even when `CC=gcc-9`
  / `CXX=g++-9` are exported; gcc-9 is used only with `USE_CLANG9=0`.
- `git config --global --add safe.directory '*'` inside the container (the repo
  is bind-mounted and owned by uid 1000, git blocks submodule ops otherwise).
  `legacy-build.sh` does this itself.
- The builder self-provisions all deps into `deps/` (clang-9 and the rom4s
  clang-10 bundle from bitbucket, i386 sysroot, MySQL / MariaDB SDKs, hl2sdk
  clones, AMBuild). Downloads come from github.com, bitbucket.org, cdn.mysql.com,
  snapshot.debian.org and archive.debian.org — all reachable.
- Known quirk: `builder/run/linux.sh` leaves `sourcemod-*.tar.gz` / `mmsource-*.tar.gz`
  symlinks at the repo root pointing at the absolute package path. After a
  `legacy-build.sh` run that path is the container's `/workspace/packages/…`, so
  the links are dangling on the host (and `mmsource-*` is not in `.gitignore`).
  Ignore/delete them; the real artifacts live in `packages/`.

### Verifying / testing
- **Static ABI check** (the "ABI / export checks" step of `build-linux` in
  `test-server.yml`, "Static package checks" in `release.yml`): `SM_PACKAGE=<pkg>
  testing/scripts/check-package.sh` and `MM_PACKAGE=<pkg>
  testing/scripts/check-metamod-package.sh`. Uses host `binutils` (reads 32-bit
  ELF fine). The **legacy-build** package PASSES; a **jammy-native**
  (`ubuntu:22.04`) package intentionally FAILS the glibc-2.34 / pthread /
  `__cxx11` checks — that is expected, not a regression.
- **Full smoke test** (CI primary gate `test-built-debian`): prepare the server
  tree on the host (`fetch-server.sh` → `apply-valve-rc-fix.sh` →
  `apply-srcds-patch.sh` → `KEEP_MAPS=de_dust2,de_inferno,de_nuke trim-server-maps.sh`,
  needs `unrar`), then boot `srcds` inside `debian:11` running `install-deps.sh` →
  `install-addons.sh` → `smoke-test.sh` with `SM_PACKAGE` / `MM_PACKAGE` set (without
  them `install-addons.sh` falls back to downloading rom4s 6572 + MM 1.10.6). The
  559 MB server zip is cached under `.ci-cache/`. It boots a 32-bit `srcds_i686`
  and probes `sm version` / `sm exts list` / `sm plugins list` via `expect`
  (~2 min). Pass `CSS34_LINE=<line>` (or the `*_EXPECT` variables) so the expected
  versions match the package.

### Lint
There is no dedicated linter/pre-commit config in this repo. The ABI export
check (`check-package.sh`) is the closest static verification of build output.

### Version pin bumps (Jules / agents)
Daily SM/MM tip bumps: follow `docs/JULES_DAILY_VERSION_BUMP.md`. After editing
pins, run `testing/scripts/check-version-pins.sh` (also enforced by
`.github/workflows/version-pins.yml` on PRs; it only covers `sm12-latest`,
`sm13-latest` and MM 1.12). Upstream tip probe:
`builder/scripts/resolve-upstream-tips.sh`.
