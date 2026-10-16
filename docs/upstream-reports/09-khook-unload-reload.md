# Unloading `dhooks.ext` on a running server crashes it, and a reload is broken

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
`SDK_OnUnload` leaves three things behind:

- the per-class destructor hooks (`KHook::SetupVirtualHook` in
  `handle.cpp`, `HookCleanUp::CBaseEntity`) are never removed;
- the detour / virtual hook capsules (`locals::address_detours`,
  `locals::virtual_detours`) are never destroyed, so their KHook hooks keep
  calling `Capsule::PrePostHookLoop` after SourceMod freed the extension's
  objects: `sm exts unload dhooks` with a live detour segfaults within
  frames;
- the handle types (`DHookParamReturn`, `DHookSetup`, `DynamicHook`,
  `DynamicDetour`) and the `Functions` gameconf listener are never removed,
  so the next `sm exts load dhooks` (or the autoload of a plugin that uses
  DHooks) fails `CreateType` and every `DHookCreate` returns an invalid
  handle.

Fix: `handle::shutdown()` removes the destructor hooks and the handle types,
`Capsule::RemoveAll()` destroys the capsules, and `SDK_OnUnload` removes the
`Functions` listener. Covered by the botplay unload test
(`DHOOKS_UNLOAD_TEST=1`).

## Minimal reproduction

Load css34_dhooks_probe, add bots and enable its detours. Run `sm plugins unload css34_dhooks_probe`, then `sm exts unload dhooks`, continue server frames, and run `sm exts load dhooks`. Reload the probe and create new handles. Repeat with DHOOKS_UNLOAD_TEST=1 in the downstream botplay runner.

## Expected result and regression check

No callback enters unloaded extension code, and handle creation succeeds after reload. Capture the first failing unload/reload stage and stack.

## Evidence to attach

Record exact dependency revisions, architecture, compiler, minimal plugin/harness,
and before/after diagnostics. The reproduction above is a procedure, not a new
passing test result.

Source: [existing report 4](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/docs/UPSTREAM_REPORTS.md).
Patch files named above are preserved in the [pinned builder](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/)
and on the `archive/khook` branch. The runtime fixture is
[css34_dhooks_probe.sp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/plugins/css34_dhooks_probe.sp);
[botplay-record.exp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/scripts/botplay-record.exp) contains the unload/reload sequence.
