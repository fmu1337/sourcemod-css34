# Reproducible build (rom4s v1.11.0.6572)

Attempts to rebuild the original Linux release as closely as possible.

## Run

```bash
chmod +x builder/run/linux-repro.sh builder/compare-release.sh builder/patches/*.sh
builder/run/linux-repro.sh
```

This uses:

- **clang-9** (rom4s tarball) — same compiler family as Travis Ubuntu 14.04
- **Pinned deps** from `builder/pins.env` (June 2020 revisions)
- **SourceMod** `832519ab` (git6572)
- **STRIP_MODE=debug** — keeps `.symtab` like the original release
- **ORIGINAL_TRANSLATIONS=1** — copies translations from the original release tarball (upstream SourceMod at 6572 only ships 21 phrase files; the release bundles 687)

Compare against the original artifact:

```bash
builder/compare-release.sh packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz
```

## Current results (Ubuntu 22.04 + jammy workarounds)

| Layer | Match vs original |
|---|---|
| Native `.so` binaries | **0 / 20** byte-identical |
| Other package files (with `ORIGINAL_TRANSLATIONS=1`) | ~201 / 241 comparable |

Closest `.so` size (after strip): `sourcemod.1.ep1.so` **907 KB** built vs **951 KB** original.

## Why byte-identical `.so` files are hard

1. **Original CI ran on Ubuntu 14.04 (trusty)** with bare `$HOME/clang-9/usrbin` — no jammy `-nostdinc++` wrappers.
2. **`sourcemod-css34-builder` is deleted** — exact 2020 patch set is lost; we reconstructed from Travis + artifact analysis.
3. **Our compatibility patches** (`apply-sourcemod.sh`, `apply-hl2sdk-ep1c.sh`) target modern hosts and differ from the lost builder.
4. **Debug codegen**: optimize builds emit `-g3`; original binaries have no `.debug_info` (stripped) but different code layout remains.

## Next step for closer binary match

Build inside **Ubuntu 14.04** with the rom4s clang tarball and no jammy-specific wrappers (Docker/VM). That removes glibc/header/wrapper drift.

## Environment variables

| Variable | Default (repro) | Purpose |
|---|---|---|
| `REPRO_BUILD=1` | set by `linux-repro.sh` | Pin deps in `checkout-deps.sh` |
| `STRIP_MODE` | `debug` | `none`, `debug`, or `unneeded` |
| `ORIGINAL_TRANSLATIONS` | `1` | Bundle translations from original release |
| `ORIGINAL_RELEASE_URL` | rom4s v1.11.0.6572 URL | Source for translations |
