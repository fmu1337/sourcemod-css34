# Release blockers: SDKHooks EP1 + Metamod PLAPI (CSS:S v34)

Field report from a live CSS:Source **v34** (EP1 / `server_i486.so`) dedicated
server (Oracle Ampere aarch64 host, 32-bit `srcds_i686`, eSTEAMATiON SCI,
AppID 240), compared against production backup **2021-07-05** and GitHub
release tag [`1.11.0.6572-mm1.10.7`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.11.0.6572-mm1.10.7).

**Treat both items below as release blockers** for shipping a drop-in
replacement of a working v34 SM/MM tree.

Related in-flight work: SDKHooks **vtable** gamedata overlay is in
[#34](https://github.com/fmu1337/sourcemod-css34/pull/34) (rom4s / css34
`builder/assets/gamedata/sdkhooks.games`). That does **not** replace this
write-up: #34 targets post-load crashes (`IndexOfEdict`); the load-time
`entity listeners` / `gEntList` path and the PLAPI mix-up are separate.

## Environment (reference)

| Item | Value |
|------|--------|
| Host | Oracle Cloud Ampere (aarch64) running x86 `srcds_i686` via multiarch |
| Game | CSS:S v34, `./srcds_run -binary ./srcds_i686` |
| Fresh package | SM **1.11.0.6572** + MM from tag `1.11.0.6572-mm1.10.7` |
| Working reference | Live DM backup **2021-07-05** (`sm_backup_core`) |
| Repro instance | `~/v34/sm6572_repro/` on UDP **27035** (prod DM stays on **27015** with SM **6522**) |

## Blocker A — SDKHooks fails to set up entity listeners

### Symptoms (when SM 6572 actually loads)

```
Failed lookup of gEntList - Reverting to networkable entities only
[SM] Unable to load extension "sdkhooks.ext": Failed to setup entity listeners
```

Confirmed in `addons/sourcemod/logs/errors_*.log` on every map load while
`SourceMod Version: 1.11.0.6572` was running (logs `L20260714.log`,
`errors_20260715.log`).

Consequence: any plugin needing SDKHooks fails (`flash_spawner`, `map_decals`,
`disconnect_msg`, VIP ammo, etc.). Mixed fresh core + old plugins/gamedata
also segfaults in `server_i486.so` on map load / changelevel.

### Cause chain (verified in SM source)

SDKHooks `EntListeners()` calls `gamehelpers->GetGlobalEntityList()`. If that
is NULL (and there is no `EntityListenersPtr` fallback), load fails with
**Failed to setup entity listeners**. The SDKTools line about `gEntList` is
the same underlying failure.

`EntityListeners` offset **65572** is identical in the 2021 backup, the
published 6572 package, and #34’s rom4s overlay — it is **not** what
distinguishes load failure from success.

### Backup vs release gamedata (key deltas)

| File | Production backup (works) | Release `1.11.0.6572` |
|------|---------------------------|------------------------|
| `sdkhooks.games/common.games.txt` | `EntityListeners` 65572 | same |
| `sdkhooks.games/game.cstrike.txt` | v34 vtables (e.g. OnTakeDamage **60/61**) | upstream-ish (e.g. **62/63**) — wrong for EP1; tracked in **#34** |
| `core.games/engine.ep1.txt` | `#default` + `@gEntList` (+ Cmd_ExecuteString, …) | `"cstrike"` + `@gEntList` (signature **present**) |
| `sdkhooks.ext.2.ep1.so` | SHA ≠ release | different binary |

Local `server_i486.so` **does** export `gEntList` (`GLOBAL` `OBJECT` in `.dynsym`,
size 65592). CI smoke on the matched SM+MM package loads extensions (fails hard
on `<FAILED>`). So the field load-fail may still involve install mix / host
quirks, but EP1 gamedata + sdkhooks package content still need re-verify against
a real v34 `server_i486.so` and an explicit **SDK Hooks** smoke assert.

### Minimal reproduce

1. Clean CSS:v34 tree; start `srcds_i686 -game cstrike +map de_dust2 -insecure`.
2. Install release SM+MM **as a matched pair** (see Blocker B).
3. `sm exts list` / error log.
4. Expected: SDKHooks running. Observed (when 6572 loaded): entity-listeners fail.

## Blocker B — Metamod plugin iface (`11 < 14`) on clean / hybrid installs

### Symptoms (second-instance / swap matrix)

