# sm13-mm20-khook — MM 2.0 KHook experiment (branch `cursor/mm20-khook-c33d`)

Experimental line pairing **SourceMod 1.13.0-git7472** with **Metamod 2.0.0-dev+1469** where upstream removed SourceHook in favour of KHook.

| Component | Pin | Commit |
|-----------|-----|--------|
| SourceMod | 1.13.0-git7472 | `6eb5f8fa381100ed7cac1ab62a4ece11795a5d92` |
| Metamod | 2.0.0-dev+1469 | `fa6f80e4662e5b96cc2e97722d812f374581dfd8` |

Build:

```bash
CSS34_LINE=sm13-mm20-khook PURE_SOURCE_BUILD=1 builder/docker/legacy-build.sh
```

## Status

Not targeted for `master` until smoke + botplay pass. Requires css34 patches in:

- `apply-mmsource-v112.sh` — restore SourceHook headers from MM 1407 for compile
- `apply-sourcemod-v112.sh` — KHook include paths, `g_SHPtr` extern/init, `GetShApiVersion` for PLAPI 18+

Production SM 7472 line uses **MM 1.12 git1226** (`sm13-latest`) instead — see [SM13_LATEST.md](SM13_LATEST.md).

Stable MM 2.0 on v34 without KHook breakage remains **git1407** with SM 7404 (`sm13-mm20` on `master` — [SM13_MM20.md](SM13_MM20.md)).

Native KHook SM port (separate track): `claude/khook-mm-2-0-v34-k9wv3x`.
