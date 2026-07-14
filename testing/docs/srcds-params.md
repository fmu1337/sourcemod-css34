# CS:S v34 `srcds_run` / `srcds` launch parameters (string + DWARF audit)

Validated against stock binaries from `srcds_css34_l_a.zip` (dated 2010-03-21):

| File | Role | MD5 |
|---|---|---|
| `srcds_run` | shell wrapper (restart / gdb / steam update) | `9ef9e859ec94776811de6c1a0020df5c` |
| `srcds_i686` | thin ELF loader → `bin/dedicated_i686.so` | `5ea1005802c49456692c9aa0141e1d91` |
| `bin/dedicated_i686.so` | dedicated app-system host | `afe97b94b5805a984efb1c77cd3a3c06` |
| `bin/engine_i686.so` | engine | `a0a8ea1f14c3fafd4a26eca033851817` |
| `cstrike/bin/server_i486.so` | game DLL | `8349c21323a4e63e1b169dc06e1d7036` |

Method: `strings` + null-terminated flag scrape, then `addr2line`/disasm xrefs on unstripped DWARF. Cross-checked against Source SDK `Host_Init` / `CServerGameDLL::GetTickInterval` / `CPhoneHome::IsExternalBuild`.

Reproduce: `testing/scripts/extract-srcds-params.sh` (uses `.ci-cache/srcds_css34_l_a.zip`).

## Layering (what consumes which flags)

```text
./srcds_run [wrapper flags…] [everything else…]
        │
        ├─ consumes: -game -debug -norestart -pidfile -binary -timeout
        │            -gdb -debuglog -autoupdate -steamerr -ignoresigint
        │            -notrap -steamuser -steampass -help
        │
        └─ passes ALL argv (including its own) to:
              ./srcds_{i486|i686|amd} …   (CPU auto-detect, or -binary / $FORCE)
                    │
                    └─ dlopen bin/dedicated_*.so → engine_*.so → cstrike/bin/server_*.so
```

`srcds_i686` itself has **no** game flags — only loads dedicated. Unknown tokens are generally ignored (`FindParm` / `CheckParm` miss → no-op).

---

## `srcds_run` only (not the engine)

Source of truth: the shell script itself (Copyright Valve 2004). Help text via `./srcds_run -help`.

| Flag | Default | Behavior |
|---|---|---|
| `-game <dir>` | `cstrike` | Must be an existing directory |
| `-norestart` | restart **on** | Clears `RESTART`; after exit, do not loop |
| `-timeout <sec>` | `10` | Sleep between restart attempts |
| `-debug` | off | Enable core dumps (`ulimit -c`), after non-zero exit run `gdb` batch (`bt`, `info locals`, …) into `-debuglog` |
| `-debuglog <file>` | `debug.log` | gdb output target |
| `-gdb <path>` | `gdb` | Debugger binary |
| `-pidfile <file>` | auto `hlds.$$.pid` when `-debug` | Noted by script; **pidfile is not appended to the engine cmdline** in this CSS build (block is commented out) |
| `-binary <path>` | auto-detect | Skip CPU detect; use this ELF |
| `-autoupdate` | off | Run `./steam -command update …` before each start; also **forces** restart on |
| `-steamerr` | off | Quit if steam update / binary missing |
| `-steamuser` / `-steampass` | — | Steam update credentials (both required if password set) |
| `-ignoresigint` | quit on INT | Empty SIGINT trap action (Ctrl+C does not quit the **wrapper**) |
| `-notrap` | trap on | Skip `trap … 2` entirely |

### Why `-norestart` “does nothing” on a hang

`srcds_run` only reacts to **process exit**:

```sh
# RESTART set (default):
$HL_CMD
retval=$?
# retval==0 → break; else sleep $TIMEOUT and loop

# -norestart:
exec $HL_CMD   # or run once if -debug
```

If the server **hard-hangs** (deadlock, stuck in syscall, 100% CPU spin with no exit), there is **no exit code**. The wrapper never wakes up. `-norestart` does not add a watchdog, heartbeat, or timeout.

What actually helps hangs:

