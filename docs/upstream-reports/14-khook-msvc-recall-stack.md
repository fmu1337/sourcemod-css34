# A recall corrupts the recall site's stack and registers on MSVC x86

Status: **draft for owner submission; not filed upstream**.
Evidence is existing downstream code/notes, not a fresh reproduction in this
change. Re-check the upstream tip and attach the requested logs before filing.

Target: Kenzzer/khook.

Environment: SourceMod KHook `0cd7f6fcb4e3f09e0adb136f42dfa12305682bcc`
merged with master `6eb5f8fa381100ed7cac1ab62a4ece11795a5d92`
(downstream result `25954d4aa4a55ab10c6e2c30699f52358f982fb9`);
Metamod `05c5c63a9d595cb84021c3a51fe38366ba4a12a5`;
KHook `2a89535` (abbreviated revision recorded in the source notes).

## Problem and downstream fix
The detour returns from a recall to the recall site with a plain `ret` and
the hooked call's saved registers. `KHook::Recall` calls the recall as a
`__thiscall` member, whose callee must pop the stack arguments, so the recall
site's ESP is off by their size and its epilogue pops arguments into
EBX / ESI / EDI. SourceMod's `LevelInit` hook (and every other hook that
recalls: `FireEvent`, `ChangeLevel`, sounds, voice) crashes srcds.exe on the
first map load. Seen under Wine with the v34 Windows server; the KHook unit
tests pass because their recall sites do not use ESP-relative code or
callee-saved registers after the call.

Fix: `apply-khook-x86-recall.sh` (restore ESP / EBX / ESI / EDI around the
recall call on MSVC x86; `BeginDetour` keeps the original entry's
callee-saved registers).

## Minimal reproduction

On Windows x86 use a hooked __thiscall function with at least one stack argument. In the hook, change an argument and recall it. Inspect ESP and EBX/ESI/EDI immediately before and after recall; keep caller locals live across it. The pinned SourceMod LevelInit hook reproduces this during the first map load.

## Expected result and regression check

The __thiscall stack is balanced and callee-saved registers are intact. A harness that never accesses stack locals or those registers after recall can miss the bug.

## Evidence to attach

Record exact dependency revisions, architecture, compiler, minimal plugin/harness,
and before/after diagnostics. The reproduction above is a procedure, not a new
passing test result.

Source: [existing report 9](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/docs/UPSTREAM_REPORTS.md).
Patch files named above are preserved in the [pinned builder](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/)
and on the `archive/khook` branch. The runtime fixture is
[css34_dhooks_probe.sp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/plugins/css34_dhooks_probe.sp);
[botplay-record.exp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/scripts/botplay-record.exp) contains the unload/reload sequence.
