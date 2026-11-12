# Metamod 2.0 / KHook: what we tried and why we stopped

Everything about the two Metamod 2.0 lines in one place. Neither is built on master; their builder,
patches and original docs live on the
[`archive/khook`](https://github.com/fmu1337/sourcemod-css34/tree/archive/khook) branch.
Their releases and pointers stay published.

| Line | SourceMod | Metamod | State | Pointer serves |
|------|-----------|---------|-------|----------------|
| `sm13-mm20` | 1.13.0.7404 | 2.0 git1407, the last Metamod 2.0 with SourceHook | retired | `1.13.0.7404-mm2.0.0-r2` |
| `sm13-mm20-khook` | 1.13.0.7565: the KHook branch `k/sourcehook_alternative` (`0cd7f6f`) with `master` (`6eb5f8f`) merged in | 2.0 git1472 (`05c5c63`), KHook `2a89535` | frozen | `1.13.0.7565-mm2.0.0-khook-dhooks-r2` (Linux + Windows, ships `dhooks.ext`) |

## The problem

Metamod `master` replaced SourceHook with KHook ("Provide an alternative to SourceHook", MM #223,
around git1450). It deletes `core/sourcehook/`, stops exporting `g_SHPtr` / `ISourceHook` and raises the
plugin API, so plugins built against SourceHook are refused. SourceMod `master` still installs every hook
through `g_SHPtr`, so it cannot run on Metamod 2.0 git1450+. Only the SourceMod KHook branch
(`k/sourcehook_alternative`, not merged into `master`) can.

Grafting the old SourceHook headers into Metamod (PRs #54, #55) compiles, but at run time
`MetaFactory(MMIFACE_SOURCEHOOK)` returns NULL and every hook dereferences a null `g_SHPtr`: smoke and
botplay were red. Both PRs were closed. That is also why `sm13-mm20` must stay on git1407.

## What we built for `sm13-mm20-khook`

- **Master merge.** The KHook branch lagged `master` by about 50 commits. The builder recreated one fixed
  merge commit from a take list and a conflict-resolution patch, with fixed author and date, so every host
  produced the same SHA.
- **Ports the branch had dropped.** `game.cstrike` (its four CDetour detours moved to `KHook::Member`,
  `LevelInit` to `KHook::Virtual`), `dbi.mysql` (`SourceHook::String` / `List` → `std::string` / `std::list`),
  the Windows `Hook_FireOutput` link error, and a KHook API rename (`GetContext` → `GetContextPtr`).
- **DHooks for x86.** The rewritten DHooks supported only Linux x86_64. We wrote the 32-bit backend
  (i386 System V on Linux, MSVC conventions on Windows: stack params, `this` in ECX on Windows, `float`
  returns in x87 ST(0), hidden-pointer `Vector` returns), restored the old API it had dropped
  (`RegisterLibrary("dhooks")`, `DHookEnableDetour`, `DHookGetParamAddress`, `DHookSetFromConf` returning
  true), fixed unloading DHooks on a running server, and fixed command listeners detouring a KHook JIT stub.
- **Windows.** A KHook recall on MSVC x86 returned with a plain `ret` from a `__thiscall` callee and
  corrupted ESP / EBX / ESI / EDI: `srcds.exe` crashed on the first map. Fixed in KHook's recall path.
  Native and Wine smoke with the DHooks probe passed afterwards.

Smoke, botplay stress (SMAC, SDKHooks, cstrike detours) and the DHooks probe (virtual hooks, detours,
`Vector` / `float` returns, `MRES_ChangedHandled` recall, unload / reload) all passed on Linux; Windows
passed smoke and the DHooks probe.

## Pros and cons

**For KHook / Metamod 2.0**

- It is where upstream Metamod is going: Metamod 1.12 gets no new features.
- One hooking library for Metamod, SourceMod and DHooks, without SourceHook's macro layer.
- The 32-bit work above made DHooks on KHook fully usable on CS:S v34, on Linux and Windows.

**Against (why it stopped)**

- **Upstream SourceMod does not run on it.** We would ship a fork of an unmerged branch plus our own
  merge of `master`, redone on every bump. Weekly bump PRs (`upstream-bump.yml`) cannot do that.
- **Old Metamod plugins break.** Metamod 2.0 refuses SourceHook-era plugins; v34 servers still run
  PLAPI 7–12 plugins, which `sm12-latest` / `sm13-latest` keep running through the legacy-plugin bridge.
- **x86 is not an upstream target.** Ten bugs on the way were ours to find and fix (list below); every
  upstream change to KHook or DHooks could break 32-bit again, and only we would notice.
- **Cost.** Its own patch layer, merge tooling, Windows fixes and CI rows, for a line almost nobody installs.
- `sm13-latest` on Metamod 1.12 already gives SourceMod 1.13 with DHooks, the bridge and weekly bumps.

## Decision (owner, 2026-10-15)

`sm13-mm20` is retired, `sm13-mm20-khook` is frozen outside CI, and their code moved to `archive/khook`.
Line IDs, pointers and releases stay; no new builds. Revisit when SourceMod `master` merges the KHook port:
then `sm13-latest` moves to Metamod 2.0 as one line, and the legacy-plugin bridge has to be solved there
first.

## Upstream bugs found (drafts, not filed)

Full text with reproduction steps:
[`docs/upstream-reports` 06–15 at `2dde54f`](https://github.com/fmu1337/sourcemod-css34/tree/2dde54f/docs/upstream-reports).

| # | Where | Bug |
|---|-------|-----|
| 1 | SM DHooks (KHook) | `dhooks.ext` no longer registers the `dhooks` library |
| 2 | SM DHooks (KHook) | `DHookSetFromConf` returns 0 on success |
| 3 | SM DHooks (KHook) | legacy natives declared but not registered |
| 4 | SM DHooks (KHook) | unloading `dhooks.ext` crashes the server; reload is broken |
| 5 | SM DHooks (KHook) | only Linux x86_64 is supported |
| 6 | SM KHook branch | ConsoleDetours detours the KHook stub, not `ConCommand::Dispatch` |
| 7 | SM KHook branch | build breaks against current KHook / MSVC |
| 8 | KHook | x86 recall restores the callee-saved registers it was re-entered with |
| 9 | KHook (MSVC x86) | recall corrupts the recall site's stack and registers |
| 10 | SM DHooks (KHook) | does not build / run on Windows x86 |

## Known-bad assets

The first Windows assets of the KHook tags crashed `srcds.exe` on the first map. Use
`1.13.0.7565-mm2.0.0-khook-dhooks-r2` (or `line-sm13-mm20-khook`).
