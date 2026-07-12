# Byte-Match Experiments: Progress & Next Steps

## Current Status (post-Exp #6)

**Trusty Docker repro + dynamic libstdc++ + pinned deps:**
- ✅ **9/20 .so files same size** as original v1.11.0.6572
- ❌ **0/20 byte-identical** (reconstructed patches differ from lost original)
- 📊 **4 SDK modules** have +50–65 KB `.text` gap (sourcemod.1.ep1, sdkhooks, sdktools, game.cstrike)

---

## Experiment #7: Linker Flags & Visibility (IN PROGRESS)

**Hypothesis:** The original build may have used additional linker optimizations (`-fvisibility=hidden`, `-fdata-sections`, `-ffunction-sections`, `-Wl,--gc-sections`) that reduce `.text`.

**Theory:** GCC 9.3.0 on trusty with these flags could:
1. Eliminate unused inline/template instantiations
2. Reduce symbol table bloat
3. Shrink .text by 5–10% on SDK modules

### Variants to test (sequential)

| # | Flags | Expected Δ | Status | Notes |
|---|---|---|---|---|
| 7a | `-fvisibility=hidden` for ep1 only | −1–2 KB | BASELINE | Already in place; verify applied |
| 7b | Add `-fdata-sections -ffunction-sections` | −5–10 KB | READY | Requires linker GC flag |
| 7c | Add `-Wl,--gc-sections` at link | −3–8 KB | READY | Only on Linux, with sections flags |
| 7d | Combine 7b + 7c | −10–20 KB | READY | Full aggressive optimization |
| 7e | Add `-Wl,-Bsymbolic` (bind locally) | −2–5 KB | READY | Reduce GOT/PLT bloat |

### Implementation

**Scripts created:**
- `builder/patches/apply-sourcemod-exp7.sh` — variants: `baseline`, `sections`, `gc`, `symbolic`, `full`
- `builder/run/exp7-linker-flags.sh` — wrapper to run variants via Docker trusty

**Usage:**
```bash
# Baseline (no experimental flags)
builder/run/exp7-linker-flags.sh

# Test -fdata-sections -ffunction-sections
EXP7_VARIANT=sections builder/run/exp7-linker-flags.sh

# Test with garbage collection
EXP7_VARIANT=gc builder/run/exp7-linker-flags.sh

# Test symbolic binding
EXP7_VARIANT=symbolic builder/run/exp7-linker-flags.sh

# Full aggressive optimization
EXP7_VARIANT=full builder/run/exp7-linker-flags.sh
```

**Expected results:**
- sourcemod.1.ep1.so: 858 KB → ~820–840 KB (−2–4%)
- sdkhooks.ext.1.ep1.so: 309 KB → ~295–305 KB
- sdktools.ext.1.ep1.so: 524 KB → ~500–515 KB
- game.cstrike.ext.1.ep1.so: 207 KB → ~195–205 KB

---

## Experiment #8: Include Symlinks (PLANNED)

**Status:** Previously failed — `REPRO_SKIP_INCLUDE_SYMLINKS=1` failed on `appframework/IAppSystem.h`.

**Revision:** Make symlink creation **conditional per-SDK** instead of all-or-nothing:
- ep1 (hl2sdk-ep1c): **SKIP** symlinks, patch paths explicitly
- episode1: keep symlinks (fewer modifications needed)
- css/csgo: vary and compare

**Expected delta:** If symlinks pull extra code paths, −3–8 KB on ep1 modules.

**Implementation:** Modify `apply-hl2sdk-ep1c.sh` with per-SDK symlink control.

---

## Experiment #9: GCC 9.3.0-11ubuntu0~14.04 Native (PLANNED)

**Status:** "not run yet" — current builds use clang-9 with gcc wrappers.

**Action:** Fully switch to native gcc-9.3.0-11ubuntu0~14.04 on trusty:
- Rebuild from `gcc-9 package` on Launchpad (lost archives)
- Avoid clang-9 entirely; use gcc-9 -m32 -multilib
- Compare .text/symbol output

**Expected:** May reveal gcc-specific code generation differences from original.

**Implementation:** Modify `install-clang9.sh` to optionally use gcc-9 instead.

---

## Experiment #10: Optimization Flags Study (PLANNED)

**Current:** All repro builds use `-O2` (standard SourceMod default).

