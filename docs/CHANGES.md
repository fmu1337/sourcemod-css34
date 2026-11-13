# What we change relative to upstream

Upstream SourceMod and Metamod:Source do not build or run correctly on CS:S v34 (Source 2006 /
episode1, 32-bit, old glibc). This file lists every change we make and why. Each patch lives in
`builder/patches/series/<line or MM_112>/<repo>/NNNN-*.patch`; `series.json` pins the upstream commit and
the exact tree the series must produce, so a patch that stops fitting fails the build.

**Upstream report?** marks changes that are upstream bugs worth filing (the owner files them; drafts
with reproduction steps are at
[`docs/upstream-reports` at `2dde54f`](https://github.com/fmu1337/sourcemod-css34/tree/2dde54f/docs/upstream-reports)).

## SourceMod patches

`sm13-latest` series; `sm12-latest` has the same patches (renumbered) except where noted.

| Patch | Upstream problem on CS:S v34 | Our change | Upstream report? |
|-------|------------------------------|------------|------------------|
| `0001-build-episode1-toolchain` | ConVars bind to `vstdlib` instead of the SDK's `tier1` (console commands break); pthread / rt not in `NEEDED` on glibc 2.17; GCC 10 `-Werror`; `logic.so` exports `std::` (srcds hangs) | episode1 link order, explicit `NEEDED`, link via the C++ driver, warning flags, hidden static libstdc++ | yes (link order, pthread / rt) |
| `0002-glibc217-database-imports` (sm13 only) | `libpq` imports `explicit_bzero`, MySQL imports `compress2` / `uncompress` unversioned (absent from glibc 2.17) | hidden `explicit_bzero`; zlib inside the static link group | — |
| `0003-cstrike-episode1` | `game.cstrike` is not built for episode1; EP1 `FindInDataMap` returns an incomplete `typedescription_t` | build it for EP1, `SE_EPISODEONE` guards, `FindDataMapInfo` | yes (`FindDataMapInfo`) |
| `0004-gameconfigs-rtld-noload` | `dlopen(engine_i486.so)` maps a second engine next to srcds' `engine_i686.so`; v34 engines export no `CreateInterface`, so `"library" "engine"` signatures resolve to 0 | `RTLD_NOLOAD`, find the module srcds already mapped | yes |
| `0005-sourcemm-api-safe-iface` | a NULL interface factory crashes at load | check for NULL, report the missing interface | — |
| `0006-gcc10-warnings` | `MIN()` breaks `-Werror` on GCC 10 | replace it in two units | — |
| `0007-css34-versioning` | shallow clones give a wrong build number | build number from `lines.json`; `CSS34 pack:` line in `sm version` | — |
| `0008-dbi-connect-options` (sm13 only) | core passes only the fixed `DatabaseInfo` fields to a DB driver | `IDBConnectOptions`: drivers can read any key of a `databases.cfg` entry | — |
| `0009-mysql-tls-options` (sm13 only) | MySQL driver never requests TLS and turns verification off; HeatWave / MySQL 8.4 `REQUIRE SSL` accounts are refused | `ssl_mode` / `ssl_ca` (see README), TLS 1.2+, `utf8mb4` | — |
| `0010-handlesys-lazy-table` | since 1.11.0.6792 the 2^20-entry handle table is zeroed at startup: +64 MB RSS in every srcds (156 MB vs 82 MB) | `calloc` instead of `new[]` + `memset`: 90 MB | — |
| `0011-no-gamedata-updater` | `updater.ext` overwrites the css34 gamedata with upstream's (no v34 entries) over plain HTTP | `updater.ext` and `webternet.ext` are not built or loaded | — |
| sm12 `0007-sdktools-onmapend-list` | the 1.12 cherry-pick of SM #2589 uses the wrong list type: GCC 10 fails | `SourceHook::List<omg_hooks *>`, as `OutputHookList` stores | yes (1.12-dev) |
| `sourcepawn/0001-gcc10-link-flags` | GCC 10 sign-compare errors; pthread / rt not in `NEEDED` | `-Wno-sign-compare`, explicit `NEEDED` | yes (pthread / rt) |
| `hl2sdk-manifests/0001-episode1-defines` | the SDK's malloc hooks end up in SourceMod modules | `NO_HOOK_MALLOC`, `NO_MALLOC_OVERRIDE` for episode1 | — |
| `hl2sdk-manifests/0002-compiler-flag-guard` | manifests pass flags GCC 10 does not know | drop unknown flags | — |

## Metamod 1.12 patches (`MM_112`, shared by both lines)

| Patch | Upstream problem | Our change | Upstream report? |
|-------|------------------|------------|------------------|
| `0001-build-episode1-toolchain` | as SourceMod `0001` | as SourceMod `0001` | yes (link order) |
| `0002-episode1-mem-h` | `MemAllocScratch` undeclared on episode1 | include `tier0/mem.h` | yes |
| `0003-css34-versioning` | shallow clone gives a wrong build number | build number from `lines.json`, `CSS34 pack:` in `meta version` | — |
| `hl2sdk-manifests/0001`, `0002` | as in SourceMod | as in SourceMod | — |

## Ours, not in upstream

- **CS:S v34 gamedata** (`builder/assets/gamedata/`, checked by `check-css34-gamedata.py`): v34 vtable
  offsets for SDKHooks / SDKTools (upstream's are for Steam CS:S and crash), `HintTextPreByte` (without
  it the v34 client shows no hint text), `HudTextMsg` kept (ClientMod draws it; the stock client may not),
  no `GetMaxHealth` hook (not virtual on v34; read `m_iMaxHealth` instead), `VPhysicsUpdate` 143.
- **Legacy-plugin bridge** (`builder/patches/mm-oldbridge/`): every MM 1.12 package also ships the
  MM 1.10.7 core `metamod.1.ep1`, and MM 1.12 hands PLAPI 7–12 plugins from `metaplugins.ini` to it.
- **Build for old Linux**: manylinux2014 i686 (glibc 2.17, GCC 10), static hidden libstdc++, every ELF
  checked for GLIBC ≤ 2.17 and unversioned imports (`testing/unversioned-imports.txt`).
- **sm13 MySQL stack**: OpenSSL 3.5 LTS and MariaDB Connector/C 3.4.9 built from pinned sources
  (AlliedModders' connector binary is built against OpenSSL 1.1); OpenSSL's libc `getentropy` probe
  compiled out (glibc 2.17).
