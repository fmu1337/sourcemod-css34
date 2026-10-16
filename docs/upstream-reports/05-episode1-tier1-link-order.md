# episode1 link ordering can bind ConVar to vstdlib instead of the SDK archive

Status: **draft for owner submission; not filed upstream**.
Evidence is existing downstream code/notes, not a fresh reproduction in this
change. Re-check the upstream tip and attach the requested logs before filing.

Target: alliedmodders/metamod-source (analogous SourceMod HL2Library path).

`SdkHelpers.configureCxx` puts shared vstdlib/tier0 before static
`tier1_i486.a` for the episode1 Linux target. The resulting module may import
ConVar implementation from vstdlib rather than include the SDK archive's
implementation. Downstream notes associate this with a GameDLLInit hang and
broken cvar lookup. This is an episode1 compatibility report, not a request to
change link order for every SDK unconditionally.

### Minimal reproduction

1. Use Metamod 1.12 git1226 and the episode1 SDK with the downstream Linux
   build setup. Disable only the `PYTIER1` reordering block in the linked script.
2. Capture the verbose link line for `metamod.2.ep1.so`, then inspect:

   ```sh
   nm -D metamod.2.ep1.so | c++filt | grep -E 'ConVar|s_pConCommandBases'
   readelf -d metamod.2.ep1.so
   ```

3. Boot a v34 server with that module and capture a stack if GameDLLInit stalls.
4. Repeat with the archive before vstdlib/tier0, keeping all other compiler and
   linker options identical. Compare defined vs undefined symbols, not just
   whether a name occurs in the symbol table.

Expected: the intended episode1 ConVar implementation and registration list
are used consistently. Downstream's patched build embeds the SDK implementation.

### Proposed fix and regression checks

Change the episode1-specific library ordering in the build configuration.
Do not assume the unrelated pthread/rt additions in the downstream block are
needed for this particular fix. Verify symbols and startup/cvar lookup, then
build a newer Source1 SDK to check for unintended symbol interposition changes.

Downstream implementation: [pinned patch script](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/apply-mmsource-v112.sh).
