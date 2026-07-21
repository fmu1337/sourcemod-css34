# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy builds).

The repository tracks upstream SourceMod as a git submodule and produces packages matching the original [v1.11.0.6572 release](https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572) layout:

- `sourcemod-1.11.0-git6572-css34-linux.tar.gz`
- `sourcemod-1.11.0-git6572-css34-windows.zip`
- `sourcemod.1.ep1.so` / `sourcemod.1.ep1.dll` and `sourcemod.2.ep1.so` / `sourcemod.2.ep1.dll`
- `game.cstrike.ext.1.ep1.so` / `.dll` and `game.cstrike.ext.2.ep1.so` / `.dll`
- MySQL and SQLite DBI extensions

## Build locally (Linux)

```bash
git submodule update --init --recursive
chmod +x builder/run/linux.sh builder/checkout-deps.sh builder/package.sh builder/patches/*.sh
builder/run/linux.sh
```

The script installs multilib packages, pins SourceMod to the v1.11.0.6572 commit, downloads dependencies, applies compatibility patches, builds **Metamod:Source** (`metamod.1.ep1.so` with css34 header patches), and writes:

- `packages/mmsource-1.10.7-dev-css34-linux.tar.gz`
- `packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz`

To build and test a package containing no SourceMod/Metamod binaries copied
from a reference release, use:

```bash
PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh
```

This disables the optional `sourcemod.logic.so` and `bintools.ext.so` reference
fallbacks. The Test Server workflow runs in this pure-source mode.

Linux builds use **gcc-9** multilib on Ubuntu 22.04 (clang-9 from the original rom4s Travis builder is fragile on modern hosts). Before packaging, binaries are stripped, upstream translations are bundled, and gamedata is trimmed to the CS:S v34 layout.

Override the pinned SourceMod commit if needed:

```bash
SOURCEMOD_COMMIT=832519ab647cdecb85763918dbfed1cb5e79c6cb builder/run/linux.sh
```

## Build locally (Windows)

Requires Visual Studio Build Tools with the x86 MSVC toolset, Python 3, and Git Bash (or WSL).

```bash
git submodule update --init --recursive
# Open "x86 Native Tools Command Prompt for VS" or run vcvarsall.bat x86 first
builder/run/windows.sh
```

The script builds Metamod + SourceMod and writes:

- `packages/mmsource-1.10.7-dev-css34-windows.zip`
- `packages/sourcemod-1.11.0-git6572-css34-windows.zip`

## CI

GitHub Actions workflow `.github/workflows/build.yml` runs the Linux and Windows builds on pushes and pull requests.

Release builds publish from **tags** only. Short tag format for this branch:

```text
1.13.0.7394-mm1.12.0
```

Push a matching tag on **this branch tip** (not `master`) to run `.github/workflows/release.yml`, which builds SM + MM for Linux and Windows and attaches the four packages to a GitHub Release.

```bash
git tag 1.13.0.7394-mm1.12.0
git push origin 1.13.0.7394-mm1.12.0
```

Other version lines (tags point at their own branch tips):

- master / sm11: `1.11.0.6572-mm1.10.7` (already released)
- sm12 PR branch: `1.12.0.7239-mm1.12.0`

`.github/workflows/test-server.yml` builds **our** Metamod 1.12 + SourceMod 7394 packages and smoke-tests them on a real CS:S v34 dedicated server under Debian 11 / 12 / 13 / Latest, Rocky Linux 9, and the Ubuntu 22.04 host runner.

It applies the modern-OS buffer fix (`srcds_patch` + `valve.rc`), loads our Metamod + SourceMod, and asserts console markers. Details: [`testing/README.md`](testing/README.md), buffer-fix notes: [`testing/docs/bufferfix.md`](testing/docs/bufferfix.md).

## Install

Extract the Metamod package into the CS:S v34 server `cstrike` directory first, then SourceMod.

Linux:

```bash
tar -xzf mmsource-1.10.7-dev-css34-linux.tar.gz -C /path/to/cstrike
tar -xzf sourcemod-1.11.0-git6572-css34-linux.tar.gz -C /path/to/cstrike
```

Windows: unzip `mmsource-*-css34-windows.zip`, then `sourcemod-*-css34-windows.zip`, into `cstrike`.

## Notes

- Builds against `rom4s/hl2sdk-ep1c` (ep1) and `alliedmodders/hl2sdk` episode1, like the original builder.
- MySQL extension (`dbi.mysql.ext.so`) is included by default.
- 32-bit (`x86`) binaries are produced for compatibility with the v34 dedicated server.
