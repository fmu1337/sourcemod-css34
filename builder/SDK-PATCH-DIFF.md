# SDK patch diff: reconstructed vs inferred original

We do not have `rom4s/sourcemod-css34-builder/patches/`. This document compares:

1. **Our `apply-hl2sdk-ep1c.sh`** against pristine `rom4s/hl2sdk-ep1c@fd7c497`
2. **Our `apply-sourcemod.sh`** SDK/link-related hunks
3. **Binary-level inference** from original `v1.11.0.6572` vs trusty repro (see `BINARY-DIFF.md`)

Regenerate the hl2sdk diff:

```bash
builder/sdk-patch-diff.sh /tmp/sdk-patch-diff
# → /tmp/sdk-patch-diff/hl2sdk-ep1c.patch
```

---

## Executive summary

| Layer | Match quality | Notes |
|---|---|---|
| Simple extensions (bintools, dbi.*, …) | **Good** | Identical `.text`/`.data`; only BSS padding + build timestamp |
| hl2sdk-ep1c header patches | **Unknown** (24 files + 177 symlinks) | Required to compile; original likely had similar but not identical set |
| SourceMod `SE_CSS` guards | **Plausible** | Disables Orange Box paths for CSS v34 |
| **Link model (C++ EH)** | **Mismatch** | Original imports `__cxa_*` / `_Unwind_Resume`; repro embeds EH (`T __cxa_throw`) → +text |
| **ep1 SDK include paths** | **Suspect** | `public/game/server`, `toolframework`, … may pull extra code into sdkhooks/sdktools/cstrike |

The **+50–65 KB `.text`** gap on `sourcemod.1.ep1`, `sdkhooks`, `sdktools`, `game.cstrike` is **not** from missing Valve imports (both builds import `Error`, `DevMsg`, `GetCVarIF`, … from `tier0_i486.so`). It comes from **different compiled code + link model**.

---

## Part 1: `apply-hl2sdk-ep1c.sh` (24 modified + 4 added + 177 symlinks)

### Added files

| File | Source | Purpose |
|---|---|---|
| `common/steamcommon.h` | curl from `alliedmodders/hl2sdk` **css** branch | Steam types not in rom4s ep1c |
| `common/userid.h` | curl from alliedmodders **css** | USERID_t etc. |
| `linux_sdk/tier0_i486.so` | compiled stub `void tier0_i486_stub(void){}` | link-time placeholder |
| `linux_sdk/vstdlib_i486.so` | same | link-time placeholder |

Pristine `rom4s/hl2sdk-ep1c` already ships `linux_sdk/tier1_i486.a`, `mathlib_i486.a` — **not** the `.so` stubs.

### Modified headers (content)

| File | Change | Risk |
|---|---|---|
| `public/tier0/platform.h` | `#include <new>` on Linux; `VALVE_LITTLE_ENDIAN`; MSVC-only warnings; **`GetCPUInformation()` returns `const CPUInformation*`** instead of `const CPUInformation&` | **API change** — affects `fasttimer.h` |
| `public/tier0/fasttimer.h` | `*GetCPUInformation()` deref | paired with above |
| `public/tier0/wchartypes.h` | wchar guard for glibc | compile fix |
| `public/tier0/basetypes.h`, `public/minmax.h` | wrap `min`/`max` macros for C++ | compile fix |
| `public/mathlib/math_base.h` | C++ `min`/`max` templates; remove `swap()` template; `FORCEINLINE_MATH` → `inline` on `Lerp<QAngle>` | **removes Valve swap template** |
| `public/tier1/utlmemory.h`, `utlvector.h` | `this->` in templates; `std::swap` | compile fix |
| `public/tier0/threadtools.h` | `this->` in `CTSQueue`/`CTSList` templates | compile fix |
| `public/tier0/memalloc.h` | fix `#endif` comment typo | compile fix |
| `public/networkvar.h` | MSVC-only pragma; `this->NetworkStateChanged()` | compile fix |
| `public/datamap.h` | **`#if 0` — disable Valve `offsetof` macro** | use system `offsetof` |
| `public/dt_common.h` | add `SPROP_VARINT 0` | DT compat |
| `public/icvar.h`, `edict.h`, `keyvalues.h`, … | lowercase include paths | case sensitivity |
| `public/soundemittersystem/isoundemittersystembase.h` | `interval.h`; fix `operator==` | compile fix |
| `public/bitmap/imageformat.h`, `toolframework/itoolentity.h`, `engine/iserverplugin.h` | MSVC guards / includes | compile fix |