- external supervisor (`systemd` with watchdog / `TimeoutStopSec` + kill, `tmux`+manual, `docker --stop-timeout`, custom loop on `status`/`rcon` probe)
- CI approach in this repo: spawn **engine binary directly** via `expect` (`testing/scripts/console-probe.exp`), not `srcds_run`

### `-notrap` reality on CSS v34

Help text says it prevents “automatic removal of old lock files”. In **this** script version:

- with trap (default): SIGINT runs `quit 0` (or nothing if `-ignoresigint`)
- `-notrap`: no SIGINT handler on the wrapper; INT goes to the foreground child
- `quit()` still does `trap - 2; kill -2 $$` on scripted shutdown

There is **no** lock-file cleanup path wired to `-notrap` in this build. Treat it as “don’t steal Ctrl+C”.

### `-debug` (wrapper) ≠ engine developer mode

Wrapper `-debug` ≠ `-dev`. The token `-debug` is also forwarded to the engine argv, but **`engine_i686.so` has no `-debug` string** — so the engine ignores it. GDB/core handling is wrapper-only.

---

## Engine: `-dev` / `-allowdebug` / `-nodev` (no `-dev2`)

Implemented in `Host_Init` (`engine_i686.so`), same logic as Source SDK:

```cpp
if ( CommandLine()->FindParm( "-dev" )
  || ( CommandLine()->FindParm( "-allowdebug" )
       && !CommandLine()->FindParm( "-nodev" ) ) )
{
    sv_cheats.SetValue( 1 );
    developer.SetValue( 1 );
}
```

Implications:

| Invocation | Result |
|---|---|
| `-dev` | `developer 1` + `sv_cheats 1` |
| `-dev 1` | Same as `-dev`. `FindParm` only checks **presence** of token `-dev`; the following `1` is an unused argv word (not `ParmValue`) |
| `-dev2` | **Does not exist** in CSS v34 (no string, no xref) |
| `-allowdebug` without `-nodev` | Same as `-dev` |
| `-allowdebug -nodev` | Does **not** force developer/cheats |
| `+developer 1` / `developer 1` | ConVar only — not identical to `-dev` for phone-home / “external build” checks |

### Side effect: phone-home / “external build”

`CPhoneHome::IsExternalBuild()` treats a build as **internal** if `-dev` **or** `-internalbuild` is present (unless `-publicbuild`). So `-dev` also changes telemetry classification, not just console verbosity.

---

## `-dumplongticks` — **absent** on CSS v34

Searched `srcds_*`, `dedicated`, `engine`, `tier0`, `server`: **no** `dumplongticks` / `longtick` string.

Later Source branches (Valve wiki / Orange Box+ dedicated docs) document `-dumplongticks` as “generate minidumps on long server frames”. That is **not** in this 2010 CSS dedicated tree. Closest related bits here: `LinuxMiniDump` symbol exists, but nothing wired to a long-tick cmd/flag by that name.

Do not expect `-dumplongticks` to do anything on v34.

---

## `-tickrate` — in **game DLL**, not engine

`CServerGameDLL::GetTickInterval()` in `server_i486.so`:

- default interval float `0x3cf5c28f` ≈ **0.03** → **~33.33 Hz** (pre-Valve CSS 66 lock-in)
- if `FindParm("-tickrate")` and `ParmValue` **> 10** → interval = `1.0 / tickrate`
- otherwise keep default

Modern Steam CS:S compiled `-tickrate` out for `CSTRIKE_DLL` (SDK2013 comment: “server ops are abusing it”). **v34 still has it** — so `start.sh`’s `-tickrate 66` is meaningful here.

Not present in `engine_i686.so` strings; changing tickrate requires game DLL that still honors the flag.

---

## Useful engine / dedicated / server flags present in this build

### High-value for dedicated ops

