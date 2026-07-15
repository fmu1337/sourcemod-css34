# Field report: SDKHooks EP1 + Metamod PLAPI (CSS:S v34)

Field notes from a live CSS:Source **v34** (EP1 / `server_i486.so`) dedicated
server (Oracle Ampere aarch64 host, 32-bit `srcds_i686`, eSTEAMATiON SCI,
AppID 240), compared against production backup **2021-07-05** and GitHub
release tag [`1.11.0.6572-mm1.10.7`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.11.0.6572-mm1.10.7).

**Verdict (re-checked against CI after [#34](https://github.com/fmu1337/sourcemod-css34/pull/34) landed):**

| Symptom | Real package bug? | What it actually is |
|---------|-------------------|---------------------|
| `Older Metamod… (11 < 14)` | **No** | Install mix: PLAPI-11 SM under leftover **MM 1.11** / `metamod.2.ep1` |
| `Failed to setup entity listeners` / `gEntList` on **matched** SM+MM | **Not reproduced** in CI | Almost certainly collateral of the mix (or host quirk); see below |
| Wrong SDKHooks **vtables** in tagged `1.11.0.6572-mm1.10.7` | **Yes** (post-load) | Upstream-ish `OnTakeDamage` 62/63 vs css34 60/61 — fixed on **master** via #34 gamedata overlay; needs a **retag** to ship |

These notes stay useful as an operator trap guide. They are **not** evidence that the matched release pair refuses to load SDKHooks.

## Environment (reference)

| Item | Value |
|------|--------|
| Host | Oracle Cloud Ampere (aarch64) running x86 `srcds_i686` via multiarch |
| Game | CSS:S v34, `./srcds_run -binary ./srcds_i686` |
| Fresh package | SM **1.11.0.6572** + MM from tag `1.11.0.6572-mm1.10.7` |
| Working reference | Live DM backup **2021-07-05** (`sm_backup_core`) |
| Repro instance | `~/v34/sm6572_repro/` on UDP **27035** (prod DM stays on **27015** with SM **6522**) |

## Symptom A — `Failed to setup entity listeners` / `gEntList`

### What was reported

When SourceMod **1.11.0.6572** appeared to be running on the Ampere host:

```
Failed lookup of gEntList - Reverting to networkable entities only
[SM] Unable to load extension "sdkhooks.ext": Failed to setup entity listeners
```

### CI reality (matched SM + MM on amd64 Debian)

On the repo’s v34 smoke / botplay tree:

- Stock smoke may **not list** SDKHooks at all — it only autoloads when a plugin
  requires it, and smoke’s required-ext assert is currently BinTools / SDK Tools /
  CS Tools (gap; should assert SDK Hooks when an SMAC/botplay plugin is present).
- With SMAC/botplay (#34), **SDK Hooks loads cleanly** for:
  - rom4s SM 6572
  - built master SM 6572 (with #34 css34 `sdkhooks.games` overlay)
- No `entity listeners` / `gEntList` load failure in those sessions.

`EntityListeners` offset **65572** is identical in the 2021 backup, the published
6572 package, and #34’s overlay — it does **not** distinguish success from
failure. Release `core.games/engine.ep1.txt` already has linux `@gEntList`.

So for a **clean matched** install on a normal x86_64 host, treat this symptom as
**not a confirmed release blocker**. Re-check only if it still appears after the
checklist below (especially MM version). The Ampere/multiarch host remains an
unverified variable.

### Related real issue (vtables, not listeners)

Published tag `game.cstrike.txt` still has upstream-ish offsets
(`OnTakeDamage` linux **63**). Production/css34 backup and #34 assets use **61**.
That class of bug shows up **after** hooks load (crashes / `IndexOfEdict`), not
as `Failed to setup entity listeners`. Master already overlays css34
`builder/assets/gamedata/sdkhooks.games/`; cut a new tag to publish it.

## Symptom B — Metamod plugin iface (`11 < 14`)

### What was reported

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

### Package facts (tag `1.11.0.6572-mm1.10.7`) — not a build bug

| Artifact | Field |
|----------|--------|
| Release `addons/metamod/bin/metamod.1.ep1.so` | String **`1.10.7-dev`** only (MM package has **no** `metamod.2.ep1.so`) |
| Backup / myarena `metamod.2.ep1.so` | String **`1.11.0-dev+1130`**, iface min **14** |
| Release SM/exts | Intentionally advertise **PLAPI 11** |

### Why the repo pins PLAPI 11

`builder/patches/apply-mmsource-css34.sh` is explicit:

- CS:S v34 / rom4s-era MM uses **core-legacy** SourceHook **v4** and **PLAPI 11**.
- Upstream MMS 1.10-dev headers alone produce modern SH / ISmmAPI that crash on
  css34 MM when registering hooks.
- The patch sets `METAMOD_PLAPI_VERSION` to **11** so SourceMod/exts compile
  against the legacy vtable layout; `GetApiVersion()` returns **11**.

Release SM **must** pair with release (or rom4s-compatible) **MM 1.10.x /
`metamod.1.ep1` / PLAPI 11**. Mixing with MM **1.11** (`metamod.2.ep1`, iface
min **14**) is unsupported and fails **before** any SDKHooks gamedata runs.

If `meta version` shows `1.11.0-dev+1130`, runtime Metamod is **not** the release
binary — usual trap: leftover `metamod.2.ep1.so` from the 2021 / myarena tree
wins over the copied `metamod.1.ep1.so`.

See also the myarena / `1.ep1` vs `2.ep1` matrix in
[PATCH_STRATEGY.md](PATCH_STRATEGY.md).

**Classification: operator / hybrid-install confusion**, documented so it is not
re-investigated as a broken release tarball.

## Out of scope

Production `plugins/cssdm/*.smx` need `cssdm.ext.*.so`. The fresh package does
**not** ship CS:S DM. Package `cssdm` separately if desired.

Stock `adminmenu.smx` can fail `AskPluginLoad` with error 23 when Material Admin
already registered topmenu natives — plugin-set friction, not SDKHooks.

## Operator checklist (clean second instance)

1. `meta version` → expect **`1.10.7-dev`**, not `1.11.0-dev+1130`.
2. `addons/metamod/bin/`: release **`metamod.1.ep1.so`** present; **remove** any
   leftover **`metamod.2.ep1.so`** from the backup tree.
3. Install release **SM tar + MM tar as a pair** (no shim / single-file swaps).
4. `sm exts list` after a plugin that requires SDKHooks (or SMAC) → expect
   **SDK Hooks** running. If hooks load but crash later, refresh sdkhooks
   gamedata from master (#34) / retag.
5. Do **not** hybrid-test release SM against backup/myarena MM 1.11.

## Follow-ups for the repo

1. **Retag** (or patch release) so published `1.11.0.6572-*` includes #34 css34
   `sdkhooks.games` offsets.
2. Smoke/botplay: assert **SDK Hooks** is loaded when a requiring plugin is
   installed (smoke alone can pass without ever autoloading it).
3. Keep this doc linked from README / release notes as the PLAPI **11** contract
   and “don’t leave `metamod.2.ep1` around” warning.
