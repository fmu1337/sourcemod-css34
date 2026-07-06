# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy builds).

The repository tracks upstream SourceMod as a git submodule and produces Linux packages with the CS:S v34 SDK ([rom4s/hl2sdk-ep1c](https://github.com/rom4s/hl2sdk-ep1c)).

## Build locally (Linux)

```bash
git submodule update --init --recursive
chmod +x builder/run/linux.sh builder/patches/*.sh
builder/run/linux.sh
```

The script installs multilib toolchain packages, downloads Metamod:Source and AMBuild, applies compatibility patches, and writes `sourcemod-css34-linux.tar.gz` to the repository root.

To include the MySQL DBI extension (`dbi.mysql.ext.so`), pass `ENABLE_MYSQL=1`. The builder downloads the legacy 32-bit MySQL 5.6 client SDK (~280 MB) on first use:

```bash
ENABLE_MYSQL=1 builder/run/linux.sh
```

Use `MYSQL_PATH` to point at an existing client SDK tree instead of downloading into `deps/mysql-5.5`.

## CI

GitHub Actions workflow `.github/workflows/build.yml` runs the same Linux build on pushes and pull requests.

## Install

Extract the tarball into your CS:S v34 server `cstrike` directory (Metamod:Source must already be installed):

```bash
tar -xzf sourcemod-css34-linux.tar.gz -C /path/to/cstrike
```

## Notes

- Only **CSS** (`-s css`) is built.
- MySQL extension is optional (`ENABLE_MYSQL=1`); SQLite (`dbi.sqlite.ext.so`) is always included.
- 32-bit (`x86`) binaries are produced for compatibility with the v34 dedicated server.