### Symlinks (177)

`create_include_symlinks()` walks the tree and links `public/Foo.h` → `public/foo.h` when only lowercase exists. Pristine rom4s ep1c on Linux may compile **without** all of these (includes already lowercase). Original builder may have used a **smaller** symlink set or Windows-centric paths.

**Experiment:** set `SKIP_INCLUDE_SYMLINKS=1` (if added) or disable the Python block and measure `.text` delta on sdkhooks.

### Stubs vs game runtime

Link stubs export only `tier0_i486_stub` / `vstdlib_i486_stub`. Valve APIs (`Error`, `DevMsg`, …) remain **undefined** and resolve at load time from the **game's** `tier0_i486.so` — same on original and repro.

---

## Part 2: `apply-sourcemod.sh` (SDK-relevant)

### AMBuildScript

| Hunk | Effect |
|---|---|
| Add `ep1` SDK entry (`SE_CSS`, `1.ep1`) | Builds `*.1.ep1.so` against `hl2sdk-ep1c` |
| `sdk.name == 'ep1'` include paths | Adds `public/game/server`, `toolframework`, `game/shared`, `common` — **broader than episode1** |
| `dynamic_libs` for `css` → `tier0_i486.so` | Correct for CS:S v34 |
| `lib_folder` for `ep1`/`episode1` → `linux_sdk` | Uses stub `.so` + static `tier1_i486.a` |
| Clang `-Wno-*` / `-fpermissive` | compile fixes |

**Not patched (vs inferred original):**

```python
# AMBuildScript configure_linux — always applied for Linux:
cxx.linkflags += ['-static-libstdc++']
# clang only:
cxx.linkflags += ['-lgcc_eh']
```

Binary evidence suggests the **original release did not embed** libstdc++ EH the same way:

```
original sourcemod.1.ep1.so:  U __cxa_throw   U _Unwind_Resume
repro sourcemod.1.ep1.so:     T __cxa_throw   t _Unwind_Resume  (+ U duplicates in symtab)
```

### SourceMod source `SE_CSS` guards (bulk sed)

Forces pre-Orange Box paths when `SOURCE_ENGINE == SE_CSS`:

- `SOURCE_ENGINE >= SE_ORANGEBOX` → `&& != SE_CSS`
- `SOURCE_ENGINE >= SE_EYE` → `&& != SE_CSS`
- `PlayerManager`, `HalfLife2`, `GameHooks`, `sdkhooks/takedamageinfohack`, `sdktools/vsound`, `cstrike/natives`, …

These are **required** for v34 semantics (2-arg `ChangeLevel`, auth string Steam IDs, 14-param `EmitSound`, etc.).

### Notable per-file patches

| File | Change |
|---|---|
| `HalfLife2.cpp` | `CommandLine_Tier0` via `CreateInterface` — **repro imports `CommandLine_Tier0` UND; original does not** |
| `PlayerManager.cpp` | `GetAuthString()` path for CSS; `CSteamID()` instead of `k_steamIDNil` |
| `cstrike/natives.cpp` | `FindDataMapInfo` instead of manual `typedescription_t` offset |
| `core/smn_entities.cpp` | drop `FL_EP2V_UNKNOWN` for CSS; block `string_t` setters |

---

## Part 3: Dynamic symbol diff (inferred original behavior)

### `sourcemod.1.ep1.so` — UND symbols only in **original**

```
__cxa_allocate_exception, __cxa_throw, __cxa_begin_catch, __cxa_end_catch,
__gxx_personality_v0, _Unwind_Resume, _Znwj, _ZdlPv, _ZNSt9exceptionD2Ev, …
snprintf@GLIBC_2.0
```

### `sourcemod.1.ep1.so` — UND symbols only in **repro**

```
CommandLine_Tier0, dl_iterate_phdr, __sprintf_chk, pthread_mutex_*,
pthread_once, printf, realloc, write, ___tls_get_addr
```

### Valve tier0 — **same on both**

Both import: `Error`, `DevMsg`, `Warning`, `GetCPUInformation`, `GetCVarIF`,
`AssertValidStringPtr`, `KeyValuesSystem`, `MemAllocScratch`, …

**Conclusion:** the SDK patch gap is **not** “missing tier0 linkage”. It is **extra compiled code** and **different C++ runtime embedding**.

