# sm13-bleeding — latest upstream SM/MM for CSS v34

Experimental release line tracking **latest AlliedMods master** (Sep 2026):

| Component | Pin | Commit |
|-----------|-----|--------|
| SourceMod | **1.13.0-git7461** | `809392d1dc0436b064f1d2d03cc498551f2a97b9` |
| Metamod:Source | **2.0.0-git1467** | `7e24ce9e7a03bfeb5c8ab1e4dd55d5d5747f3d33` |

Build: `CSS34_LINE=sm13-bleeding PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh`

## Upgrade from sm13-dev (7404 / MM 1407)

### SourceMod 7404 → 7461 (57 commits)

Notable upstream changes relevant to css34:

| Area | Change | css34 impact |
|------|--------|--------------|
| **SourcePawn** | Static `libsourcepawn_static` only; no shared `sourcepawn.jit.x86.so` | Patched `BuildStaticCoreLib` for pthread/rt DT_NEEDED; logic.so embeds SP |
| **Init flow** | `InitializeBridge()` moved from `StartSourceMod()` to `InitializeSourceMod()` | Boot-trace anchors updated in `apply-sm-boot-trace.sh` |
| **MySQL** | MariaDB connector replaces libmysqlclient; static libssl | No css34 patch needed; verify `dbi.mysql.ext.so` on legacy glibc |
| **Pattern scan** | ELF segment-aware pattern scan (#2520) | Should help gamedata/sig scans on 32-bit Linux |
| **Stack align** | Linux x86 stack alignment crash fix | Relevant for headless botplay / API probe |
| **hl2sdk-manifests** | Multiple manifest bumps | Episode1 defines patched by existing `apply-sourcemod-v112.sh` |
| **Forwards** | Private forward / mid-call delete fixes | Botplay stress + API probe benefit |

### Metamod 1407 → 1467 (60 commits)

Most commits are **Source 2 / KHook** (CS2, Dota2). css34-relevant:

| Area | Change | css34 impact |
|------|--------|--------------|
| **Versioning** | Detached HEAD SHA handling upstream | `apply-mmsource-v112.sh` patch now redundant (upstream merged) |
| **libstdc++** | Hide statically-linked libstdc++ symbols | Aligns with our static-embed logic.so approach |
| **hl2sdk-manifests** | Routine bumps | Episode1 tier1-before-vstdlib patch still applies |
| **MSVC xor** | Reserved word fix | Windows builds only |

## Patches updated for 7461

- `apply-sm-boot-trace.sh` — `InitializeSourceMod` now traces `LoadBridge` + `InitializeBridge`
- `apply-sourcemod-v112.sh` — `BuildStaticCoreLib` pthread/rt (replaces `BuildDynamicCoreLib` on 7461+)
- `apply-sourcemod-v112.sh` + `patches/cxx17-compat/span` — C++17 `std::span` polyfill (7461 SourcePawn uses `<span>` but css34 builds at `-std=c++17`)
- `apply-mmsource-v112.sh` — restores `core/sourcehook/` headers from MM 1407 when MM 1467+ (KHook) removed them; SM 7461 still compiles against SourceHook APIs
- `apply-sourcemod-v112.sh` — adds `third_party/khook/include` to `ConfigureForHL2` when present (MM 1467 `ISmmPlugin.h` includes `khook.hpp`)
- `apply-sourcemod-v112.sh` — includes `sourcehook.h` from `smsdk_ext.h` when MM 2.0+ KHook no longer pulls it in via `ISmmPlugin.h` (sdktools `CallClass` / `SH_DECL_*`)

## Not yet verified on this branch

Full `legacy-build` + smoke + botplay matrix requires **debian:11 docker** (host Ubuntu 24.04 lacks gcc-9/clang-9 multilib). CI on push will be the first end-to-end gate.

## Release tag (when green)

```
git tag 1.13.0.7461-mm2.0.0
git push origin 1.13.0.7461-mm2.0.0
```

Maps to `CSS34_LINE=sm13-bleeding` in `release.yml`.
