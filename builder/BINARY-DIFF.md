# Binary diff: original v1.11.0.6572 vs trusty repro

Comparison between:

- **Original:** `sourcemod-1.11.0-git6572-css34-linux.tar.gz` from
  [rom4s release v1.11.0.6572](https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572)
- **Repro:** trusty Docker build in `sourcemod/build/package/` (Jul 6 2026), clang-9 +
  pinned deps from `builder/pins.env`

Run the analysis:

```bash
# extract both trees, then:
python3 builder/binary-diff.py /path/to/orig /path/to/repro
```

> **Note:** `packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz` in this repo was
> overwritten by a repro artifact at one point. Always compare against the GitHub
> release tarball for the original side.

## Summary

| Category | Count | Modules |
|---|---:|---|
| **Code-equivalent** (same section layout; diffs = metadata/BSS padding) | 8 | bintools, dbi.mysql, dbi.sqlite, geoip, regex, topmenus, updater + near-match dbi.mysql |
| **Same-size code shift** (identical `.text` size, re-linked layout) | 3 | sourcemod.logic, sourcepawn.jit, clientprefs |
| **Same-size content drift** | 1 | webternet (+5.5 KB in `.text`/`.rodata`, same section sizes) |
| **SDK / game patch gap** (+50–65 KB `.text`) | 4 | sourcemod.1.ep1, sdkhooks.1, sdktools.1, game.cstrike.1 |
| **Secondary SDK variants** | 3 | sourcemod.2.ep1, sdkhooks.2, sdktools.2 |
| **Loader stub** | 1 | sourcemod_mm_i486 (−178 B) |

**0 / 20** byte-identical. **9 / 20** same file size.

## Per-module table

| Module | Orig B | Repro B | Δ size | Diff bytes | % | Verdict |
|---|---:|---:|---:|---:|---:|---|
| sourcemod.1.ep1.so | 951419 | 1071248 | +119829 | 965374 | 90% | **SDK/core patch gap** (+53 KB `.text`) |
| sourcemod.2.ep1.so | 950762 | 902763 | −47999 | 842879 | 89% | ep2 variant mismatch |
| sourcemod.logic.so | 1009356 | 1009356 | 0 | 618884 | 61% | same `.text` size, re-linked JIT layout |
| sourcepawn.jit.x86.so | 548536 | 548426 | −110 | 383403 | 70% | same `.text` size, address rebasing |
| sourcemod_mm_i486.so | 12269 | 12091 | −178 | 5562 | 45% | smaller loader stub |
| clientprefs.ext.so | 271225 | 271203 | −22 | 189768 | 70% | same sections, minor relink |
| sdkhooks.ext.1.ep1.so | 383107 | 522630 | +139523 | 496573 | 95% | **+64 KB `.text`** |
| sdkhooks.ext.2.ep1.so | 393444 | 344761 | −48683 | 356126 | 91% | ep2 variant |
| sdktools.ext.1.ep1.so | 608339 | 737485 | +129146 | 658380 | 89% | **+66 KB `.text`** |
| sdktools.ext.2.ep1.so | 601902 | 557525 | −44377 | 531976 | 88% | ep2 variant |
| game.cstrike.ext.1.ep1.so | 290455 | 395182 | +104727 | 364904 | 92% | **+56 KB `.text`** |
| game.cstrike.ext.2.ep1.so | 290669 | 291120 | +451 | 179256 | 62% | ep2 relink |
| dbi.mysql.ext.so | 4203552 | 4203552 | 0 | 6388 | 0.15% | **identical code sections** |
| dbi.sqlite.ext.so | 1494420 | 1494420 | 0 | 375 | 0.03% | metadata/BSS only |
| bintools / regex / topmenus / updater | — | — | 0 | ~375 | <0.25% | metadata/BSS only |
| geoip.ext.so | 37519 | 37519 | 0 | 293 | 0.78% | `.shstrtab` + metadata |
| webternet.ext.so | 341286 | 341286 | 0 | 5588 | 1.6% | same section sizes, small code/rodata drift |

## Findings

### 1. Eight modules are effectively rebuilt matches

For **bintools, dbi.mysql, dbi.sqlite, geoip, regex, topmenus, updater**:

- `.text`, `.data`, `.rodata` — **same size and load addresses**
- All differing bytes are in **`.bss` padding** (88–89%) and **`.comment`**
- Strings diff is only build metadata:

