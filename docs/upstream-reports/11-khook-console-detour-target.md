# ConsoleDetours detours the KHook stub instead of `ConCommand::Dispatch`

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
`GenericCommandHooker::MakeHookable` reads `ConCommand::Dispatch` from each
command's vtable. When a KHook virtual hook already owns that slot, the slot
holds the KHook JIT stub, and the inline detour is written into the stub.
On shutdown Metamod frees the stub first, then restoring the detour writes
into freed memory (crash in `safetyhook::InlineHook::destroy`).

Fix: resolve the real function with
`KHook::FindOriginalVirtual(vtable, KHook::GetVtableIndex(&ConCommand::Dispatch))`
(`sourcemod-khook-consoledetours.patch`).

## Minimal reproduction

On the pinned KHook server install a virtual hook for ConCommand::Dispatch, then make the same command hookable through ConsoleDetours. Record the vtable entry, the original function address and inline-detour target. Quit the server under a debugger.

## Expected result and regression check

The inline detour targets the original function, and teardown does not write to a freed JIT stub. Compare with KHook::FindOriginalVirtual.

## Evidence to attach

Record exact dependency revisions, architecture, compiler, minimal plugin/harness,
and before/after diagnostics. The reproduction above is a procedure, not a new
passing test result.

Source: [existing report 6](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/docs/UPSTREAM_REPORTS.md).
Patch files named above are preserved in the [pinned builder](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/)
and on the `archive/khook` branch. The runtime fixture is
[css34_dhooks_probe.sp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/plugins/css34_dhooks_probe.sp);
[botplay-record.exp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/scripts/botplay-record.exp) contains the unload/reload sequence.
