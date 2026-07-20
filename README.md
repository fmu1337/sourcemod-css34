# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy builds).

How we patch and upgrade SourceMod versions (one pin at a time vs layered patches) is documented in [docs/PATCH_STRATEGY.md](docs/PATCH_STRATEGY.md).
Why we do **not** chase byte-identical `.so` vs rom4s («SUPER GOLDEN») is in [docs/BYTE_MATCH.md](docs/BYTE_MATCH.md).

## Status

**Production pin is done:** master builds and smoke-tests **SM 1.11.0.6572 + MM 1.10.7** end-to-end. Three matched release lines are published (Linux + Windows). CI on `master` is green for Build + Test Server (Debian 11/12/13/latest, Rocky 9, host smoke).

| Track | Role | Notes |
|-------|------|--------|
| **1.11 + MM 1.10.7** | Production / default | What `builder/run/*.sh` and CI smoke build every push |
| **1.12 + MM 1.12** | Alternate release | Built from upgrade branch; not the master pin |
| **1.13 + MM 1.12** | Alternate release | Same as 1.12 — published tag, botplay-checked |

Not a hard “all done forever”: published `1.11.0.6572-mm1.10.7` still needs a **retag** to pick up the #34 css34 `sdkhooks.games` overlay (wrong OnTakeDamage vtables in that tag; fixed on master). Multi-version is release tags + botplay, not parallel master CI.

## Releases (matched SM + MM)

Use the **matched** pair from one tag. Do not mix Metamod from one line with SourceMod from another.

| Tag | SourceMod | Metamod | Linux | Windows | Verified |
|-----|-----------|---------|-------|---------|----------|
| [`1.11.0.6572-mm1.10.7`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.11.0.6572-mm1.10.7) **(Latest)** | 1.11.0-git6572 | 1.10.7-dev (`metamod.1.ep1`) | SM + MM `.tar.gz` | SM + MM `.zip` | Smoke (CI every push); botplay vs rom4s baseline |
| [`1.12.0.7239-mm1.12.0`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.12.0.7239-mm1.12.0) | 1.12.0-git7239 | 1.12.0-dev | SM + MM `.tar.gz` | SM + MM `.zip` | Release botplay (SMAC stress) |
| [`1.13.0.7394-mm1.12.0`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7394-mm1.12.0) | 1.13.0-git7394 | 1.12.0-dev | SM + MM `.tar.gz` | SM + MM `.zip` | Release botplay (SMAC stress) |

Asset names follow `sourcemod-<ver>-css34-{linux.tar.gz\|windows.zip}` and `mmsource-<ver>-css34-{linux.tar.gz\|windows.zip}`.

### Compatibility matrix (what loads with what)

| Metamod ↓ \\ SourceMod → | rom4s / built **6572** (1.ep1, PLAPI 11) | our **1.12 / 1.13** release SM | myarena **6522** (2.ep1 only) |
|--------------------------|------------------------------------------|--------------------------------|--------------------------------|
| **Our / rom4s MM 1.10.x** (`metamod.1.ep1`) | **OK** — production path | Use matched **1.12/1.13** tag MM instead | **FAIL** (expected) |
| **Our MM 1.12** (release tags) | Prefer matched 1.11 tag | **OK** — matched 1.12 / 1.13 tags | Not supported |
| **myarena MM 1.11** (`metamod.2.ep1`, iface ≥14) | **OK** on same srcds (field/CI mix) | Not the release path | myarena bundle path |

**Install traps**

- Release SM **1.11** expects Metamod **1.10.x / `metamod.1.ep1` / PLAPI 11**. Leftover myarena `metamod.2.ep1.so` (`1.11.0-dev+1130`) → `Older Metamod… (11 < 14)` — not a bad package, a mix. Details: [docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md](docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md).
- SM **1.12+** needs a GeoIP2 `*.mmdb` under `configs/geoip/` for `geoip.ext` / SMAC (botplay installs it; packages may ship it via `prepare-package.sh`).
- Historical community URLs (rom4s / myarena) for local compare: [`testing/versions/matrix.json`](testing/versions/matrix.json).

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

Release builds publish from **tags** only. Short tag format:

```text
1.11.0.6572-mm1.10.7
```

Push a matching tag to run `.github/workflows/release.yml`, which builds SM + MM for Linux and Windows and attaches the four packages to a GitHub Release.

```bash
git tag 1.11.0.6572-mm1.10.7
git push origin 1.11.0.6572-mm1.10.7
```

`.github/workflows/test-server.yml` builds **our** Metamod 1.10.7 + SourceMod 6572 packages and smoke-tests them on a real CS:S v34 dedicated server under Debian 11 / 12 / 13 / Latest, Rocky Linux 9, and the Ubuntu 22.04 host runner.

On `cursor/**` pushes (and `workflow_dispatch`) it also runs botplay against rom4s baseline, built 1.11, and the published **1.12 / 1.13** release packages.

It applies the modern-OS buffer fix (`srcds_patch` + `valve.rc`), loads our Metamod + SourceMod, and asserts console markers. Details: [`testing/README.md`](testing/README.md), buffer-fix notes: [`testing/docs/bufferfix.md`](testing/docs/bufferfix.md).

## Install

Extract the Metamod package into the CS:S v34 server `cstrike` directory first, then SourceMod (same release tag).

Linux (1.11 example):

```bash
tar -xzf mmsource-1.10.7-dev-css34-linux.tar.gz -C /path/to/cstrike
tar -xzf sourcemod-1.11.0-git6572-css34-linux.tar.gz -C /path/to/cstrike
```

Windows: unzip `mmsource-*-css34-windows.zip`, then `sourcemod-*-css34-windows.zip`, into `cstrike`.

## Notes

- Builds against `rom4s/hl2sdk-ep1c` (ep1) and `alliedmodders/hl2sdk` episode1, like the original builder.
- MySQL extension (`dbi.mysql.ext.so`) is included by default.
- 32-bit (`x86`) binaries are produced for compatibility with the v34 dedicated server.
