# Compatibility patch inventory

## sm13-latest patch series (T3.4)

`builder/patches/series/sm13-latest/` is how sm13-latest is patched
(`apply-sourcemod.sh` applies the line's series with `apply-series.sh`; a line
without one fails). `series.json` names SourceMod `b34de51b` (1.13.0.7478) and the
tree each repository must have after `git apply --index`; the build fails on any
other result. The series was generated from the former scripted patcher
(`apply-sourcemod-v112.sh`, removed at the end of T3.4) on a clean
checkout with each file's original line endings kept (the old patcher rewrote
every source file to LF), and a full build from it matches the scripted build's
files, exports, `NEEDED` and `SONAME` (`compare-package-abi.py`).

| Patch | What | Why (failure without it) |
|-------|------|--------------------------|
| `sourcemod/0001-build-episode1-toolchain` | `AMBuildScript`: episode1 links static `tier1_i486.a` before `vstdlib`; `-lpthread -lrt -lgcc_s` kept `NEEDED`; link through the C++ driver; GCC 10 warning flags; `-static-libstdc++` with hidden symbols; dynamic `libgcc_s`. `core/logic/AMBuilder`: host static libstdc++, static SourcePawn before it, `--exclude-libs,ALL` + version script, css34 ABI defines. | ConVars imported from `vstdlib` instead of embedded (console commands break); pthread/rt missing on glibc 2.17; `ld` rejects driver flags; `-Werror` stops the build; `logic.so` exports `std::`/`__cxxabiv1` (srcds hang, `check-package.sh` fails). |
| `sourcemod/0002-glibc217-database-imports` | `pgsql`: hidden `explicit_bzero`; `mysql`: zlib inside the static link group. | Unversioned `explicit_bzero` / `compress2` / `uncompress` imports; see the sections below. |
| `sourcemod/0003-cstrike-episode1` | Build `game.cstrike` for episode1, extend its `SE_CSS` guards to `SE_EPISODEONE`, `FindDataMapInfo` in `GetPlayerVarAddressOrError`. | No cstrike extension on CS:S v34; EP1 `FindInDataMap` returns an incomplete `typedescription_t`. |
| `sourcemod/0004-gameconfigs-rtld-noload` | `CacheGameBinaryInfo` / `@`-signatures open already-mapped modules with `RTLD_NOLOAD`. | `dlopen(engine_i486.so)` + `dlclose` leaves dangling ConVars in `vstdlib` (srcds loads `engine_i686.so`). |
| `sourcemod/0005-sourcemm-api-safe-iface` | `GET_V_IFACE_*` check the factory for NULL before `VInterfaceMatch` and report which interface is missing. | A NULL factory on CS:S v34 dereferenced at load instead of a load error. |
| `sourcemod/0006-gcc10-warnings` | curl `-Wno-stringop-truncation`; `MIN()` replaced in two units. | `-Werror` build failures with GCC 10. |
| `sourcemod/0007-css34-versioning` | Build number from `SOURCEMOD_GIT_REV` (lines.json), detached/submodule HEAD in `Versioning`, `CSS34 pack:` line in `sm version`. | Shallow clones give a wrong build number; smoke checks the pack commit. |
| `sourcepawn/0001-gcc10-link-flags` | `-Wno-sign-compare`; pthread/rt/`-lgcc_s` `NEEDED`. | GCC 10 sign-compare errors in the JIT/compiler; missing `NEEDED` on glibc 2.17. |
| `hl2sdk-manifests/0001-episode1-defines` | episode1 Linux defines `NO_HOOK_MALLOC`, `NO_MALLOC_OVERRIDE`. | The SDK's malloc hooks/overrides in SourceMod modules on CS:S v34. |
| `hl2sdk-manifests/0002-compiler-flag-guard` | Drop manifest compiler flags GCC 10 does not know (formerly `manifest_flag_guard.py`). | Unknown-flag errors from newer manifests (hl2sdk-manifests `ebd6e10`). |

## sm12-latest patch series

`builder/patches/series/sm12-latest/` is made the same way for SourceMod `e68dada2`
(1.12.0.7257) and patches sm12-latest. Its patches are the
sm13 ones above except:

- no `glibc217-database-imports`: SM 1.12's database extensions need neither shim;
- `sourcemod/0007-sdktools-onmapend-list`: `EntityOutputManager::OnMapEnd` uses
  `SourceHook::List<omg_hooks *>`, the type `OutputHookList` stores (section
  "SM 1.12: entity-output map-end cleanup list type" below);
- `sourcepawn/0001-gcc10-link-flags` also fixes a sign-compare in `vm/shell/shell.cpp`.

A full build from the series matches the scripted build's files, exports, `NEEDED`
and `SONAME`.

## Metamod 1.12 patch series (MM_112)

`builder/patches/series/MM_112/` (`"root": "metamod"`) is keyed by the Metamod pin
rather than a line: every line that builds `MM_112_COMMIT` (`cb477558`, 1.12.0
git1228) uses it. `checkout-deps.sh` fetches the pin with `fetch-sourcemod.sh`
(exact tree, LF as committed), applies the series whose `commit` matches, then
`apply-mmsource-oldbridge.sh modern` (the legacy-plugin bridge stays a script: it
is our own code, kept once in `builder/patches/mm-oldbridge/`). `build-metamod.sh`
no longer patches MM 1.12. A full build from the series matches the scripted
build's files, exports, `NEEDED` and `SONAME`.

