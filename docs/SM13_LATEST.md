# sm13-latest — latest SourceMod pin for CSS v34

Release line with the newest **SourceMod 1.13** pin paired with **Metamod 1.12 git1228** (classic SourceHook, no KHook breakage):

| Component | Pin | Commit |
|-----------|-----|--------|
| SourceMod | **1.13.0-git7478** | `b34de51b8c7f92fc2a7242fc0195e2d64a69cefd` |
| Metamod:Source | **1.12.0-git1228** | `cb47755826fad1483291e5dc00222aa64303d12f` |

Install: `line-sm13-latest` (the published pointer stays on the last released tag until this pin is tagged), see [README](../README.md#what-to-install).

Build:

```bash
CSS34_LINE=sm13-latest builder/docker/build.sh
```

MM 2.0 git1450+ (KHook) lives in its own line, `sm13-mm20-khook` ([MM20_KHOOK.md](MM20_KHOOK.md)); SM `master` cannot run on it.

## Replaces sm13-dev (7404)

`sm13-dev` (7404 + MM 1.12) is retired from the CI matrix; this line is the default SM 1.13 pin.

### SourceMod 7404 → 7472

| Area | Change | css34 impact |
|------|--------|--------------|
| **SourcePawn** | Static `libsourcepawn_static` only | `BuildStaticCoreLib` pthread/rt; logic.so embeds SP |
| **Init flow** | `InitializeBridge()` moved to `InitializeSourceMod()` | Boot-trace in `apply-sm-boot-trace.sh` |
| **MySQL** | MariaDB connector on 7461+ | `db-configure-args.sh` + `checkout-deps.sh` |
| **C++** | Upstream `-std=c++20` / `std::span` | Kept. GCC 10.2 in manylinux2014 compiles it; no span polyfill |

## Patches for 7472 (this line)

- `apply-sm-boot-trace.sh` — `InitializeSourceMod` traces `LoadBridge` + `InitializeBridge`
- `apply-sourcemod-v112.sh` — `BuildStaticCoreLib` pthread/rt; upstream `-std=c++20` left in place, sourcepawn `-Wno-sign-compare` anchored on that line
- `db-configure-args.sh` / `checkout-deps.sh` — MariaDB vs mysql configure flags

## Release tag

`1.13.0.7472-mm1.12.0` maps to `CSS34_LINE=sm13-latest` in `release.yml`. The tag already exists;
a rebuild of the same pins takes the next revision suffix:

```
git tag 1.13.0.7472-mm1.12.0-r3
git push origin 1.13.0.7472-mm1.12.0-r3
```

A new SourceMod revision needs a new base tag (`1.13.0.<rev>-mm1.12.0`) and its mapping in `release.yml`.
