# x86: a recall restores the callee-saved registers it was re-entered with

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
On a recall (hook changed parameters, `MRES_ChangedHandled`),
`BeginDetour` copies the registers from the recall entry over the ones saved
at the original entry, and uses them when it finally returns to the original
caller. A pre/post stub that does not preserve EBX / ESI / EDI across the
recall therefore corrupts the caller's registers (seen as a crash in
`CCSPlayer::CheckFalling` after a `PlayStepSound` recall). DHooks now saves
and restores every general register; either document this contract or
restore the callee-saved registers from the original entry.

## Minimal reproduction

On Linux x86 install a pre/post hook that changes parameters and recalls a function. Use an assembly caller that sets EBX/ESI/EDI to sentinels before the call and checks them afterwards. Compare stubs that do and do not save these registers. The existing PlayStepSound probe provides an integration case.

## Expected result and regression check

Callee-saved registers at return match the original caller. If preserving them inside hooks is intentional API policy, document that obligation instead of treating every stub as valid.

## Evidence to attach

Record exact dependency revisions, architecture, compiler, minimal plugin/harness,
and before/after diagnostics. The reproduction above is a procedure, not a new
passing test result.

Source: [existing report 8](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/docs/UPSTREAM_REPORTS.md).
Patch files named above are preserved in the [pinned builder](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/)
and on the `archive/khook` branch. The runtime fixture is
[css34_dhooks_probe.sp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/plugins/css34_dhooks_probe.sp);
[botplay-record.exp](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/testing/scripts/botplay-record.exp) contains the unload/reload sequence.
