# CS:S v34 dedicated: launch parameters reference

Complete reference of **command-line flags** consumed by the CSS v34 dedicated stack, validated on stock binaries from `srcds_css34_l_a.zip` (2010-03-21), cross-checked against eSTEAM overlay and BufferFix `srcds_patch`.

| Method | Detail |
|---|---|
| Discovery | NUL-terminated `[+-]flag` scrape in ELF + `srcds_run` |
| Verification | `imm32` xref (push/mov of string VA) + `addr2line` (unstripped DWARF) |
| Re-scrape | `testing/scripts/extract-srcds-params.sh` |

**Layers:** wrapper `srcds_run` → loader `srcds_i686` → `bin/dedicated_*.so` → `bin/engine_*.so` → `cstrike/bin/server_*.so` (+ `tier0` / `steamclient`).

Unknown argv tokens are ignored (`FindParm` / `CheckParm` miss → no-op). Flags below are only those with a verified consumer.

`+name value` on the command line is the engine’s way to queue a **console command / ConVar** before/during init (e.g. `+map`, `+sv_pure 0`). Only `[+-]` tokens with an ELF xref are listed as “flags”; common `+cvar` examples used in hosting are noted where verified.

---

## How to read this doc

| Column | Meaning |
|---|---|
| **Layer** | Who parses it: **W** wrapper, **D** dedicated, **E** engine, **G** game DLL, **T** tier0, **S** steamclient |
| **Takes value?** | Whether the next argv word is consumed (`ParmValue`) |
| **DS useful?** | Relevant on a headless dedicated server |

---

## 1. Wrapper only — `srcds_run` (W)

These are **shell** options. If you start `./srcds_i686` directly (MyArena-style), they do nothing unless the engine also defines the same name (only `-game` / `-pidfile` overlap with different implementations).

| Flag | Value | Description |
|---|---|---|
| `-game <dir>` | yes | Mod directory (default `cstrike` if omitted). Must exist as a folder. |
| `-binary <path>` | yes | Skip CPU auto-detect; run this ELF (`srcds_i486` / `i686` / `amd`). Override also via env `FORCE`. |
| `-norestart` | no | Do not loop-restart after the child exits. Default is restart-on. **Does not detect hangs** — only exit codes. |
| `-timeout <sec>` | yes | Seconds to sleep between restart attempts (default `10`). |
| `-debug` | no | Enable core dumps (`ulimit -c`); after non-zero exit run `gdb` batch (`bt`, locals, …) into the debug log. **Not** engine developer mode. |
| `-debuglog <file>` | yes | gdb output file (default `debug.log`). |
| `-gdb <path>` | yes | Debugger binary (default `gdb`). |
| `-pidfile <file>` | yes | Intended pid path when `-debug` is set. In this CSS `srcds_run`, appending `-pidfile` to the **engine** cmdline is commented out — prefer engine `-pidfile` on direct launches. |
| `-autoupdate` | no | Run `./steam -command update …` before each start; forces restart-on. |
| `-steamerr` | no | Exit if Steam update fails or `steam` binary missing. |
| `-steamuser` / `-steampass` | yes | Credentials for Steam update (password requires username). |
| `-ignoresigint` | no | Ctrl+C does not quit the **wrapper** (empty SIGINT action). |
| `-notrap` | no | Do not install SIGINT trap on the wrapper. Help text about “lock files” is stale on this script revision. |
| `-help` | no | Print syntax and exit (code 2). |

**Hang note:** `-norestart` only changes post-**exit** behavior. A frozen process never exits, so the wrapper never wakes. Use an external watchdog or spawn the ELF under `timeout`/`systemd`/expect (as CI does).

---

## 2. Dedicated host — `bin/dedicated_*.so` (D)

