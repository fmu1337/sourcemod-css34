# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **build system** (not a long-running app). It compiles patched
**Metamod:Source 1.10.7 + SourceMod 1.11.0.6572** packages for **Counter-Strike:
Source v34** and smoke-tests them on a real `srcds` dedicated server. See
`README.md`, `testing/README.md`, and `.github/workflows/` for the canonical
commands; the notes below only cover non-obvious environment caveats.

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
- **CI `build.yml` equivalent** (jammy-native artifacts): run `builder/run/linux.sh`
  inside `ubuntu:22.04` with `SKIP_APT_INSTALL=1`, `CC=gcc-9`, `CXX=g++-9`,
  `WDIR/DEPS_DIR/PACKAGES_DIR=/workspace/...`. Produces
  `packages/sourcemod-*-css34-linux.tar.gz` and `packages/mmsource-*-css34-linux.tar.gz`.
- **Smoke-test-compatible package** (CI `test-server.yml` path): run
  `builder/docker/legacy-build.sh` (builds in `debian:11` with the i386
  gcc-4.9 logic sysroot). This is the package that passes the ABI check and
  boots on legacy glibc. Prefer this when you need a package that actually loads
  in `srcds`.
- `git config --global --add safe.directory '*'` inside the container (the repo
  is bind-mounted and owned by uid 1000, git blocks submodule ops otherwise).
- The builder self-provisions all deps into `deps/` (clang-9 from bitbucket,
  MySQL SDK, hl2sdk clones, ambuild). Downloads come from github.com,
  bitbucket.org, cdn.mysql.com and archive.debian.org — all reachable.
- Known quirk: `builder/run/linux.sh` captures package-script stderr into the
  root-level `*.tar.gz` symlinks, creating a broken `mmsource-*.tar.gz` symlink
  at repo root. Ignore/delete it; the real artifacts live in `packages/`.

### Verifying / testing
- **Static ABI check** (CI `check-built-package`): `SM_PACKAGE=<pkg>
  testing/scripts/check-package.sh`. Uses host `binutils` (reads 32-bit ELF
  fine). The **legacy-build** package PASSES; a **jammy-native** (`ubuntu:22.04`)
  package intentionally FAILS the glibc-2.34 / pthread / `__cxx11` checks — that
  is expected, not a regression.
- **Full smoke test** (CI primary gate `test-built-debian`): prepare the server
  tree on the host (`fetch-server.sh` → `apply-valve-rc-fix.sh` →
  `apply-srcds-patch.sh` → `trim-server-maps.sh`, needs `unrar`), then boot
  `srcds` inside `debian:11` running `install-deps.sh` → `install-addons.sh` →
  `smoke-test.sh`. The 559 MB server zip is cached under `.ci-cache/`. It boots
  a 32-bit `srcds_i686` and probes `sm version` / `sm exts list` / `sm plugins
  list` via `expect` (~2 min).

### Lint
There is no dedicated linter/pre-commit config in this repo. The ABI export
check (`check-package.sh`) is the closest static verification of build output.