| Flag | Where | Notes |
|---|---|---|
| `-game` | eng / ded | Mod directory |
| `-ip` / `-port` / `-steamport` | eng | Network bind / advertise |
| `-noip` / `-nodns` | eng | Disable net bits |
| `-nomaster` | eng | Skip master server (`CMaster` / `UpdateMasterServer`) |
| `-localcser` | eng | Local CSER / game stats upload path |
| `-insecure` | eng | Skip VAC path (`CSteam3::Init`) |
| `-nohltv` / `-tvmasteronly` | eng | SourceTV |
| `-maxplayers` | eng | Slot cap at launch |
| `-condebug` / `-conclearlog` | **dedicated** | Console → `console.log` (smoke uses this) |
| `-textmode` | dedicated | Text console path |
| `-pidfile` | eng | Engine-side pid file (separate from wrapper’s unused path) |
| `-nobots` | **server** | Disable bots |
| `-tickrate` | **server** | See above |
| `-reuse` | eng | `SO_REUSEADDR`-style reuse |
| `-usercon` | eng | Present as string (RCON-related in later titles; verify behavior if needed) |
| `-forever` | eng | Mapreslist loop (`CMapReslistGenerator`) |

### Dev / tooling (often irrelevant on production DS)

`-allowdebug`, `-nodev`, `-dev`, `-makedevshots`, `-makereslists`, `-testscript`, `-profile`, `-heapcheck`, `-noassert` (tier0/engine), `-debugbreak` (tier0), `-vcrrecord`/`-vcrplayback`, `-fs_log*`, `-basedir`, `-vproject`, `-NoVConfig`, client-ish `-window(ed)` / `-width` / `-height` / `-dxlevel` / mat_* flags (mostly inert on pure dedicated).

### Explicitly **not** found in CSS v34 binaries

`-dumplongticks`, `-dev2`, `-debug` (engine), `-norestart` / `-notrap` (engine — wrapper-only), `-tvdisable`, `-console` (Windows-oriented; Linux dedicated uses text console path), `-nocrashdialog`, `-nobreakpad`, `-nominidumps` (common later/SteamPipe).

---

## Practical recipes

```bash
# Normal hosting (auto-restart on crash/exit≠0 only — NOT hangs)
./srcds_run -game cstrike -ip 0.0.0.0 -port 27015 -tickrate 66 \
  -nomaster -localcser +map de_dust2 +maxplayers 32

# One-shot / under external watchdog (preferred if process can freeze)
./srcds_i686 -game cstrike -ip 0.0.0.0 -port 27015 -tickrate 66 \
  -nomaster -localcser -norestart   # -norestart is ignored by binary; use for clarity in docs only
# better: do not use srcds_run at all

# Crash forensics when the process *exits* non-zero
./srcds_run -game cstrike -debug -debuglog /tmp/css-debug.log -timeout 15 ...

# Verbose engine spew + cheats (dev box)
./srcds_i686 -game cstrike -dev -condebug ...
```

---

## CI note

Smoke tests intentionally bypass `srcds_run` (`console-probe.exp` spawns `./srcds_i686` directly) so wrapper restart/gdb logic cannot mask hangs or double-start under timeout.

---

## Case study: MyArena-style `srcds_i686` cmdline

Observed host launch (direct binary, **not** `srcds_run`):

```bash
./srcds_i686 -game cstrike -ip 0.0.0.0 -port 27015 +map de_dust2_unlimited \
  -maxplayers 62 -tickrate 66 -console -condebug -norestart -usercon \
  -reader 512 -insecure +sv_pure 0 +tv_port 27020 +mp_dynamicpricing 0 \
  -localcser -nomaster -debug -pcmdscpmrc -sfwb -wsb 2 -vcforce -sesb \
  -pidfile ../game.pid
```

Corpus for this pass (in addition to stock):

| Layer | Source | Same flags as stock? |
|---|---|---|
| eSTEAM `engine` / `dedicated` | `srcds_css34_l_eSTEAMATiON.zip` | Yes for Valve flags; auth libs add `-debug_steamapi` only |
| `srcds_patch` (`engine`/`server`/`steamclient`) | bruno_args BufferFix rar | **273** byte diffs in `engine_i686.so`, **zero** new cmdline strings (memcpy→memmove only) |
| myarena MM+SM 6522 zip | bitbucket `danyas_dl` bundle | No hits for proprietary tokens below |

### Token-by-token

