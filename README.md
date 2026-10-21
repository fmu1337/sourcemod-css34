# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) + [Metamod:Source](https://www.sourcemm.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy).

All packages are **pure-source** (`PURE_SOURCE_BUILD=1`): no rom4s/reference `.so` splicing. Smoke asserts SDK Hooks load and the css34 `OnTakeDamage` gamedata (linux **61**). Botplay hooks `SDKHook_OnTakeDamage` and logs hits.

Docs: [docs/README.md](docs/README.md) (index — current reference vs. history). Known doc/project inconsistencies and simplification proposals: [docs/REVIEW_2026-10.md](docs/REVIEW_2026-10.md).

## What to install

Use a **line pointer**: one fixed URL per line that always serves the newest build of that line that passed the public-URL smoke test.

```
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/mmsource-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/sourcemod-css34-linux.tar.gz
```

<!-- lines-install:begin -->
| `<line>` | SourceMod | Metamod | Role |
|----------|-----------|---------|------|
| `sm13-latest` | 1.13.0.7478 | 1.12.0 git1228 | **Default / recommended** |
| `sm12-latest` | 1.12.0.7257 | 1.12.0 git1228 | Latest 1.12 |
| `sm13-mm20-khook` | 1.13.0.7565 (KHook branch + master) | 2.0.0 git1472 (KHook) | Frozen outside CI; archived builder, ships `dhooks.ext` |
| `sm13-mm20` | 1.13.0.7404 | 2.0.0 git1407 (last SourceHook MM 2.0) | Retired outside CI |
<!-- lines-install:end -->

