# Reproducible build (rom4s v1.11.0.6572)

Attempts to rebuild the original Linux release as closely as possible.

## Recommended: Ubuntu 14.04 Docker (closest to original Travis)

```bash
chmod +x builder/docker/trusty/run.sh
builder/docker/trusty/run.sh
```

This builds a Docker image (`ubuntu:14.04` + gcc-9-multilib + **Python 3.6.8** + rom4s clang-9) and runs `linux-repro-trusty.sh` inside it.

Manual:

```bash
sudo docker build -f builder/docker/trusty/Dockerfile -t sourcemod-css34-repro-trusty .
sudo rm -rf deps sourcemod/build   # avoid root-owned deps from container
sudo docker run --rm -v "$PWD:/src" -w /src -e WDIR=/src sourcemod-css34-repro-trusty \
  builder/run/linux-repro-trusty.sh
```

## Host repro (Ubuntu 22.04, jammy workarounds)

```bash
builder/run/linux-repro.sh
```

Uses clang-9 wrappers (`-nostdinc++`, libtinfo5). Further from original than Docker/trusty.

## Compare against original release

```bash
builder/compare-release.sh packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz
```

## Current results

### Ubuntu 14.04 Docker + pinned deps + native clang-9

| Metric | Result |
|---|---|
| Native `.so` byte-identical | **0 / 20** |
| Native `.so` **same size** as original | **9 / 20** |
| Other package files | **867 match**, 40 differ |

Same-size `.so` files: `sourcemod.logic`, `bintools`, `dbi.mysql`, `dbi.sqlite`, `geoip`, `regex`, `topmenus`, `updater`, `webternet`.

Very close sizes: `sourcepawn.jit` (−110 B), `sourcemod_mm_i486` (−178 B), `clientprefs` (−22 B).

### Ubuntu 22.04 host repro

| Metric | Result |
|---|---|
| Native `.so` byte-identical | 0 / 20 |
| Closest `sourcemod.1.ep1.so` | 907 KB vs 951 KB original |

## Why not byte-identical yet

See **`builder/BINARY-DIFF.md`** for the full ELF-level analysis (original vs trusty repro).

Short version:

1. **`sourcemod-css34-builder` is deleted** — patch set is reconstructed, not exact.
2. **8 simple extensions** already match code sections; diffs are gcc version string + BSS padding.
3. **4 SDK/game modules** (`sourcemod.1.ep1`, `sdkhooks`, `sdktools`, `game.cstrike`) have +50–65 KB `.text` — hl2sdk/sourcemod patch gap.
4. **40 non-binary diffs** remain (plugins `.smx`, gamedata, etc.) even with `ORIGINAL_TRANSLATIONS=1`.

## Settings

| Variable | Default (repro) | Purpose |
|---|---|---|
| `REPRO_BUILD=1` | set by repro scripts | Pin deps in `checkout-deps.sh` |
| `CLANG9_NATIVE=1` | trusty entrypoint | Bare rom4s clang-9, no jammy wrappers |
| `STRIP_MODE` | `debug` | `none`, `debug`, or `unneeded` |
| `ORIGINAL_TRANSLATIONS` | `1` | Translations from original release tarball |

Pinned revisions: `builder/pins.env`
