# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy builds).

The repository tracks upstream SourceMod as a git submodule and produces packages for CS:S v34:

- `sourcemod-1.11.0-git6970-css34-linux.tar.gz`
- `sourcemod-1.11.0-git6970-css34-windows.zip`
- `sourcemod.1.ep1.so` / `sourcemod.1.ep1.dll` and `sourcemod.2.ep1.so` / `sourcemod.2.ep1.dll`
- `game.cstrike.ext.1.ep1.so` / `.dll` and `game.cstrike.ext.2.ep1.so` / `.dll`
- MySQL and SQLite DBI extensions

## v1.11.0.6970 vs v1.11.0.6572 (CS:S v34)

This branch updates the pinned upstream commit from **6572** (Jun 2020) to **6970** (Oct 2024).

### What matters for CS:S v34

| Area | Change |
|------|--------|
| **Gamedata** | `engine.ep1.txt` — `DispatchKeyValue`; `engine.css.txt` — `LookupAttachment`; `game.cstrike.txt` — `SetOwnerEntity`, `GetAttachment` |
| **SDKTools** | New natives: `SetEntityCollisionGroup`, `SetEntityOwner`, `EntityCollisionRulesChanged`, `LookupEntityAttachment`, `GetEntityAttachment` |
| **Core** | Bug fixes (menus, datapacks, sendprops, SQL, handles), updated SourcePawn compiler |
| **DHooks** | Bundled into SourceMod core (`extensions/dhooks`, `dhooks.ext`) — same extension name as standalone DHooks |
| **GeoIP** | GeoLite2 `.mmdb` format; database downloaded at package time into `configs/geoip/` |

### Compatibility patches (this repo)

- **`CS_OnCSWeaponDrop`** — forward signature updated with `bool donated=false` (always `false` on v34; CS:GO-only semantics upstream)
- **`SetCollisionGroup`** — deprecated stock wrapper with compile-time `#pragma deprecated`; calls `SetEntityCollisionGroup`
- **GeoIP** — `GeoLite2-Country.mmdb` fetched during packaging (P3TERX mirror)
- **DHooks** — upstream 6970 ships built-in `dhooks.ext`; remove any standalone DHooks extension from `extensions/` before upgrading to avoid duplicate load

### Not included (other games only)

TF2, L4D2, CS:GO gamedata updates, Entity Lump API, x64-specific fixes — trimmed from the release package.

## Build locally (Linux)

```bash
git submodule update --init --recursive
chmod +x builder/run/linux.sh builder/checkout-deps.sh builder/package.sh builder/prepare-package.sh builder/download-geolite2.sh builder/patches/*.sh
builder/run/linux.sh
```

The script installs multilib packages, pins SourceMod to the v1.11.0.6970 commit, downloads dependencies, applies CS:S v34 compatibility patches, and writes `packages/sourcemod-1.11.0-git6970-css34-linux.tar.gz`.

Linux builds use **gcc-9** multilib on Ubuntu 22.04. Before packaging, binaries are stripped, upstream translations are bundled, gamedata is trimmed to the CS:S v34 layout, and the GeoLite2 database is downloaded.

Override the pinned SourceMod commit if needed:

```bash
SOURCEMOD_COMMIT=f53cb134ef83b580c83e1f4bf35f60d11c4571dd SOURCEMOD_GIT_REV=6970 builder/run/linux.sh
```

## Build locally (Windows)

Requires Visual Studio Build Tools with the x86 MSVC toolset, Python 3, and Git Bash (or WSL).

```bash
git submodule update --init --recursive
# Open "x86 Native Tools Command Prompt for VS" or run vcvarsall.bat x86 first
builder/run/windows.sh
```

The script writes `packages/sourcemod-1.11.0-git6970-css34-windows.zip`.

## CI

GitHub Actions workflow `.github/workflows/build.yml` runs the Linux and Windows builds on pushes and pull requests.

## Install / upgrade from 6572

Extract the archive into your CS:S v34 server `cstrike` directory (Metamod:Source must already be installed).

Linux:

```bash
tar -xzf sourcemod-1.11.0-git6970-css34-linux.tar.gz -C /path/to/cstrike
```

Windows: unzip `sourcemod-1.11.0-git6970-css34-windows.zip` into `cstrike`.

**Plugin authors:** update `CS_OnCSWeaponDrop` to three parameters (third defaults to `false`), replace `SetCollisionGroup` with `SetEntityCollisionGroup`, and recompile plugins against the new `scripting/include`.

## Notes

- Builds against `rom4s/hl2sdk-ep1c` (ep1) and `alliedmodders/hl2sdk` episode1, like the original builder.
- MySQL extension (`dbi.mysql.ext.so`) is included by default.
- 32-bit (`x86`) binaries are produced for compatibility with the v34 dedicated server.
