# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy builds).

The repository tracks upstream SourceMod as a git submodule and produces Linux packages matching the original [v1.11.0.6572 release](https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572) layout:

- `sourcemod-1.11.0-git6572-css34-linux.tar.gz`
- `sourcemod.1.ep1.so` and `sourcemod.2.ep1.so`
- `game.cstrike.ext.1.ep1.so` and `game.cstrike.ext.2.ep1.so`
- MySQL and SQLite DBI extensions

## Build locally (Linux)

```bash
git submodule update --init --recursive
chmod +x builder/run/linux.sh builder/checkout-deps.sh builder/package.sh builder/patches/*.sh
builder/run/linux.sh
```

The script installs multilib toolchain packages, pins SourceMod to the v1.11.0.6572 commit, downloads dependencies, applies compatibility patches, and writes `packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz`.

Override the pinned SourceMod commit if needed:

```bash
SOURCEMOD_COMMIT=832519ab647cdecb85763918dbfed1cb5e79c6cb builder/run/linux.sh
```

## CI

GitHub Actions workflow `.github/workflows/build.yml` runs the same Linux build on pushes and pull requests.

## Install

Extract the tarball into your CS:S v34 server `cstrike` directory (Metamod:Source must already be installed):

```bash
tar -xzf sourcemod-1.11.0-git6572-css34-linux.tar.gz -C /path/to/cstrike
```

## Notes

- Builds against `rom4s/hl2sdk-ep1c` (ep1) and `alliedmodders/hl2sdk` episode1, like the original builder.
- MySQL extension (`dbi.mysql.ext.so`) is included by default.
- 32-bit (`x86`) binaries are produced for compatibility with the v34 dedicated server.
