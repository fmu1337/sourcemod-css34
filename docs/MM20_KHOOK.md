# sm13-mm20-khook — Metamod 2.0 KHook on CS:S v34

Experimental line built from the newest upstream dev heads that run on KHook:

| Component | Pin | Commit |
|-----------|-----|--------|
| SourceMod | 1.13.0-git7565 (`k/sourcehook_alternative` tip + `master` merged at build time) | `25954d4aa4a55ab10c6e2c30699f52358f982fb9` |
| ↳ KHook branch tip | 1.13.0-git7519 | `0cd7f6fcb4e3f09e0adb136f42dfa12305682bcc` |
| ↳ merged `master` | 1.13.0-git7472 | `6eb5f8fa381100ed7cac1ab62a4ece11795a5d92` |
| Metamod:Source | 2.0.0-dev+1472 (`master` tip) | `05c5c63a9d595cb84021c3a51fe38366ba4a12a5` |
| KHook (MM submodule) | 2026-09-16 | `40d233d160b5bf60cc3e732939142b222fbd8ece` |

```bash
CSS34_LINE=sm13-mm20-khook PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh
```

## Why SourceMod comes from the KHook branch

Metamod `master` merged "Provide an alternative to SourceHook" (#223, git ~1450).
It deletes `core/sourcehook/`, stops exporting `g_SHPtr` / `ISourceHook` and
bumps the plugin API so old SourceHook plugins are rejected.

SourceMod `master` (7472) still builds against `<mms>/core/sourcehook` and
installs every hook through `g_SHPtr`. Grafting the old SourceHook headers into
the Metamod tree (the approach in PRs #54 and #55) makes it compile, but at
runtime Metamod hands SourceMod no SourceHook instance, so it cannot work.

What those PRs did, for reference (both closed in favour of this line):

- restore `core/sourcehook/*.h` from git1407 (`git archive 0084b86
  core/sourcehook`, or a vendored copy under `builder/assets/sourcehook/`)
  and add `third_party/khook/include` to SM's include paths, since
  `ISmmPlugin.h` includes `khook.hpp` from git1450+;
- `#include <sourcehook.h>` plus `extern SourceHook::ISourceHook *g_SHPtr` in
  `smsdk_ext.h` / `sourcemm_api.h`, and `g_SHPtr` initialised from
  `ismm->MetaFactory(MMIFACE_SOURCEHOOK, …)` in `SDK_OnMetamodLoad`;
- `GetShApiVersion()` hard-coded to 5 when `METAMOD_PLAPI_VERSION >= 18`,
  because `ISmmAPI::GetShVersions` is gone.

The `MetaFactory` call returns NULL on KHook Metamod, so every `SH_ADD_HOOK`
dereferences a null `g_SHPtr`. On #54 the CI smoke and botplay jobs for that
line failed while all other lines passed. #55 applied the same shim to the
released `sm13-mm20` line, so its pin must stay on git1407
([SM13_MM20.md](SM13_MM20.md)).
The only SourceMod tree that runs on KHook Metamod is the upstream KHook port,
`k/sourcehook_alternative`, so this line pins its tip.

## SourceMod master merge (`builder/sourcemod-khook-merge.sh`)

The KHook branch lags `master` by ~50 commits. The builder brings it up to date
without forking SourceMod: after checking out the KHook tip it recreates one
fixed merge commit.

- `patches/sourcemod-khook-master-merge.take` lists the files taken verbatim
  from `master` (including the `sourcepawn` and `public/amtl` gitlinks);
- `patches/sourcemod-khook-master-merge.patch` holds the conflict resolution
  for the files where both sides touched hook code (core console/event/user
  message hooks, SDKHooks, SDKTools output/sound/tenatives, `AMBuildScript`);
- the tree is committed with fixed author/date, so every host produces the same
  SHA. It is checked against `SM_KHOOK_BUILD_COMMIT` in `versions.env`, and
  the build fails if the take list or patch stop reproducing it.

Bumping either side means redoing the merge in a SourceMod checkout, then
regenerating the take list, the resolution patch and `SM_KHOOK_REV` /
`SM_KHOOK_BUILD_COMMIT` (`git rev-list --count` of the merge commit).

## css34 patches (`builder/patches/apply-sourcemod-khook.sh`)

Called first from `apply-sourcemod-v112.sh`; it is a no-op on SourceHook trees.

1. **KHook API drift.** KHook `96f3c61` renamed `KHook::GetContext()` to
   `GetContextPtr()` (`GetContext<T>()` is now a template). The SM branch still
   uses the old name in `public/vtable_hook_helper.h`, so SDKTools fails to build
   against MM `master`. The patch renames the call.
2. **cstrike port** (`sourcemod-khook-css34.patch`). The SM KHook branch comments
   `extensions/cstrike` out of `AMBuildScript` because it still uses a SourceHook
   `LevelInit` hook and CDetour, which the branch removed. The patch:
   - uses `KHook::Virtual` on `IServerGameDLL::LevelInit` for the timeleft tracker;
   - turns the four CDetour detours (`HandleCommand_Buy_Internal`,
     `GetWeaponPrice`, `TerminateRound`, `CSWeaponDrop`) into `KHook::Member`
     PRE callbacks. When the old detour called the original with changed
     arguments or post-processed its return value, the callback now calls
     `CallOriginal()` itself and supersedes, which keeps the CDetour behaviour;
   - drops `SM.AddCDetour` and re-enables the extension.
3. **SDKTools `Hook_FireOutput` (Windows).** The branch defines the Windows
   x86 variant without the `EntityOutputManager::` qualifier, so MSVC fails to
   link `sdktools.ext` (LNK2019). The patch adds the qualifier.
4. **DHooks linux x86 + ConsoleDetours** — see [DHooks](#dhooks-linux-x86).
5. **mysql.** The branch also disables `dbi.mysql`. Its only SourceHook
   dependencies are `SourceHook::String` and `SourceHook::List` (`sh_string.h`
   / `sh_list.h`, gone from MM), so the patch switches them to `std::string` /
   `std::list` and re-enables it.

## Verified locally (2026-09-23)

- The build passes on glibc 2.31 (`ubuntu:20.04`, same gcc-9/clang-9 toolchain
  as `legacy-build.sh`). `check-package.sh` and `check-metamod-package.sh` pass
  (highest GLIBC 2.29).
- `smoke-test.sh` on a real srcds v34 passes: MM 2.0.0 / SM 1.13.0.7519 with the
  right commits, BinTools, SDK Tools, CS Tools and SDK Hooks loaded, and 17
  plugins running.
- `botplay-test.sh` stress (SMAC, 8 bots, map rotation) passes: SDKHooks
  `OnTakeDamage` hits, ABI probe and SM API probe rounds all clean.
- `css34_cstrike_forward_probe.smx` shows every cstrike detour firing. Masks
  1/2/4 (block a buy, change the price, change the round end delay) run a full
  botplay session with no crash.

With `master` merged (1.13.0.7565) the local smoke test and botplay stress
pass again: all cstrike detours fire every round, SourcePawn 2.0, empty error
log.

`CS_DropWeapon` from a plugin used to crash srcds v34 on every line; it is
fixed for all lines by PR #60 (`css34_cs_probe_mode 8` in botplay stress).

## DHooks (linux x86)

The KHook SourceMod branch rewrote DHooks on top of KHook, but only ships the
linux x86_64 ABI. `sourcemod-khook-dhooks-x86.patch` adds
`src/abi/system_v_i386.cpp`, the i386 System V backend used by 32-bit ep1 /
CS:S v34:

- every parameter, `this` included (`CallConv_THISCALL`), lives on the stack;
  `CallConv_FASTCALL` puts the first two 32-bit integers in ECX / EDX;
  `CallConv_STDCALL` / `CallConv_FASTCALL` callees pop their arguments;
- integers / pointers return in EAX, `float` in x87 ST(0) (FLD / FSTP are
  emitted directly, the KHook x86 assembler has no x87 / SSE instructions);
- `Vector` / `string_t` return through the hidden pointer the callee pops
  (`ret 4`); `HookParamType_Object` by value is copied on the stack;
- the PRE / POST stubs save every general register and the recall path
  restores all of them: when a hook changes parameters (`MRES_ChangedHandled`)
  KHook re-enters the detour and later returns to the original caller with
  the registers it was re-entered with, EBX / ESI / EDI included.

The same patch restores what the rewrite dropped from the old API:
`RegisterLibrary("dhooks")` (`LibraryExists` / `OnLibraryAdded`),
`DHookEnableDetour` / `DHookDisableDetour`, `DHookGetParamAddress` /
`DHookParam.GetAddress`, and `DHookSetFromConf` returning true on success
(false, not an error, when the key is missing).

`sourcemod-khook-consoledetours.patch` fixes a shutdown crash those hooks
exposed: command listeners (`AddCommandListener`) detour `ConCommand::Dispatch`
read from each command vtable. When a KHook virtual hook already owns that
slot, SM detoured the KHook JIT stub instead of the function, and Metamod
crashed restoring the stub's bytes after it had been freed. It now resolves
the real function with `KHook::FindOriginalVirtual`.

Botplay (`css34_dhooks_probe.smx`, gamedata `css34_dhooks_probe.games`)
requires on every line that ships DHooks:

| Hook | Covers |
|------|--------|
| virtual `CCSPlayer::OnTakeDamage` | entity virtual hook, `ObjectPtr` param |
| detour `CCSPlayer::RoundRespawn` | address detour (`THISCALL`, void) |
| POST virtual `CBasePlayer::EyePosition`, `MRES_Override` | `Vector` return through the hidden pointer |
| PRE virtual `CCSPlayer::PlayStepSound`, `MRES_ChangedHandled` | `float` / `bool` / pointer stack params, recall |
| POST detour `CWeaponCSBase::GetMaxSpeed`, `MRES_Override` | `float` return in ST(0) |

Returned vectors / floats and the step volume are range-checked; any bad
value fails the run. Windows (MSVC thiscall / `__fastcall`) is not ported:
`dhooks.ext` is only built for linux.

Known upstream issue, not fixed here: DHooks hooks each entity class
destructor through `KHook::SetupVirtualHook` and never removes that hook, so
unloading `dhooks.ext` (`sm exts unload dhooks`) while the server keeps
running leaves a vtable pointing at unloaded callbacks. A normal shutdown is
clean.

## Windows

`build.yml` builds this line for Windows too (`windows` job matrix). It is
build-only: there is no Windows srcds smoke test.
