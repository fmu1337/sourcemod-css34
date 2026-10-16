# Build breaks against current KHook / MSVC

Status: **draft for owner submission; not filed upstream**.
Evidence is existing downstream code/notes, not a fresh reproduction in this
change. Re-check the upstream tip and attach the requested logs before filing.

Target: alliedmodders/sourcemod (k/sourcehook_alternative branch).

Environment: SourceMod KHook `0cd7f6fcb4e3f09e0adb136f42dfa12305682bcc`
merged with master `6eb5f8fa381100ed7cac1ab62a4ece11795a5d92`
(downstream result `25954d4aa4a55ab10c6e2c30699f52358f982fb9`);
Metamod `05c5c63a9d595cb84021c3a51fe38366ba4a12a5`;
KHook `2a89535` (abbreviated revision recorded in the source notes).

## Problem and downstream fix
- KHook `96f3c61` renamed `KHook::GetContext()` to `GetContextPtr()`; the
  branch still calls the old name.
- `extensions/sdktools/output.cpp`: the Windows x86 definition of
  `Hook_FireOutput` lacks the `EntityOutputManager::` qualifier (LNK2019).

Fix: `apply-sourcemod-khook.sh`.

## Minimal reproduction

Build the pinned SourceMod KHook branch against a KHook revision containing GetContextPtr but no GetContext. Separately build the SDKTools extension with MSVC x86 and inspect the Hook_FireOutput symbol.

## Expected result and regression check

The API name matches the dependency and the method definition is qualified as EntityOutputManager::Hook_FireOutput. Keep the two compiler/linker diagnostics distinct.

## Evidence to attach

Record exact dependency revisions, architecture, compiler, minimal plugin/harness,
and before/after diagnostics. The reproduction above is a procedure, not a new
passing test result.

Source: [existing report 7](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/docs/UPSTREAM_REPORTS.md).
Patch files named above are preserved in the [pinned builder](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/)
and on the `archive/khook` branch. The runtime fixture is
[css34_dhooks_probe.sp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/plugins/css34_dhooks_probe.sp);
[botplay-record.exp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/scripts/botplay-record.exp) contains the unload/reload sequence.