### sdkhooks / sdktools pattern

Same EH split as core. Original keeps C++ exception symbols external; repro inlines EH.

Ep1 vs episode1 flip in final `.so` size:

| Module | Original | Repro | Notes |
|---|---:|---:|---|
| sdkhooks.1.ep1 | 383 KB | 523 KB | uses **hl2sdk-ep1c** + full patch set |
| sdkhooks.2.ep1 | 393 KB | 345 KB | uses **hl2sdk-episode1** + minimal patch |

→ suspicion on **`apply-hl2sdk-ep1c.sh`**, not episode1 SDK.

---

## Part 4: Recommended experiments (priority)

### 1. Dynamic libstdc++ for `ep1` / `css` / `episode1` — **implemented 2026-07-06**

`apply-sourcemod.sh` now drops `-static-libstdc++` and `-lgcc_eh` for
`ep1`, `css`, `episode1` on Linux. Dynamic repro imports `libstdc++.so.6`.

Trusty repro vs original (`v1.11.0.6572`):

| Module | Original | Before (static) | After (dynamic) |
|---|---:|---:|---:|
| sourcemod.1.ep1.so | 951419 | 1071248 | **858006** |
| sdkhooks.ext.1.ep1.so | 383107 | 522630 | **309047** |
| sdktools.ext.1.ep1.so | 608339 | 737485 | **523975** |
| game.cstrike.ext.1.ep1.so | 290455 | 395182 | **206688** |

SDK-heavy modules are now **smaller than original** (still 0/20 byte-identical).

### 2. Revert `GetCPUInformation` pointer patch — **failed (2026-07-06)**

clang-9 with `-Werror` rejects C-linkage `GetCPUInformation()` returning
`const CPUInformation&`. Pointer return is **required to compile**.

### 3. Narrow ep1 include paths — **partial (2026-07-06)**

| Variant | Result |
|---|---|
| episode1-only (`dlls`, `game_shared`) | **Build fails** — missing `iplayerinfo.h` |
| drop `game/shared` + `common` | **OK**, sizes **unchanged** |

Current ep1 paths: `game/server`, `toolframework`, `dlls`, `game_shared`.

### 4. Disable bulk include symlinks — **failed (2026-07-06)**

`REPRO_SKIP_INCLUDE_SYMLINKS=1` → fails on `appframework/IAppSystem.h`.

### 5. Pin gcc **9.3.0-11ubuntu0~14.04** — **in progress (2026-07-12)**

Superseded PPA binaries are gone; `builder/docker/trusty/install-gcc-9.3.0.sh`
rebuilds from `archive.ubuntu.com` orig/debian + Launchpad diff.

**CI failure (Jul 6):** Docker image build ran 1h17m and failed in `build-nvptx`
configure. Fix: disable `with_offload_nvptx` / `with_offload_hsa`, skip extra
languages, install only multilib toolchain `.deb` files.

**Status:** script updated; awaiting `Build (repro trusty)` rerun.

### 7. Linker flags (`-fdata-sections`, `-Wl,--gc-sections`, …) — **wired (2026-07-12)**

`EXP7_ENABLED=1` + `EXP7_VARIANT={sections,gc,symbolic,full}` now routes through
`linux-repro.sh` → `apply-sourcemod-exp7.sh` (Docker env vars forwarded).

```bash
EXP7_VARIANT=sections builder/run/exp7-linker-flags.sh
```

**Status:** ready to run; results not measured yet.

### 6. `STRIP_MODE=unneeded` — **no effect (2026-07-06)**

Same sizes as `STRIP_MODE=debug` with dynamic libstdc++.

---

## Part 5: What we cannot diff without the builder

| Missing | Impact |
|---|---|
| `build.py` / `config.json` | May apply patches differently, different link flags, strip mode |
| `patches/*.patch` or encoded blobs | Exact hl2sdk / sourcemod diffs |
| Original `.o` files | Per-TU compile comparison |

---

## Files

| Path | Role |
|---|---|
| `builder/patches/apply-hl2sdk-ep1c.sh` | rom4s hl2sdk-ep1c patches |
| `builder/patches/apply-sourcemod.sh` | SourceMod + AMBuild patches |
| `builder/sdk-patch-diff.sh` | Regenerate pristine→patched unified diff |
| `builder/binary-diff.py` | ELF/module comparison tool |
| `builder/BINARY-DIFF.md` | Binary-level findings |
