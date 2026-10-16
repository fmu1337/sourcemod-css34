# Linux modules must declare their pthread/rt dependencies on pre-2.34 glibc

Status: **draft for owner submission; not filed upstream**.
Evidence is existing downstream code/notes, not a fresh reproduction in this
change. Re-check the upstream tip and attach the requested logs before filing.

Target: alliedmodders/sourcemod (SourcePawn build changes may belong in alliedmodders/sourcepawn).

When sourcepawn is linked statically into logic, or linker `--as-needed`
removes libraries before their users are seen, Linux modules can lack the
pthread/rt `DT_NEEDED` entries required on older glibc. Depending on another
server module to load these libraries first hides the missing dependency.
On glibc 2.34+ these interfaces were merged into libc, so testing only a modern
host is insufficient. This report does not require separate pthread/rt DSOs on
systems where libc legitimately supplies the interfaces.

### Minimal reproduction

1. Build the pinned SM 1.13 (`6eb5f8fa381100ed7cac1ab62a4ece11795a5d92`) with
   the downstream Debian 11 i386 toolchain. Keep all other patches fixed.
2. Remove only the forced pthread/rt link additions in the linked script,
   including the placement after static SourcePawn archives; save verbose link
   commands. Compare against the build with those additions restored.
3. Inspect both outputs, on the same pre-2.34 runtime:

   ```sh
   readelf -d sourcemod.logic.so
   readelf -d sourcepawn.jit.x86.so
   objdump -T sourcemod.logic.so | grep -E 'pthread_|clock_|timer_'
   ```

   Inspect only modules actually produced by that build (static SourcePawn may
   omit the standalone JIT). Load each package on the v34 server and capture
   the first missing-symbol error, if any. Record which dependency provides it.

Expected: every required symbol has a deliberate runtime dependency; success
must not depend on unrelated modules being loaded first. Downstream notes include
`undefined symbol: pthread_mutex_trylock` on an older runtime; that historical
symptom is not a new test result for this exact pin.

### Proposed fix and regression checks

Place required pthread/rt dependencies after static archives; narrowly scope
`--no-as-needed` if needed, and restore the previous as-needed state afterwards.
Do not copy the entire downstream link recipe as an upstream fix. Inspect ELF
NEEDED entries and test clean module loading on pre-2.34 and current glibc.

Downstream implementation: [pinned patch script](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/apply-sourcemod-v112.sh).