| Flag | Value | DS? | Description |
|---|---|---|---|
| `-game <dir>` | yes | yes | Game/mod directory containing `gameinfo.txt`. |
| `-defaultgamedir <name>` | yes | rare | Fallback mod name if `-game` missing (stock default path uses `hl2`). |
| `-textmode` | no | yes | Prefer text console path (no VGUI dedicated UI). |
| `-condebug` | no | yes | Mirror console output to `cstrike/console.log`. |
| `-conclearlog` | no | yes | Truncate `console.log` before appending (with `-condebug`). |
| `-basedir <path>` | yes | rare | Override computed base directory for the install. |
| `-noasync` | no | rare | Disable async filesystem jobs. |
| `-fs_log` | no | tool | Start filesystem “copy missing files” logging helper. |
| `-fs_target <dir>` | yes | tool | Target root for FS log copy scripts. |
| `-fs_logbins` | no | tool | Emit bin-copy batch fragments on FS shutdown. |
| `-vcrrecord <file>` | yes | tool | Record VCR input stream. |
| `-vcrplayback <file>` | yes | tool | Replay VCR input (`can't open` errors if missing). |
| `-usegh` | no | no | Load `ghostinj.dll` (Windows GhostInject tooling). |
| `-vproject <path>` | yes | tool | Set VProject for filesystem/gameinfo resolution. |
| `-NoVConfig` | no | tool | Skip interactive vconfig when gameinfo lookup fails. |
| `-tempcontent` | no | tool | Add `<mod>_tempcontent` search path. |
| `-noassert` | no | rare | Soften/suppress assert dialog path in dedicated spew. |

---

## 3. Engine — network & identity (E)

| Flag | Value | DS? | Description |
|---|---|---|---|
| `-ip <addr>` | yes | yes | Bind address for the game socket (`NET_Init`). Use `0.0.0.0` for all interfaces. |
| `-port <n>` | yes | yes | Game listen port (default 27015). |
| `+port <n>` | yes | yes | Same as `-port` (also accepted by `NET_Init`). |
| `-steamport <n>` | yes | rare | Extra Steam-related port used during `CSteam3::Init`. |
| `-noip` | no | rare | Disable IP networking. |
| `-nodns` | no | rare | Skip DNS in net init. |
| `-usetcp` | no | rare | Enable TCP listen path alongside UDP. |
| `-reuse` | no | yes | Allow address reuse on sockets (`NET_OpenSocket`). |
| `-usercon` | no | yes | Enable remote/user console path (`NET_Config`). |
| `-nohltv` | no | yes | Disable SourceTV / HLTV. |
| `-tvmasteronly` | no | rare | SourceTV master-only mode (`CHLTVServer::Init`). |
| `-insecure` | no | yes | Start without VAC (`CSteam3::Init`). |
| `-nomaster` | no | yes | Do not talk to Valve master servers. |
| `-autoupdate` | no | rare | If master requests restart for update, honor that path (`CheckMasterServerRequestRestart`). Distinct from wrapper `-autoupdate`. |
| `-localcser` | no | yes | Use local CSER / stats upload endpoint (`CUploadGameStats`). Typical on non-Steam/CSS v34 hosting. |
| `-gamestats` | no | rare | Enable game-stats upload path. |
| `-maxplayers <n>` | yes | yes | Hard slot cap at `CGameServer::InitMaxClients` (also clamped by game limits). |
| `-pidfile <path>` | yes | yes | Write the **engine** PID (panel supervisors use this). |
| `-nogamedll` | no | tool | Skip loading the game DLL (engine-only tooling). |

---

## 4. Engine — developer / phone-home (E)

| Flag | Value | DS? | Description |
|---|---|---|---|
| `-dev` | no | rare | In `Host_Init`: set `developer 1` and `sv_cheats 1`. Also marks build **internal** for phone-home. Presence-only — `-dev 1` is the same as `-dev` (the `1` is unused argv). **There is no `-dev2`.** |
| `-allowdebug` | no | rare | Same cheats/developer effect as `-dev` **unless** `-nodev` is also set. |
| `-nodev` | no | rare | Blocks the `-allowdebug` → developer/cheats path. |
| `-phonehome` | no | no | Force phone-home init path in `Host_Init`. |
| `-internalbuild` | no | no | Treat build as internal (`CPhoneHome::IsExternalBuild`). |
| `-publicbuild` | no | no | Force “external/public” classification for phone-home. |
| `-bi <id>` | yes | no | Phone-home **build identifier** override (`CPhoneHome::Init` reads next parm; stock cookie string nearby is `VLV_INTERNAL`). |

