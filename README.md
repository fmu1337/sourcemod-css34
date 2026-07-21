# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) + [Metamod:Source](https://www.sourcemm.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy).

All CI packages are **pure-source** (`PURE_SOURCE_BUILD=1`): no rom4s/reference `.so` splicing. Smoke asserts SDK Hooks load and css34 `OnTakeDamage` gamedata (linux **61** / windows **60**). Botplay hooks `SDKHook_OnTakeDamage` and logs hits.

How we patch and upgrade SourceMod versions (one pin at a time vs layered patches) is documented in [docs/PATCH_STRATEGY.md](docs/PATCH_STRATEGY.md).
Why we do **not** chase byte-identical `.so` vs rom4s («SUPER GOLDEN») is in [docs/BYTE_MATCH.md](docs/BYTE_MATCH.md).

## Version matrix (current pins)

| Line (`CSS34_LINE`) | SourceMod | Metamod | Role |
|---------------------|-----------|---------|------|
| `sm11-oldstable` | **1.11.0.6970** (`f53cb134…`) | **1.10-dev** (`80e8ff0…`, `metamod.1.ep1`) | OldStable |
| `sm12-latest` | **1.12.0.7245** (`f8490c810…`) | **1.12 git1224** (`364cb6c…`, `metamod.2.ep1`) | Latest |
| `sm13-dev` | **1.13.0.7404** (`cdedec760…`) | **1.12 git1224** | DEV (default) |
| `sm13-mm20` | 1.13.0.7404 | **2.0 git1407** (`0084b86…`) | Experimental |
| `sm11-mm111` | 1.11.0.6970 | **1.11-dev** (`7ff2d97…`) | Exploratory (PLAPI mix risk) |

Pins live in [`builder/versions.env`](builder/versions.env). Resolver: [`builder/resolve-version.sh`](builder/resolve-version.sh).

### What pairs with what

| | SM 1.11 (PLAPI 11, `1.ep1`) | SM 1.12 / 1.13 (`2.ep1`) |
|--|--|--|
| **MM 1.10** (`metamod.1.ep1`) | **matched** (`sm11-oldstable`) | no |
| **MM 1.11** (`metamod.2.ep1`) | exploratory only | not a release path |
| **MM 1.12** git1224 | no | **matched** (`sm12-latest`, `sm13-dev`) |
| **MM 2.0** git1407 | no | experimental (`sm13-mm20`) |

Do **not** install leftover myarena `metamod.2.ep1` / MM 1.11 under SM 1.11 — you get `Older Metamod… (11 < 14)`.

## Build (pure-source)

```bash
git submodule update --init --recursive

# Default DEV line (SM 1.13.7404 + MM 1.12.1224):
CSS34_LINE=sm13-dev PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh

# OldStable / Latest:
CSS34_LINE=sm11-oldstable PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh
CSS34_LINE=sm12-latest    PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh

# Mix MM on a line:
CSS34_LINE=sm13-dev MMS_LINE=2.0 PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh
```

Host / jammy-native (ABI may fail legacy smoke):

```bash
CSS34_LINE=sm13-dev PURE_SOURCE_BUILD=1 builder/run/linux.sh
```

Windows (x86 MSVC env):

```bash
CSS34_LINE=sm13-dev PURE_SOURCE_BUILD=1 builder/run/windows.sh
```

## CI

- `.github/workflows/build.yml` — default `CSS34_LINE=sm13-dev`, pure-source Linux + Windows
- `.github/workflows/test-server.yml` — builds **sm11-oldstable**, **sm12-latest**, **sm13-dev**; smoke on Debian 11 (all three) + Debian latest / Rocky / host for sm13; forces `sm exts load sdkhooks` and checks OnTakeDamage gamedata
- `.github/workflows/release.yml` — tag-driven; set `CSS34_LINE` to match the tag

```bash
git tag 1.13.0.7404-mm1.12.0
git push origin 1.13.0.7404-mm1.12.0
```

## Install

Extract **matched** MM then SM from the same line into `cstrike`:

```bash
tar -xzf mmsource-*-css34-linux.tar.gz -C /path/to/cstrike
tar -xzf sourcemod-*-css34-linux.tar.gz -C /path/to/cstrike
```

## Notes

- Patch strategy: [docs/PATCH_STRATEGY.md](docs/PATCH_STRATEGY.md). 6970 carries API/toolchain shims from the old ≥6800 notes.
- SDKHooks EP1 / PLAPI traps: [docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md](docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md).
- Machine-readable pins: [`testing/versions/matrix.json`](testing/versions/matrix.json) (updated with this matrix when present on the branch).