`sm11-oldstable` (SM 1.11.0.6970 + MM 1.10.7) has **no pointer** — see [Known-bad releases](#known-bad-releases).
What each pointer serves right now (tag, commits, smoke result) is in
[`lines-index/lines.json`](https://github.com/fmu1337/sourcemod-css34/releases/download/lines-index/lines.json).

```bash
tar -xzf mmsource-css34-linux.tar.gz  -C /path/to/cstrike
tar -xzf sourcemod-css34-linux.tar.gz -C /path/to/cstrike
```

Always install MM and SM **from the same line** (same pointer or same tag). Windows packages are only
attached to the per-tag releases (pointers are Linux-only).

## Version matrix (current pins)

<!-- lines-versions:begin -->
| Line (`CSS34_LINE`) | SourceMod | Metamod | Role |
|---------------------|-----------|---------|------|
| `sm11-oldstable` | **1.11.0.6970** (`f53cb134…`) | **1.10-dev git976** (`80e8ff0b…`) | OldStable, withheld from pointers |
| `sm12-latest` | **1.12.0.7257** (`e68dada2…`) | **1.12 git1228** (`cb477558…`) | Latest 1.12 |
| `sm13-latest` | **1.13.0.7478** (`b34de51b…`) | **1.12 git1228** (`cb477558…`) | Latest 1.13 (default) |
| `sm13-mm20` | 1.13.0.7404 (`cdedec76…`) | 2.0 git1407 (last SourceHook MM 2.0) (`0084b86a…`) | Retired outside CI ([docs](docs/SM13_MM20.md)) |
| `sm13-mm20-khook` | **1.13.0.7565** (KHook branch + master) (`25954d4a…`) | **2.0 git1472 (KHook)** (`05c5c63a…`) | Frozen outside CI ([docs](docs/MM20_KHOOK.md)) |
<!-- lines-versions:end -->

`sm13-dev` (7404 + MM 1.12) is **retired** — use `sm13-latest`. Its alias stays in `resolve-version.sh` /
`release.yml` only so the `1.13.0.7404-mm1.12.0` tag can be rebuilt.

Pins live in [`builder/lines.json`](builder/lines.json). `python3 builder/lines.py gen` writes
[`builder/versions.env`](builder/versions.env), [`builder/generated/ci-matrix.json`](builder/generated/ci-matrix.json),
[`builder/generated/tag-map.sh`](builder/generated/tag-map.sh), and the two tables above.
`python3 builder/lines.py check` fails when a generated file is stale, a line lists the same image twice,
or a known-bad tag is pinned on a line that publishes a pointer.
The manifest records line status and known-bad release tags; it is separate from the published pointer index.
Resolver: [`builder/resolve-version.sh`](builder/resolve-version.sh).
A daily bump edits `lines.json` and regenerates — see [docs/JULES_DAILY_VERSION_BUMP.md](docs/JULES_DAILY_VERSION_BUMP.md).

> `meta version` prints the Metamod build number from `lines.json` (`1.12.0-dev+1228`,
> or `1.10.7-dev+976` on `sm11-oldstable`) and `Build ID: <rev>:<commit prefix>`.
> `sm version` prints `<major>.<minor>.0.<SM_REV>` (for example `1.13.0.7478`).
> The clones stay shallow; `generate_headers.py` reads `MMS_GIT_REV` / `SOURCEMOD_GIT_REV`.

### What pairs with what

| | SM 1.11 (PLAPI 11, `1.ep1`) | SM 1.12 / 1.13 (`2.ep1`) |
|--|--|--|
| **MM 1.10** (`metamod.1.ep1`) | **matched** (`sm11-oldstable`) | no |
| **MM 1.11** (`metamod.2.ep1`) | no (myarena bundle; `11 < 14`) | not a release path |
| **MM 1.12** git1228 | no | **matched** (`sm12-latest`, `sm13-latest`) |
| **MM 2.0** git1407 | no | experimental (`sm13-mm20`) |
| **MM 2.0** git1450+ (KHook, no SourceHook) | no | only the SM KHook branch (`sm13-mm20-khook`); SM `master` cannot run on it |

## Releases

A tag pins one SM + MM pair; never mix Metamod from one tag with SourceMod from another.
A rebuild of the same pins gets a `-r<N>` suffix (tags are never moved); `release.yml` maps
`<tag>-r<N>` to the same line as `<tag>`.

**Current builds** (what the line pointers serve, built from `88713a7`, every asset in `SHA256SUMS`):

| Tag | Line | SourceMod | Metamod |
|-----|------|-----------|---------|
| [`1.13.0.7472-mm1.12.0-r2`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7472-mm1.12.0-r2) | `sm13-latest` | 1.13.0-git7472 | 1.12.0 git1226 |
| [`1.12.0.7253-mm1.12.0-r2`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.12.0.7253-mm1.12.0-r2) | `sm12-latest` | 1.12.0-git7253 | 1.12.0 git1226 |
| [`1.13.0.7565-mm2.0.0-khook-dhooks-r2`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7565-mm2.0.0-khook-dhooks-r2) | `sm13-mm20-khook` | 1.13.0-git7565 (KHook branch + master), + `dhooks.ext` | 2.0.0 git1472 (KHook) |
| [`1.13.0.7404-mm2.0.0-r2`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7404-mm2.0.0-r2) | `sm13-mm20` | 1.13.0-git7404 | 2.0.0 git1407 |

**Earlier tags** (same pins, older packaging: no `SHA256SUMS`, no `css34-package.json`). The seven tags of the
current lines were moved to `b1f5192` and rebuilt on 2026-10-12, before the `-r<N>` rule existed:

| Tag | Line | SourceMod | Metamod | Notes |
|-----|------|-----------|---------|-------|
| [`1.11.0.6970-mm1.10.7`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.11.0.6970-mm1.10.7) | `sm11-oldstable` | 1.11.0-git6970 | 1.10.7-dev (`metamod.1.ep1`) | Linux only; withheld (below) |
| [`1.12.0.7253-mm1.12.0`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.12.0.7253-mm1.12.0) | `sm12-latest` | 1.12.0-git7253 | 1.12.0-dev (git1226) | |
| [`1.13.0.7472-mm1.12.0`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7472-mm1.12.0) | `sm13-latest` | 1.13.0-git7472 | 1.12.0-dev (git1226) | |
| [`1.13.0.7404-mm2.0.0`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7404-mm2.0.0) | `sm13-mm20` | 1.13.0-git7404 | 2.0.0-dev (git1407) | |
| [`1.13.0.7565-mm2.0.0-khook`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7565-mm2.0.0-khook) | `sm13-mm20-khook` | 1.13.0-git7565 | 2.0.0-dev (git1472, `05c5c63`) | |
| [`1.13.0.7565-mm2.0.0-khook-dhooks`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7565-mm2.0.0-khook-dhooks) | `sm13-mm20-khook` | 1.13.0-git7565, + `dhooks.ext` | 2.0.0-dev (git1472, `05c5c63`) | |
| [`1.13.0.7404-mm1.12.0`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7404-mm1.12.0) | `sm13-dev` (retired) | 1.13.0-git7404 | 1.12.0-dev (git1226) | historical |
| `1.11.0.6572-mm1.10.7`, `1.12.0.7245-mm1.12.0` | pre-matrix | 6572 / 7245 | 1.10.7-dev / 1.12.0-dev (git1224) | historical, superseded |
| `1.12.0.7239-mm1.12.0`, `1.13.0.7394-mm1.12.0` | pre-matrix | 7239 / 7394 | 1.12.0-dev | **known-bad** (below) |

Asset names: `sourcemod-<ver>-git<rev>-css34-{linux.tar.gz|windows.zip}`; Linux Metamod is
`mmsource-<ver>-git<mmrev>-css34-linux.tar.gz` on the `-r2` tags and `mmsource-<ver>-dev-css34-linux.tar.gz`
on older ones; Windows Metamod is still `mmsource-<ver>-dev-css34-windows.zip` everywhere.

### Installer contract (fmu1337/v34_server_base)

**Stable line pointers.** Each live line has one published release with a fixed tag and fixed asset names:

```
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/sourcemod-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/mmsource-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/SHA256SUMS
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/lines.json
```

`<line>` ∈ `sm12-latest`, `sm13-latest`, `sm13-mm20`, `sm13-mm20-khook`. Both files use the same format,
`{line: {tag, sm_version, sm_commit, mm_version, mm_commit, extension_api, extension_api_min, metamod_binary, smoke, …}}`:

- `line-<line>/lines.json` holds only that line's entry (written by that line's runs only);
- `lines-index/lines.json` holds every line, rebuilt from all `line-*/lines.json`.

A pointer is created on the first tag release of its line. A line whose builds never passed smoke has a
pointer release with only `lines.json` (`"tag": null, "smoke": "fail"`).

`release.yml` switches a pointer only after `smoke-release` installed the **public** tag URLs with a plain
`tar -x` and booted `srcds`; a red smoke leaves the pointer on the previous build (`lines.json[line].candidate`
records the failed tag). Pointer assets are replaced upload-first (`<name>.next-<run>` → delete old → rename),
so the URL serves the old file during a rebuild; the only gap is two back-to-back API calls. `smoke-pointer`
then re-runs the smoke against the pointer URLs.

Several lines may be tagged at once: pointer updates are serialized per line, and the shared
`lines-index/lines.json` is rebuilt from the per-line files and re-checked after upload, so parallel runs
cannot drop each other's entries. Two tags of the *same* line finishing out of order never move the pointer
back: an update whose tagged commit is older than the one served is skipped.

**Releases never go back to draft.** `release.yml` only uploads into an existing release
(`--clobber`) and re-publishes it if it is a draft. Drafts that already exist can be re-published with
the *Release Maintenance* workflow (Actions → Release Maintenance → Run).

**Manifest in every package** (tags built after #69, i.e. the `-r2` tags and the pointers).
`addons/sourcemod/css34-package.json` and `addons/metamod/css34-package.json`:
`line, sm_version, sm_commit, mm_version, mm_commit, extension_api, extension_api_min, metamod_binary, build_date`.
`extension_api` / `extension_api_min` are `SMINTERFACE_EXTENSIONAPI_VERSION` / `_MIN` of the build
(SM 1.11/1.12 have no `_MIN` → `1`; 1.12.0.7253: 8; 1.13.0.7404: 9–9; 1.13.0.7472 / 7565: 9–11).

**Ready to run.** `tar -xzf mm.tgz -C cstrike && tar -xzf sm.tgz -C cstrike` is the whole install:
`addons/metamod/sourcemod.vdf`, `"DisableAutoUpdate" "yes"` in `configs/core.cfg` (SourceMod's key for
turning the updater off), executable `*.so` / `scripting/spcomp`, and on SM 1.12+
`configs/geoip/GeoLite2-Country.mmdb` (mode 0644 — older packages shipped it 0600, unreadable for a
non-root srcds). `testing/scripts/check-package.sh` enforces all of it.

### Known-bad releases

- **`1.13.0.7394-mm1.12.0` and `1.12.0.7239-mm1.12.0`: SDKHooks broken.** The packages have no
  `gamedata/sdkhooks.games/game.cstrike.txt` and `master.games.txt` is upstream's (no `game.cstrike.txt` entry),
  so *every* SDKHooks offset is missing and `SDKHook()` throws `Hook type not supported on this game` for all
  types (SMAC `smac_wallhack` FarESP hits it first on `SDKHook_ThinkPost` / `SetTransmit`). Fixed in every
  build since (`package.sh` and `check-package.sh` require the css34 file); use `line-sm13-latest` /
  `line-sm12-latest`. Botplay's API probe `SDKHookEx`-checks the SMAC hook types, and `check-sm-logs.sh` fails
  on that message.
- **`1.11.0.6970-mm1.10.7` (`sm11-oldstable`): withheld from line pointers.** Reported SIGABRT at startup
  without plugins on rom4s 4044 + bufferfix + `srcds_i686` on Ubuntu 24.04 (our debian:11 smoke passes).
  Root cause is not yet reproduced here; until it is, there is no `line-sm11-oldstable` pointer and
  installers should use rom4s 1.11.0.6572 + MM 1.10.6 for SM 1.11. The tag itself stays published
  (Linux assets only).
- **Windows assets of `1.13.0.7565-mm2.0.0-khook*`.** The first uploads crashed `srcds.exe` on the first map
  load (KHook recall on MSVC x86). Both tags now point at `b1f5192`, which carries the fix, and their assets
  were re-uploaded from it on 2026-10-12, but those exact files never went through the Wine smoke. Prefer
  `1.13.0.7565-mm2.0.0-khook-dhooks-r2`. Fix and Wine / native Windows smoke:
  [docs/MM20_KHOOK.md](docs/MM20_KHOOK.md#windows).

**Install traps**

- SM **1.11** expects Metamod **1.10.x / `metamod.1.ep1` / PLAPI 11**. A leftover myarena `metamod.2.ep1.so`
  (MM 1.11) → `Older Metamod… (11 < 14)` — not a bad package, a mix. See
  [docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md](docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md).
- Installing over an old SourceMod: delete a flat `gamedata/sm-cstrike.games.txt` left from older drops
  (`[CSTRIKE] Could not locate HandleCommand_Buy`); ours lives in `gamedata/sm-cstrike.games/`.
- Historical community URLs (rom4s / myarena) for local compare: [`testing/versions/matrix.json`](testing/versions/matrix.json) (`reference` section).

## Build (pure-source)

Needs Docker. The build runs in pinned `quay.io/pypa/manylinux2014_i686` (glibc 2.17, GCC 10.2.1). SDKs, AMBuild and static OpenSSL 1.1.1w are fetched into `deps/`.

```bash
git submodule update --init --recursive

# Default (SM 1.13.7478 + MM 1.12.1228):
CSS34_LINE=sm13-latest builder/docker/build.sh

# Other lines:
CSS34_LINE=sm11-oldstable  builder/docker/build.sh
CSS34_LINE=sm12-latest     builder/docker/build.sh
```

`builder/docker/legacy-build.sh` calls `build.sh`.

MM 2.0 builds (`sm13-mm20`, `sm13-mm20-khook`) are archived outside CI in
[`archive/khook`](https://github.com/fmu1337/sourcemod-css34/tree/archive/khook).
Use that branch to reproduce them; master rejects those build selections. Existing
release assets, line IDs and pointer URLs remain available.

`builder/package-paths.sh` resolves exact Linux package names from the selected
line and revisions. Stale packages cannot silently replace the expected build.
No root package symlinks are created.

`PURE_SOURCE_BUILD=1` is the default. Packages land in `packages/`. `build.sh` builds in
manylinux2014 (glibc 2.17). `check-package.sh` fails the package if any ELF needs a
GLIBC newer than `GLIBC_FLOOR` (default 2.17).

`builder/run/linux.sh` on a normal distro still defaults to clang-9 (`USE_CLANG9=1`).
That path is not what CI ships. Inside the manylinux image it uses devtoolset-10 GCC.

Windows (x86 MSVC env):

```bash
CSS34_LINE=sm13-latest builder/run/windows.sh
```

## CI

- `.github/workflows/test-server.yml` — the real gate (push to `master` / `cursor/**`, PRs; `docs/**` and `*.md` are ignored).
  Builds **three active** lines (`sm11-oldstable`, `sm12-latest`, `sm13-latest`) with `builder/docker/build.sh` + `check-package.sh` / `check-metamod-package.sh`;
  smoke on `debian:11`, `ubuntu:24.04` and `debian:13` for every active line, plus `rockylinux:9` and the ubuntu-22.04 host for
  `sm13-latest`; **botplay-stress matrix** on `debian:11` for all lines
  (SMAC + SDKHooks OnTakeDamage + SM API / cstrike / DHooks probes). Packages pass between jobs via
  **Actions cache**. Reference (rom4s / published-release) botplay, extra distros and bisect are
  `workflow_dispatch` opt-ins.
- `.github/workflows/build.yml` — Linux build of `sm13-latest` with `builder/docker/build.sh`
  (manylinux2014); **Windows** build of `sm13-latest`, booted
  natively on `windows-latest` and under Wine (`wine-smoke`).
- `.github/workflows/release.yml` — tag-driven; tag (minus `-r<N>`) maps to `CSS34_LINE`; packages attach with
  `gh release upload` (**GitHub Releases**, not Actions artifacts); then `SHA256SUMS`, public-URL smoke,
  line pointer, pointer smoke.
- `.github/workflows/version-pins.yml` — `python3 builder/lines.py check` on pin-related PRs.
- `.github/workflows/release-maintenance.yml` — re-publish releases that ended up as drafts.
- `.github/workflows/cleanup-artifacts.yml` — weekly / manual purge of Actions artifacts.

Failure logs remain downloadable for seven days after a run. Scheduled cleanup keeps other
artifacts for at least 72 hours and preserves failure logs for seven days. Only PR runs
cancel an older run of the same workflow/ref. Botplay baseline comparisons are informational;
server crashes and API/ABI probes still fail the job.

```bash
git tag 1.13.0.7472-mm1.12.0-r3 && git push origin 1.13.0.7472-mm1.12.0-r3   # rebuild sm13-latest
```

New pins need a new base tag. `release.yml` reads the tag map generated from `builder/lines.json`.

## Notes

- Docs index (current vs. history): [docs/README.md](docs/README.md).
- Patch layout and upgrade strategy: [docs/PATCH_STRATEGY.md](docs/PATCH_STRATEGY.md).
- SDKHooks EP1 / PLAPI traps: [docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md](docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md).
- Compatibility PASS/FAIL notes and historical URLs: [`testing/versions/matrix.json`](testing/versions/matrix.json). Live pins are [`builder/lines.json`](builder/lines.json).
- Smoke / botplay / Wine testing: [testing/README.md](testing/README.md).