**Test matrix:**
| Flag | Motivation | Expected Δ |
|---|---|---|
| `-O2` (baseline) | Current | 0 B |
| `-Os` | Smaller code size | −5–15 KB |
| `-O3` | Aggressive; may expand code | +10–30 KB |
| `-flto=thin` | Thin LTO; cross-module optimizations | −10–50 KB |
| `-march=pentium4` | Tune for P4 (2004-era original builder) | ±5 KB |

**Risk:** LTO may differ between gcc-9.3 and clang-9; could break reproducibility differently.

**Implementation:** Add `EXP10_OPT_FLAG` env var to override `-O2`.

---

## Experiment #11: GCC Build Flags Profile (PLANNED)

**Extract original flags** from binary metadata:
- Use `readelf -p` to extract build flags from `.comment` section
- Compare against `gcc --version` string in .so binaries
- May reveal `-march`, `-mtune`, `-flto` settings

**Expected:** Identify original compiler version and configuration.

**Tool:** Create `builder/analyze-binary-metadata.sh`.

---

## Comparison Framework

All experiments use a standard comparison:

```bash
# Run in Docker trusty
builder/docker/trusty/run.sh  # baseline (Exp #6)

# Experimental run
EXP7_VARIANT=sections builder/docker/trusty/run.sh

# Diff the artifacts
builder/compare-release.sh <artifact>
```

**Output format** (from `compare-release.sh`):
```
sourcemod.1.ep1.so: 858006 bytes (repro) vs 951419 bytes (original) [−93413 B, −9.8%]
sdkhooks.ext.1.ep1.so: 309047 bytes (repro) vs 383107 bytes (original) [−74060 B, −19.3%]
```

---

## Symbol Inspection Tools

For detailed .text comparison:

```bash
# Extract symbol sizes
objdump -t sdkhooks.so | grep -E '\.text' | awk '{sum += $5} END {print sum " bytes .text symbols"}'

# Compare against original
nm -S original/sdkhooks.so | grep -E ' T ' | awk '{sum += $2} END {print sum " bytes .text symbols"}'

# ELF section summary
readelf -S sdkhooks.so | grep '\.text\|\.data\|\.bss'
readelf -S original/sdkhooks.so | grep '\.text\|\.data\|\.bss'
```

---

## Known Blockers

| Issue | Exp | Workaround |
|---|---|---|
| Pristine patches lost | All | Reconstruct from binaries |
| Original builder config unknown | 7–11 | Try standard gcc/clang configs |
| gcc 9.3.0 PPA superseded | 9 | Rebuild from source + Launchpad diff |
| Clang-9 may differ from gcc-9 | 7–9 | Test both; collect metrics |

---

## Success Criteria

- **Exp #7:** Reduce `.text` by 5–10% on SDK modules (−35–50 KB total across 4 modules) → **Byte-match 2–3 more .so files**
- **Exp #8:** Eliminate symlink overhead without breaking builds → **−3–8 KB**
- **Exp #9:** Match gcc-9 output better than clang-9 → **Reveal original toolchain**
- **Exp #10:** Find optimization flag that keeps code similar size → **Reproducible builds**
- **Exp #11:** Identify original compiler version string → **Validate hypothesis**

**Ultimate goal:** Byte-match at least **3–5 of the 20 .so files** by combining targeted experiments.

---

## Running Experiments Sequentially

```bash
# Baseline (Exp #6) — run first for comparison
builder/docker/trusty/run.sh
tar -tzf packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz > /tmp/baseline-files.txt

# Exp #7a: baseline variant (should be identical to Exp #6)
EXP7_VARIANT=baseline builder/run/exp7-linker-flags.sh

# Exp #7b: sections flags
EXP7_VARIANT=sections builder/run/exp7-linker-flags.sh
builder/compare-release.sh packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz

# Exp #7c: sections + gc
EXP7_VARIANT=gc builder/run/exp7-linker-flags.sh
builder/compare-release.sh packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz

# ... continue with other variants ...
```

---

## Notes

- Each experiment takes ~30–45 minutes in Docker trusty
- Size deltas are measured in **bytes** to catch 1–2 KB differences
- Symbol differences may vary by gcc/clang patch versions
- Document results in `builder/REPRO.md` after each successful experiment