| Token | Layer that owns it | Effect on **this** launch path (`./srcds_i686`) |
|---|---|---|
| `-game cstrike` | dedicated / engine | Required mod dir |
| `-ip 0.0.0.0` | engine (`NET_Init`) | Bind all interfaces |
| `-port 27015` | engine (`NET_Init`) | Game port |
| `+map …` | engine (`+` → Cbuf) | Start map |
| `-maxplayers 62` | engine | Slot cap at launch |
| `-tickrate 66` | **server** `GetTickInterval` | interval = `1/66` (v34 still honors this) |
| `-console` | **nowhere** in Linux ELFs | No-op (Windows `srcds.exe` GUI switch; not a NUL-terminated string in dedicated/engine/server) |
| `-condebug` | **dedicated** `CTextConsoleUnix::Init` | Write `cstrike/console.log` |
| `-norestart` | **`srcds_run` only** | **No-op** — binary launch ignores it (and would not help hangs anyway) |
| `-usercon` | engine (`NET_Config`) | Present / checked; enables remote console path on builds that use it |
| `-reader 512` | **not found** in any public layer | See proprietary block below |
| `-insecure` | engine (`CSteam3::Init`) | Skip VAC |
| `+sv_pure 0` | engine convar `sv_pure` | Pure mode off |
| `+tv_port 27020` | engine convar `tv_port` | SourceTV port (still need `tv_enable 1` separately if TV is used) |
| `+mp_dynamicpricing 0` | **server** convar | Avoids “Incorrect price blob / couldn't download price list” spam when left at 1 |
| `-localcser` | engine | Local CSER / stats path |
| `-nomaster` | engine | No Valve master advertise |
| `-debug` | **`srcds_run` only** (engine has no `-debug`) | **No-op** on direct `srcds_i686`. Hits like `-debug_steamapi` / `suid-debug` in steam libs are unrelated substrings |
| `-pcmdscpmrc` | **not found** | Proprietary — name echoes MyArena **ProcessCmds** (`GoDtm666`), but the public SM bundle has no such argv string |
| `-sfwb` | **not found** | Proprietary / no-op on stock |
| `-wsb 2` | **not found** (byte `wsb` in eSTEAM SCI is unrelated garbage) | Proprietary / no-op on stock |
| `-vcforce` | **not found** | Proprietary / no-op on stock |
| `-sesb` | **not found** | Proprietary / no-op on stock |
| `-pidfile ../game.pid` | engine (`Sys_Init`) | Writes PID for the **panel** supervisor (this is the engine-side pidfile, unlike the unused wrapper path) |

### Proprietary cluster (`-reader`, `-pcmdscpmrc`, `-sfwb`, `-wsb`, `-vcforce`, `-sesb`)

Absent from every public binary we scanned:

- stock `srcds_*` / `dedicated` / `engine` / `server` / `tier0` / `vstdlib` / `steamclient`
- eSTEAM overlay (`libeST_*`, `valve_api`, patched steam_api)
- BufferFix `srcds_patch`
- myarena SourceMod/Metamod package (all `.so`)

So on a **stock / rom4s / our CI tree**, those six tokens are ignored argv noise. On MyArena game nodes they may still do something if the host injects:

- a **custom** `srcds_i686` / `engine_*.so` not published in the community zips, or
- an `LD_PRELOAD` / panel helper that wraps `main`/`CommandLine`, or
- a license/feature cookie consumed only by private ProcessCmds/host tooling

Do **not** treat them as documented Valve flags. If reproducing a MyArena bug outside their panel, drop them first and retest.

### What is actually useful to copy from that line

Keep for vanilla v34:

```text
-game cstrike -ip 0.0.0.0 -port 27015 -maxplayers N -tickrate 66
-condebug -usercon -insecure -localcser -nomaster -pidfile <path>
+map <map> +sv_pure 0 +tv_port <port> +mp_dynamicpricing 0
```

Drop or replace:

| Drop | Why |
|---|---|
| `-console` | No Linux consumer |
| `-norestart` / `-debug` | Only `srcds_run`; meaningless on `srcds_i686` |
| `-reader` / `-pcmdscpmrc` / `-sfwb` / `-wsb` / `-vcforce` / `-sesb` | Not in public game tree |

Related panel plugins sometimes seen next to such launches (not cmdline flags): Metamod `addons/daf/bin/dosattackfix`, `nativetools`, SM extension **ProcessCmds** (`processcmds.ext`) by GoDtm666 / MyArena — those load via `addons/`, not via argv.
