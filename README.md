# sourcemod-css34

**English** | [Русский](README.ru.md)

Patched [SourceMod](https://www.sourcemod.net/) + [Metamod:Source](https://www.sourcemm.net/) for
**Counter-Strike: Source v34** (episode1, 32-bit), built from source for glibc 2.17+ Linux and Windows.
What we change and why: [docs/CHANGES.md](docs/CHANGES.md).

## Install

Each line has a pointer that always serves its newest build that passed smoke on the public URLs:

```
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/mmsource-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/sourcemod-css34-linux.tar.gz
```

<!-- lines-install:begin -->
| `<line>` | SourceMod | Metamod | Role |
|----------|-----------|---------|------|
| `sm13-latest` | 1.13.0.7488 (`5eb6a120…`) | 1.12.0 git1229 (`4e031eb5…`) | **Default** |
| `sm12-latest` | 1.12.0.7260 (`3f746067…`) | 1.12.0 git1229 (`4e031eb5…`) | Latest 1.12 |
| `sm11-oldstable` | 1.11.0.6970 (`f53cb134…`) | 1.12.0 git1227 (`75dd7b26…`) | Frozen, dual-core |
<!-- lines-install:end -->

```bash
tar -xzf mmsource-css34-linux.tar.gz -C /path/to/cstrike
tar -xzf sourcemod-css34-linux.tar.gz -C /path/to/cstrike
```

Always take Metamod and SourceMod from the same line (or the same tag). What each pointer serves now:
[`lines-index/lines.json`](https://github.com/fmu1337/sourcemod-css34/releases/download/lines-index/lines.json)
or the `line-<line>` release page. Windows zips are on the tag releases only. Coming from SM 1.7 / 1.8 /
1.11: [docs/MIGRATION.md](docs/MIGRATION.md). Third-party extensions: [docs/EXTENSIONS.md](docs/EXTENSIONS.md).

### sm11

`line-sm11-oldstable` also serves MM 1.10.7 as `mmsource-legacy-css34-linux.tar.gz`, for extensions that
exist only as `*.ext.1.ep1` (it runs the `1.ep1` SourceMod core; no DHooks).

## Compatibility

- **Old Metamod plugins** (PLAPI 7–12, built for MM 1.4–1.10) run on every MM 1.12 package: it also ships
  the MM 1.10.7 core `metamod.1.ep1` and hands such plugins to it. Keep your `metaplugins.ini`.
- **Old `.smx` plugins** load on 1.12 / 1.13 unchanged (CI loads plugins built by spcomp 1.7.3 and 1.11).
- **Extensions** built for SM ≤ 1.12 do not load on 1.13 (API 9–11) and vice versa: one build per line.
- Leftover `metamod.2.ep1.so` from a third-party MM 1.11 → `Older Metamod… (11 < 14)`: a mix, not a bad
  package. A flat `gamedata/sm-cstrike.games.txt` from an old drop breaks cstrike
  (`Could not locate HandleCommand_Buy`): delete it.
- No gamedata auto-updater: `updater.ext` would overwrite the v34 gamedata. Leftover
  `updater.ext.so` / `webternet.ext.so` from older packages are never loaded and can be deleted.

## MySQL HeatWave / MySQL 8.4 (`sm13-latest`)

`dbi.mysql` speaks `caching_sha2_password`, TLS 1.2/1.3 and `utf8mb4`. TLS is off unless the
`databases.cfg` entry asks for it:

```
"ssl_mode"  "verify_ca"              // disabled (default) | preferred | required | verify_ca | verify_identity
"ssl_ca"    "configs/mysql-ca.pem"   // relative to addons/sourcemod/
```

For HeatWave use at least `required`, better `verify_ca` with the DB system's CA. `preferred` falls back
to plaintext and checks no certificate. An unknown mode, or a verify mode without a readable CA, fails the
connect. Keys and values are those of [fmu1337/sm-dbi-mysql](https://github.com/fmu1337/sm-dbi-mysql), whose
default is `preferred`: entries that relied on it must now say so. `sm12-latest` cannot log in to
MySQL 8.4 / HeatWave.

## Known-bad releases

Never on a pointer; `known_bad` in `builder/lines.json`:

- `1.12.0.7239-mm1.12.0`, `1.12.0.7245-mm1.12.0`, `1.13.0.7394-mm1.12.0`: missing or wrong v34 gamedata
  (`SDKHook()` → `Hook type not supported on this game`).
- `1.11.0.6970-mm1.10.7`: SIGABRT at startup on new distributions, its `2.ep1` core does not load. Replaced
  by `1.11.0.6970-mm1.12.0-dual`.
- `1.11.0.6572-mm1.10.7`: Steam CS:S SDKTools offsets. Still published as a prerelease (the installer's
  Windows `--sm rom4s` path uses its MM 1.10.7 zip).

The Metamod 2.0 lines (`sm13-mm20`, `sm13-mm20-khook`) are archived: [docs/KHOOK.md](docs/KHOOK.md).

## Build

Needs Docker. Builds run in pinned `quay.io/pypa/manylinux2014_i686` (glibc 2.17, GCC 10); pins are in
[`builder/lines.json`](builder/lines.json).

```bash
CSS34_LINE=sm13-latest builder/docker/build.sh     # or sm12-latest; packages land in packages/
CSS34_LINE=sm13-latest builder/run/windows.sh      # Windows: windows-2022, MSVC 14.44
```

`sm11-oldstable` is rebuilt only from its freeze archive. Releases, pointers, bumps, the frozen line and
CI: [docs/MAINTAINING.md](docs/MAINTAINING.md). Tests: [testing/README.md](testing/README.md).