Logic (matches Source SDK `Host_Init`):

```text
if (-dev) OR (-allowdebug AND NOT -nodev):
    sv_cheats = 1
    developer = 1
```

---

## 5. Engine — logging, precache, misc server (E)

| Flag | Value | DS? | Description |
|---|---|---|---|
| `-flushlog` | no | rare | Flush server log more aggressively (`CLog`). |
| `-uselogdir` | no | rare | Prefer `logs/<map>/…` layout (`COM_SetupLogDir`). |
| `-allowstalezip` | no | rare | Allow spawning with stale/mismatched zip/BSP consistency path. |
| `-preload` | no | rare | Force model preload behavior in `PrecacheModel`. |
| `-nopreload` | no | rare | Disable preload. |
| `-nopreloadmodels` | no | rare | Disable model preload specifically. |
| `-random_invariant` | no | tool | Deterministic RNG seeding during `Sys_InitGame`. |
| `-noassert` | no | rare | Soften asserts in engine spew path. |
| `-surfcachesize <n>` | yes | rare | Override surface cache size. |
| `-defaultgamedir` | yes | rare | Default mod string when resolving paths. |
| `-game` | yes | yes | Mod directory (also resolved in engine FS helpers). |
| `-vproject` / `-NoVConfig` / `-tempcontent` | varies | tool | Filesystem / VProject helpers (same family as dedicated). |

---

## 6. Engine — mapreslist / devshots / test tooling (E)

Valve content pipeline flags; rarely needed on a live DS.

| Flag | Value | Description |
|---|---|---|
| `-makereslists` | no | Generate reslists (`MapReslistGenerator`). |
| `-usereslistfile <file>` | yes | Map list file instead of scanning `maps/*.bsp`. |
| `-startmap <map>` | yes | Resume reslist/devshot generation at map (after crash). |
| `-forever` | no | Loop map list when finished (`[ -forever ] -- when you get to the end of the maplist, start over`). |
| `-rebuildaudio` | no | Rebuild audio while generating reslists. |
| `-trackdeletions` | no | Emit `deletions.bat` for deleted content tracking. |
| `-makedevshots` | no | Automated map screenshot pass. |
| `-usedevshotsfile <file>` | yes | Map list for devshots (default `maps/*.bsp`). |
| `-testscript <file>` | yes | Run a `.vtest`-style test script from host frame loop. |
| `-spewsentences` | no | Dump sentence wave references while building reslists. |
| `-dti` | no | DataTable instrumentation (`SendTable_Init`). |
| `-heapcheck` | no | Heap check around host hunk init. |
| `-dumpvidmemstats` | no | Video memory stats path during map validation. |
| `-buildcubemaps` | no | Cubemap build / occlusion tooling. |
| `-requirecubemaps` | no | Require cubemap samples when loading maps. |

Embedded help fragment for devshots also documents:  
`[ -condebug ] -- prepend console.log entries with mapname or engine if not in a map` (engine-side note used by mapreslist tooling; console logging itself is owned by dedicated `-condebug`).

---

## 7. Engine — video / window (E) — usually inert on dedicated

Still present and xref’d from `InitMaterialSystemConfig` / `Shader_Connect`. On a pure dedicated box they typically do nothing useful.

| Flag | Value | Description |
|---|---|---|
| `-sw` / `-window` / `-windowed` / `-startwindowed` | no | Windowed mode. |
| `-full` / `-fullscreen` | no | Fullscreen. |
| `-w` / `-width <n>` | yes | Backbuffer width (`-w` is the short alias). |
| `-height <n>` | yes | Backbuffer height. (`-h` string exists in the binary but has **no** cmdline xref here — use `-height`.) |
| `-resizing` | no | Allow resize. |
| `-safe` | no | Safe video defaults. |
| `-dxlevel <n>` | yes | Force DX level (e.g. `80` / `90` style values). |
| `-mat_vsync` / `-mat_antialias` / `-mat_aaquality` | varies | Material system video overrides. |
| `-adapter <n>` | yes | GPU adapter index. |
| `-ref` | no | Reference rasterizer path. |