| Patch | What | Why (failure without it) |
|-------|------|--------------------------|
| `metamod/0001-build-episode1-toolchain` | `AMBuildScript`: episode1 `tier1_i486.a` before `vstdlib`; pthread/rt/`gcc_s` `NEEDED`; link through the C++ driver; GCC 10 flags; hidden static libstdc++. | As SourceMod's `0001`: ConVars from `vstdlib`, missing `NEEDED` on glibc 2.17, `-Werror`, exported `std::` symbols. |
| `metamod/0002-episode1-mem-h` | `provider_ep2.cpp` includes `tier0/mem.h`. | `MemAllocScratch` undeclared on episode1. |
| `metamod/0003-css34-versioning` | Build number from lines.json (`generate_headers.py`), `CSS34 pack:` line in `meta version`. | A `--depth` clone gives a wrong build number; smoke checks the pack commit. |
| `hl2sdk-manifests/0001-episode1-defines`, `0002-compiler-flag-guard` | As in SourceMod, for Metamod's own manifests (`4304a88`). | As in SourceMod. |

## Refreshing a series

After a pin bump in `builder/lines.json`: `builder/scripts/patch-series.sh
refresh <line>` (or `refresh MM_112` after an MM pin bump) rebases the series
(`git apply --3way`) and rewrites `series.json`; it reads the pin from
`lines.json` itself, because `lines.py gen` and `check` fail until it has run.
Then run `python3 builder/lines.py gen`. `builder/scripts/upstream-bump.py`
(T4.4) does all of this for the weekly bump PRs.
`builder/scripts/patch-series.sh check <series>` applies the series to a fresh
checkout of the pin. Before a bump, `builder/scripts/check-patch-drift.sh
--sm-commit <rev> --line <line>` (or `--range old..new`, `--mm-commit`) dry-runs
the series on the candidate with `git apply --3way` and names the first patch
that no longer applies; `--check-pins` checks every series on its own pin and
the MM 1.10 bridge patcher on the bridge pin.

## sm13 PostgreSQL explicit_bzero (temporary)

The sm13 series (`sourcemod/0002-glibc217-database-imports`) adds a Linux C
source, `css34_explicit_bzero.c`, only to `dbi.pgsql.ext`; sm12 has no such patch. The vendored `libpq.a` imports `explicit_bzero`, which
is absent from glibc 2.17 and otherwise remains an unversioned undefined import.
The hidden definition uses `memset` followed by a compiler memory barrier so
password erasure survives dead-store elimination and cannot interpose on libc
or other extensions (`test-glibc-imports.py` compiles the shim from the series).
A patch that does not apply fails the build.

Remove this patch when libpq is built from source in manylinux2014; PostgreSQL
already provides `src/port/explicit_bzero.c` for platforms without the function.

## Unversioned import contract

`testing/unversioned-imports.txt` lists exact symbol names and providers. System
providers were inspected from the pinned manylinux2014 i686 image in
`builder/docker/build.sh` (glibc 2.17 / libgcc_s). Engine providers were inspected
from CS:S v34 build 4044 `bin/{engine_i486,engine_i686,tier0_i486,vstdlib_i486}.so`.
Only observed imports are listed, rather than admitting every engine export.
New imports require verification against those providers, never the host libc.
Optional GCC instrumentation hooks are permitted only for weak undefined imports;
strong references to those names still fail. Unknown weak imports also fail.
Both SourceMod and Metamod package checks inspect every shipped ELF, including
executables, using `nm -D --undefined-only`; inspection errors fail closed.

## sm13 MySQL dependencies

The strict import check also found `compress2`, `uncompress` and weak
`getentropy` in sm13's MariaDB extension. The builder compiles checksum-pinned
zlib 1.3.1 with PIC and runs its tests; the same sm13 series patch moves zlib
inside the extension's existing static-library link group. Compression therefore
has no unversioned imports or new runtime dependency.

OpenSSL 1.1.1w normally probes libc's `getentropy` through a weak symbol (glibc
2.25+), then uses its Linux `getrandom` syscall path and existing random-device
fallback. `patch-openssl-getentropy.py` omits only that libc probe on Linux.
The upstream syscall path, kernel-seeding checks and device fallback remain
intact. The build runs `openssl rand` to verify entropy acquisition and changes
the build stamp so cached, unpatched libcrypto archives cannot be reused.
The OpenSSL patcher fails on missing or inconsistent anchors. No new unsupported libc
symbol is allowlisted. Revisit the OpenSSL patch when replacing OpenSSL 1.1.1w.

## SM 1.12: entity-output map-end cleanup list type

- Introduced by css34 commit `bc2d291` (PR #126, T1.5 / #84).
- Implementation: `builder/patches/series/sm12-latest/sourcemod/0007-sdktools-onmapend-list.patch`
  (generated from the `PYOUT` block of the former `apply-sourcemod-v112.sh`).
- Upstream: SourceMod #2589, cherry-picked as `e68dada2979eb3093d81d2e3766f741e7d431e4a`
  (SM 1.12.0.7257).
- Change: use `SourceHook::List<omg_hooks *>` in
  `EntityOutputManager::OnMapEnd`, matching the list stored in `OutputHookList`.
- Evidence without patch: GCC 10 fails with `'list' is not a member of 'std'`.
  Adding `<list>` alone would leave the cleanup interpreting a SourceHook list
  as a different container type. SM 1.13 already uses `std::list` consistently
  and is not rewritten.
- Drift policy: fail on missing/changed map-end anchors, unknown storage types,
  or malformed already-patched code; validate the consistent SM 1.13 layout.
- Validation: checker fixtures plus runtime entity-output probe across map
  changes; manylinux GCC 10 build and PR CI remain required.
- Upstream report candidate for **#101 / T3.6**: the 1.12-dev cherry-pick uses
  the wrong container type. Report against that branch with the compiler error
  and storage-type mismatch, rather than proposing a change to 1.13.
