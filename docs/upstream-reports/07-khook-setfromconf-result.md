# `DHookSetFromConf` returns 0 on success

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
`DHookSetup_SetFromConf` falls through with `return 0` after it set the
address, so `if (!DHookSetFromConf(...))` treats every success as a failure.
The old extension returned 1 on success and 0 (no error) when the key is
missing.

Fix: same patch, `src/natives/dhooksetup.cpp`.

## Minimal reproduction

Use a gameconf containing a valid function signature (the repository css34_dhooks_probe gameconf is a concrete fixture). Create a detour setup, call `DHookSetFromConf` for that key and print the return value. Repeat with a missing key.

## Expected result and regression check

A resolved key returns true; a missing key follows the documented failure path. The affected success path returns zero.

## Evidence to attach

Record exact dependency revisions, architecture, compiler, minimal plugin/harness,
and before/after diagnostics. The reproduction above is a procedure, not a new
passing test result.

Source: [existing report 2](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/docs/UPSTREAM_REPORTS.md).
Patch files named above are preserved in the [pinned builder](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/)
and on the `archive/khook` branch. The runtime fixture is
[css34_dhooks_probe.sp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/plugins/css34_dhooks_probe.sp);
[botplay-record.exp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/scripts/botplay-record.exp) contains the unload/reload sequence.