---

## 8. Game DLL — `cstrike/bin/server_*.so` (G)

| Flag | Value | DS? | Description |
|---|---|---|---|
| `-tickrate <n>` | yes | yes | If `n > 10`, tick interval = `1/n`. Else keep default float ≈ **0.03** → **~33.33 Hz**. Modern Steam CSS removed this for `CSTRIKE_DLL`; **v34 still honors it**. |
| `-nobots` | no | yes | Prevent bot creation (`CCSBotManager`). |
| `-game` | yes | rare | Used in level-init / chapter title paths. |
| `-makedevshots` / `-makereslists` | no | tool | Cooperate with engine tooling (cameras, soundemitter flush, etc.). |

---

## 9. tier0 / steamclient (T / S)

| Flag | Layer | Value | Description |
|---|---|---|---|
| `-noassert` | T | no | Skip new assert dialog (`DoNewAssertDialog`). |
| `-debugbreak` | T | no | Break into debugger on assert (string present; weak xref in this build). |
| `-mpi_worker` | T/S | no | MPI worker mode. |
| `-debug_steamapi` | S | no | Extra Steam API debug spew. |
| `-single_core` | S | no | “Force Steam to run on your primary CPU only.” |

eSTEAM adds **no** additional Valve game flags beyond stock; auth libraries may still expose the steamclient flags above.

BufferFix `srcds_patch`: **273** byte diffs in `engine_i686.so`, **zero** new cmdline strings (memcpy→memmove only).

---

## 10. Verified `+` argv companions

| Token | Layer | Description |
|---|---|---|
| `+port <n>` | E | Alternate spelling for `-port` in `NET_Init`. |
| `+map <name>` | E | Queues map load; also consulted by mapreslist builders (`BuildGeneralMapList`). |

Other `+cvar` / `+cmd` forms work through the normal ConVar/command buffer (not each name needs an ELF cmdline string). Hosting classics that appear as **ConVars** (confirmed as strings, set via `+`):

| Example | Where stored | Notes |
|---|---|---|
| `+sv_pure 0` | engine ConVar `sv_pure` | Pure server mode. |
| `+tv_port 27020` | engine ConVar `tv_port` | SourceTV port (enable TV separately, e.g. `tv_enable`). |
| `+mp_dynamicpricing 0` | game ConVar | Avoids price-blob download errors on v34. |
| `+maxplayers` | — | **No** `+maxplayers` NUL string/xref in this engine build — use **`-maxplayers`**. |
| `+ip` / `-sv_pure` | — | Not present as cmdline tokens here. |

---

## 11. Explicitly absent on CSS v34 public binaries

Searched stock + eSTEAM + `srcds_patch` + myarena SM/MM zip — **no** consumer:

| Token | Notes |
|---|---|
| `-dumplongticks` | Later Source / wiki; not in this tree |
| `-dev2` | Does not exist |
| `-console` | Windows client/dedicated GUI switch; no Linux ELF consumer |
| `-debug` (engine) | Wrapper-only; engine has no `-debug` |
| `-norestart` / `-notrap` (engine) | Wrapper-only |
| `-nominidumps` / `-nobreakpad` / `-nocrashdialog` | Newer branches |
| `-tvdisable` / `-pingboost` / `-threads` / `-fork` | Not in these ELFs |
| `-reader` `-pcmdscpmrc` `-sfwb` `-wsb` `-vcforce` `-sesb` | MyArena panel proprietary / no-op on stock |

---

## 12. Full verified inventory (checklist)

**Wrapper (W):**  
`-autoupdate` `-binary` `-debug` `-debuglog` `-game` `-gdb` `-help` `-ignoresigint` `-norestart` `-notrap` `-pidfile` `-steamerr` `-steampass` `-steamuser` `-timeout`

**Dedicated (D):**  
`-NoVConfig` `-basedir` `-conclearlog` `-condebug` `-defaultgamedir` `-fs_log` `-fs_logbins` `-fs_target` `-game` `-noassert` `-noasync` `-tempcontent` `-textmode` `-usegh` `-vcrplayback` `-vcrrecord` `-vproject`

