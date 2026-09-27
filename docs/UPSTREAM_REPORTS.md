# Upstream reports (drafts)

Bugs found while porting the KHook SourceMod branch (`k/sourcehook_alternative`)
and Metamod 2.0 KHook to CS:S v34. Each one is fixed or worked around in this
repository; the text below is ready to file upstream (alliedmodders/sourcemod,
alliedmodders/metamod-source, Kenzzer/khook). Nothing has been filed yet.

Pins: SourceMod KHook branch `0cd7f6f` merged with master `6eb5f8f` (7565),
Metamod 2.0 master `05c5c63` (git1472), KHook `2a89535`.

## SourceMod — DHooks (KHook rewrite)

### 1. `dhooks.ext` no longer registers the `dhooks` library

Plugins that detect DHooks with `LibraryExists("dhooks")` /
`OnLibraryAdded("dhooks")` (the documented pattern for the old extension) see
it as missing. The rewrite's `SDK_OnLoad` never calls
`sharesys->RegisterLibrary(myself, "dhooks")`.

Fix: `sourcemod-khook-dhooks-x86.patch`, `src/main.cpp`.

### 2. `DHookSetFromConf` returns 0 on success

`DHookSetup_SetFromConf` falls through with `return 0` after it set the
address, so `if (!DHookSetFromConf(...))` treats every success as a failure.
The old extension returned 1 on success and 0 (no error) when the key is
missing.

Fix: same patch, `src/natives/dhooksetup.cpp`.

### 3. Legacy natives removed

`DHookEnableDetour`, `DHookDisableDetour`, `DHookGetParamAddress` and
`DHookParam.GetAddress` are still declared in `dhooks.inc` but not registered,
so old plugins fail with "Native is not bound".

Fix: same patch, `src/natives/dynamicdetour.cpp`, `src/natives/dhookparam.cpp`.

### 4. Unloading `dhooks.ext` on a running server crashes it, and a reload is broken

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

### 5. Only linux x86_64 is supported

`AMBuilder` builds DHooks for linux x86_64 only, and the rewrite deleted
`extensions/dhooks/version.rc`, which the Windows build needs. The patch adds
`src/abi/x86.cpp`, a 32-bit backend for i386 System V (Linux) and MSVC
(Windows), and restores `version.rc`.

## SourceMod — KHook branch

### 6. ConsoleDetours detours the KHook stub instead of `ConCommand::Dispatch`

`GenericCommandHooker::MakeHookable` reads `ConCommand::Dispatch` from each
command's vtable. When a KHook virtual hook already owns that slot, the slot
holds the KHook JIT stub, and the inline detour is written into the stub.
On shutdown Metamod frees the stub first, then restoring the detour writes
into freed memory (crash in `safetyhook::InlineHook::destroy`).

Fix: resolve the real function with
`KHook::FindOriginalVirtual(vtable, KHook::GetVtableIndex(&ConCommand::Dispatch))`
(`sourcemod-khook-consoledetours.patch`).

### 7. Build breaks against current KHook / MSVC

- KHook `96f3c61` renamed `KHook::GetContext()` to `GetContextPtr()`; the
  branch still calls the old name.
- `extensions/sdktools/output.cpp`: the Windows x86 definition of
  `Hook_FireOutput` lacks the `EntityOutputManager::` qualifier (LNK2019).

Fix: `apply-sourcemod-khook.sh`.

## KHook

### 8. x86: a recall restores the callee-saved registers it was re-entered with

On a recall (hook changed parameters, `MRES_ChangedHandled`),
`BeginDetour` copies the registers from the recall entry over the ones saved
at the original entry, and uses them when it finally returns to the original
caller. A pre/post stub that does not preserve EBX / ESI / EDI across the
recall therefore corrupts the caller's registers (seen as a crash in
`CCSPlayer::CheckFalling` after a `PlayStepSound` recall). DHooks now saves
and restores every general register; either document this contract or
restore the callee-saved registers from the original entry.

## KHook (Windows x86)

### 9. A recall corrupts the recall site's stack and registers on MSVC x86

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

### 10. DHooks does not build / run on Windows x86

`VOID` enumerator (winnt.h macro), missing `version.rc`, `dynamic_cast` with
SourceMod's `/GR-`, and `add_listener` on a null `ISDKHooks` when SDK Hooks is
not loaded. Fixed in `sourcemod-khook-dhooks-x86.patch`.
