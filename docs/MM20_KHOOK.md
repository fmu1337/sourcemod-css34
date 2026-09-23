# sm13-mm20-khook — Metamod 2.0 KHook on CS:S v34

Experimental line built from the newest upstream dev heads that run on KHook:

| Component | Pin | Commit |
|-----------|-----|--------|
| SourceMod | 1.13.0-git7519 (`k/sourcehook_alternative` tip) | `0cd7f6fcb4e3f09e0adb136f42dfa12305682bcc` |
| Metamod:Source | 2.0.0-dev+1469 (`master` tip) | `fa6f80e4662e5b96cc2e97722d812f374581dfd8` |
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
the Metamod tree (the approach in PR #54) makes it compile, but at runtime
Metamod hands SourceMod no SourceHook instance, so it cannot work.
The only SourceMod tree that runs on KHook Metamod is the upstream KHook port,
`k/sourcehook_alternative`, so this line pins its tip.

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
3. **mysql.** The branch also disables `dbi.mysql`. Its only SourceHook
   dependency is `SourceHook::String` (`sh_string.h`, gone from MM), so the
   patch switches those members to `std::string` and re-enables it.

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

Known issue on **all** lines, not KHook specific: calling `CS_DropWeapon` from a
plugin crashes srcds v34. The released `1.13.0.7404-mm1.12.0` (SourceHook +
CDetour) crashes the same way.

Windows is not built for this line yet.
