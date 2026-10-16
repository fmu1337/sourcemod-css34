# GameConfigs must inspect the loaded engine without loading a second variant

Status: **draft for owner submission; not filed upstream**.
Evidence is existing downstream code/notes, not a fresh reproduction in this
change. Re-check the upstream tip and attach the requested logs before filing.

Target: alliedmodders/sourcemod.

On CS:S v34 Linux, `CacheGameBinaryInfo` can open `engine_i486.so` with
`RTLD_NOW` while `engine_i686.so` is already mapped. Loading the sibling runs
its static constructors. Its ConVars join shared registration lists; closing
that temporary module leaves dangling entries. The downstream investigation
recorded a crash in `ConCommandBase::FindCommand` / `CCvar::FindVar("sv_logecho")`
after `Network:` and before the first map loaded.

### Minimal reproduction

1. Use a CS:S v34 Linux server containing both engine variants and launch
   `srcds_i686` with Metamod 1.12 and SourceMod 1.12/1.13 configured for episode1.
2. Keep the downstream compatibility patches except the `CacheGameBinaryInfo`
   and symbol-lookup `RTLD_NOLOAD` changes in the linked patch script.
3. Boot `de_dust2` under gdb. Break on `dlopen`; record the engine filename and
   `/proc/<pid>/maps`. Continue through gamedata loading and `FindVar`.
4. Repeat with only the `RTLD_NOLOAD` changes restored.

Expected: gamedata lookup reuses an already mapped engine. It must not run
constructors from another engine variant merely to inspect signatures.
Observed downstream: the first build loads the sibling and can crash while
traversing cvars; the patched path avoids that load.

### Proposed fix and regression checks

Use `RTLD_NOW | RTLD_NOLOAD`, with an already-loaded `_i686`/`_i486` sibling
fallback, and fail normally if neither is mapped. Apply the same policy to
`@` symbol lookup. Retain balanced `dlclose` calls for acquired handles.
Test both engine filenames, a missing module and ordinary signature lookup;
verify maps never gain a second engine as a side effect.

Evidence: downstream patch plus the recorded bisect in
[V34 comparison](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/docs/V34_COMPARISON_v1.11.6572_vs_v1.12.7239.md).

Downstream implementation: [pinned patch script](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/apply-sourcemod-v112.sh).