**Engine (E):**  
`+map` `+port` `-NoVConfig` `-adapter` `-allowdebug` `-allowstalezip` `-autoupdate` `-bi` `-buildcubemaps` `-defaultgamedir` `-dev` `-dti` `-dumpvidmemstats` `-dxlevel` `-flushlog` `-forever` `-full` `-fullscreen` `-game` `-gamestats` `-heapcheck` `-height` `-insecure` `-internalbuild` `-ip` `-localcser` `-makedevshots` `-makereslists` `-mat_aaquality` `-mat_antialias` `-mat_vsync` `-maxplayers` `-noassert` `-nodev` `-nodns` `-nogamedll` `-nohltv` `-noip` `-nomaster` `-nopreload` `-nopreloadmodels` `-phonehome` `-pidfile` `-port` `-preload` `-publicbuild` `-random_invariant` `-rebuildaudio` `-ref` `-requirecubemaps` `-resizing` `-reuse` `-safe` `-spewsentences` `-startmap` `-startwindowed` `-steamport` `-surfcachesize` `-sw` `-tempcontent` `-testscript` `-trackdeletions` `-tvmasteronly` `-usedevshotsfile` `-uselogdir` `-usercon` `-usereslistfile` `-usetcp` `-vproject` `-w` `-width` `-window` `-windowed`

**Game (G):**  
`-game` `-makedevshots` `-makereslists` `-nobots` `-tickrate`

**tier0 / steamclient (T/S):**  
`-debug_steamapi` `-debugbreak` `-mpi_worker` `-noassert` `-single_core`

---

## 13. Practical recipes

```bash
# Production-ish v34 (direct binary + external watchdog recommended)
./srcds_i686 -game cstrike -ip 0.0.0.0 -port 27015 -tickrate 66 \
  -maxplayers 32 -condebug -usercon -insecure -localcser -nomaster \
  -pidfile ../game.pid \
  +map de_dust2 +sv_pure 0 +mp_dynamicpricing 0

# Wrapper auto-restart on crash/exit only (not hangs)
./srcds_run -game cstrike -ip 0.0.0.0 -port 27015 -tickrate 66 \
  -timeout 15 -nomaster -localcser +map de_dust2

# Crash forensics when the process exits non-zero
./srcds_run -game cstrike -debug -debuglog /tmp/css-debug.log -timeout 15 ...

# Dev spew
./srcds_i686 -game cstrike -dev -condebug +map de_dust2
```

---

## 14. Case study: MyArena cmdline

```bash
./srcds_i686 -game cstrike -ip 0.0.0.0 -port 27015 +map de_dust2_unlimited \
  -maxplayers 62 -tickrate 66 -console -condebug -norestart -usercon \
  -reader 512 -insecure +sv_pure 0 +tv_port 27020 +mp_dynamicpricing 0 \
  -localcser -nomaster -debug -pcmdscpmrc -sfwb -wsb 2 -vcforce -sesb \
  -pidfile ../game.pid
```

| Keep on stock v34 | Drop / no-op on stock |
|---|---|
| `-game` `-ip` `-port` `-maxplayers` `-tickrate` `-condebug` `-usercon` `-insecure` `-localcser` `-nomaster` `-pidfile` | `-console` `-norestart` `-debug` |
| `+map` `+sv_pure` `+tv_port` `+mp_dynamicpricing` | `-reader` `-pcmdscpmrc` `-sfwb` `-wsb` `-vcforce` `-sesb` |

Proprietary tokens are absent from stock / eSTEAM / BufferFix / public myarena SM+MM packages — panel-private binary or `LD_PRELOAD`, or dead weight.

Related addons often co-installed by panels (not argv): Metamod `dosattackfix`, `nativetools`, SM **ProcessCmds** (`processcmds.ext`, GoDtm666 / MyArena).

---

## 15. CI note

Smoke tests spawn `./srcds_i686` via expect (`testing/scripts/console-probe.exp`), not `srcds_run`, so wrapper restart/gdb cannot mask hangs.