| String | Original | Repro |
|---|---|---|
| Build date | `Jun 22 2020 08:10:33` | `Jul  6 2026 11:19:55` |
| GCC label | `9.3.0-11ubuntu0~14.04` | `9.4.0-1ubuntu1~14.04` |
| Git rev string | `832519ab` | `832519a` |

**Conclusion:** SourceMod core patches for these extensions match. Remaining diff is
reproducible **if** we pin gcc-9.3.0-11ubuntu0~14.04 and match link-time BSS layout.

### 2. Four game-facing modules have large patch gaps

**sourcemod.1.ep1.so**, **sdkhooks**, **sdktools**, **game.cstrike** (ep1 variants)
each gained **+53 to +66 KB** of `.text` and **+5–10 KB** `.rodata` in repro.

Symbol analysis on `sourcemod.1.ep1.so`:

| Original UND (engine) | Present in repro? |
|---|---|
| `AssertValidStringPtr`, `Error`, `GetCVarIF`, `CVProfNode::*`, `DevMsg`, `Warning`, … | **Missing** — fewer Valve imports |
| `___tls_get_addr`, `__sprintf_chk`, `pthread_*`, `dl_iterate_phdr` | **Added** in repro |

Same pattern on **sdkhooks** and **game.cstrike**: original links against C++ EH
(`_Unwind_Resume`, `__cxa_throw`) and Valve tier0 APIs; repro pulls more from
`libgcc_s` / libc fortified symbols.

**Conclusion:** `builder/patches/apply-hl2sdk-ep1c.sh` and/or
`apply-sourcemod.sh` diverge from the original `sourcemod-css34-builder/patches/`
for SDK-facing code. The reconstructed `linux_sdk` tier0/vstdlib stubs and mathlib
edits are the prime suspects.

### 3. sourcemod.logic.so — same size, different code placement

- `.text` size differs by only **−32 bytes**
- Yet **61%** of file offsets differ (classic re-link / code reorder)
- Strings show minor JIT fragment changes (`0Qh:` vs `0QhJ`, etc.)
- **Same** undefined symbol set (140 imports)

**Conclusion:** Logic/JIT code is largely equivalent but not byte-stable across
rebuilds. Likely needs identical compiler **and** identical link order to match.

### 4. Toolchain differences (minor but measurable)

Both sides use **clang 9.0.1** for C++ (visible in `.comment`), but:

- Original trusty gcc package: **9.3.0-11ubuntu0~14.04**
- Repro Docker gcc package: **9.4.0-1ubuntu1~14.04**

Original `.travis.yml` used the `ubuntu-toolchain-r/test` PPA on trusty — exact
package versions from June 2020 may differ from our 2026 Docker image layers.

### 5. Strip / debug

Repro uses `STRIP_MODE=debug` (default in `linux-repro.sh`). Original release
`sourcemod.1.ep1.so` is **smaller** (951 KB vs 1071 KB repro) despite repro having
*less* Valve-linked code — original was likely stripped more aggressively or built
with different debug sections. Section comparison shows repro has larger
`.eh_frame`, `.strtab`, `.symtab` on divergent modules.

## Recommended next steps (by impact)

1. **Diff `apply-hl2sdk-ep1c.sh` / `apply-sourcemod.sh` against inferred original
   patches** — focus on symbols only in original UND list (Valve tier0/vstdlib API
   usage, C++ EH linkage).

2. **Pin gcc-9.3.0-11ubuntu0~14.04** in trusty Dockerfile (download specific
   `.deb` from Ubuntu archive) to eliminate the 375-byte metadata diffs on simple
   extensions.

3. **Try `STRIP_MODE=unneeded`** (or match original strip flags from `build.py`) —
   may close `sourcemod.1.ep1.so` size gap.

4. **ep1 vs ep2 variants** — original release shipped both `*.1.ep1.so` and
   `*.2.ep1.so`; repro ep2 modules are *smaller*. Check configure/AMBuild SDK
   selection matches original `config.json` per-target flags.

5. **sourcemod.logic / sourcepawn.jit** — treat as link-order sensitive; lower
   priority unless full byte-match is required.

## Files

- `builder/binary-diff.py` — ELF section-aware byte diff tool
- `builder/compare-release.sh` — package-level SHA comparison