On the same host, with Metamod reporting **`1.11.0-dev+1130`**, plugin iface
**16:14** (current:min):

| Swap | Result |
|------|--------|
| Backup SM **6522** full tree | SM loads; SDKHooks OK |
| Only replace `sourcemod_mm_i486.so` with release **6572** shim | SM **6522** still loads |
| Replace `sourcemod.*.ep1.so` with release **6572** | **Fails**: `Older Metamod version required, probably 1.4.x (11 < 14)` |
| Full release SM+MM **6572** while leftover MM 1.11 still wins | Same `11 < 14` — SourceMod never loads |
| Under SM6522, swap only `sdkhooks`/`sdktools` from **6572** | Exts fail with same `11 < 14` (never reaches entity-listener path) |

Message originates in Metamod (`metamod_plugins.cpp`): plugin
`GetApiVersion() < PLAPI_MIN_VERSION`.

### Verified binary facts (tag `1.11.0.6572-mm1.10.7`)

| Artifact | Field |
|----------|--------|
| Release `addons/metamod/bin/metamod.1.ep1.so` | String **`1.10.7-dev`** (not 1.11) |
| Backup `addons/metamod/bin/metamod.2.ep1.so` | String **`1.11.0-dev+1130`** |
| Release SM/exts | Intentionally advertise **PLAPI 11** |

### Why the repo pins PLAPI 11

`builder/patches/apply-mmsource-css34.sh` is explicit:

- CS:S v34 / rom4s-era MM uses **core-legacy** SourceHook **v4** and **PLAPI 11**.
- Upstream MMS 1.10-dev headers alone produce modern SH / ISmmAPI that crash on
  css34 MM when registering hooks.
- The patch sets `METAMOD_PLAPI_VERSION` to **11** so SourceMod/exts compile
  against the legacy vtable layout; `GetApiVersion()` returns **11**.

So release SM **must** pair with release (or rom4s-compatible) **MM 1.10.x /
`metamod.1.ep1` / PLAPI 11**. Mixing with MM **1.11** (`metamod.2.ep1`, iface
min **14**) is unsupported and fails before any SDKHooks gamedata runs.

Tag naming `…-mm1.10.7` matches the packaged `1.10.7-dev` string. If
`meta version` shows `1.11.0-dev+1130`, runtime Metamod is **not** the release
binary (common trap: leftover `metamod.2.ep1.so` from the 2021 / myarena tree
while `metamod.1.ep1.so` was copied beside it).

See also the myarena / `1.ep1` vs `2.ep1` matrix already recorded in
[PATCH_STRATEGY.md](PATCH_STRATEGY.md).

## Out of scope (but blocked by A)

Production `plugins/cssdm/*.smx` need `cssdm.ext.*.so`. The fresh package does
**not** ship CS:S DM. Fix A (and a matched MM pair) first; package `cssdm`
separately if desired.

## Secondary friction (not root cause)

Stock `adminmenu.smx` can fail `AskPluginLoad` with error 23 when Material Admin
already registered topmenu natives. Packaging / plugin-set issue on v34, not
SDKHooks.

## Ask / follow-ups for the repo

1. **Blocker A:** Re-sync/verify EP1 `core.games` + `sdkhooks.games` (+ rebuild
   test of sdkhooks/sdktools) against a real v34 `server_i486.so`. Land #34’s
   css34 sdkhooks vtables. Add CI assert that **SDK Hooks** is loaded (not only
   BinTools / SDK Tools / CS Tools).
2. **Blocker B:** Document the contract in release notes / README: css34 SM ↔
   MM PLAPI **11** / SH v4 / `metamod.1.ep1`. Smoke-fail if `meta version` is
   not the pinned `1.10.7-dev` (or if `metamod.2.ep1` is what actually loads).
   Do **not** hybrid-test release SM against backup/myarena MM 1.11.
3. Clarify packaging: tag says `mm1.10.7`; users must install **both** SM and MM
   tarballs and remove conflicting `metamod.2.ep1.so` from older trees.

## Operator checklist (clean second instance)

1. `meta version` → expect **`1.10.7-dev`**, not `1.11.0-dev+1130`.
2. `addons/metamod/bin/`: release **`metamod.1.ep1.so`** present; do not leave a
   winning **`metamod.2.ep1.so`** from the backup tree.
3. Install release **SM tar + MM tar as a pair** (no shim swaps).
4. Then check SDKHooks / `gEntList`; apply #34 gamedata if hooks load but crash.
