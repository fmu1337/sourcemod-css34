# Server smoke testing (CS:S v34)

Scripts and workflows that boot a Counter-Strike: Source **v34** dedicated server with **our** Metamod:Source + SourceMod packages on a matrix of Linux distributions.

## Distro matrix

| Job | Images | Lines |
|---|---|---|
| `build-linux` (+ "ABI / export checks") | `legacy-build.sh` in `debian:11` on ubuntu-22.04 | all three active lines |
| `test-built-debian` | `debian:11` | all three active lines |
| `test-built-debian` | `debian:latest` | `sm13-latest` |
| `test-built-rhel` | `rockylinux:9` | `sm13-latest` |
| `test-built-smoke` | ubuntu-22.04 host | `sm13-latest` |
| `test-built-botplay-matrix` | `debian:11` | all three active lines |

CI installs **only** the in-tree `packages/mmsource-*-css34-linux.tar.gz` and `packages/sourcemod-*-css34-linux.tar.gz` from `build-linux` (handed to later jobs via Actions cache, not artifacts). rom4s reference drops are not used in this workflow.

Packages come from `legacy-build.sh` (`debian:11`), so the smoke matrix starts at Debian 11+ / Rocky 9.

When the CI server tree is trimmed to a single map (`de_dust2`), `testing/scripts/trim-server-maps.sh` also rewrites `mapcycle.txt` so the engine does not spam `Map_IsValid: No such map` for deleted BSPs.

## Smoke logging

| Variable | Default | Effect |
|---|---|---|
| `SMOKE_CONDEBUG=1` | on | srcds `-condebug` → `cstrike/console.log` |
| `SMOKE_VERBOSE=1` | off in local runs | expect `log_user 1`, `+log on +sv_logfile 1` |

On failure, smoke prints tails of `smoke.log`, `console-probe.log`, `cstrike/console.log`, and SourceMod `L*.log`. CI uploads those logs as artifacts **only on failure** with seven-day retention. Logs remain available after the run finishes; scheduled cleanup also preserves them for seven days.

## What the smoke test checks

1. Game DLL loads (`Counter-Strike: Source`)
2. Map / dedicated server config starts (`Mapchange to …` in console)
3. `sm version` — expected MM/SM versions
4. `sm exts list` — prints full list; fails on `<FAILED>`; requires BinTools + SDK Tools + CS Tools + **SDK Hooks**
5. `sm plugins list` — every enabled `.smx` listed as Running (not `<Failed>`)
6. SourceMod session log (`addons/sourcemod/logs/L*.log`) — no error markers
7. **sdkhooks.games** `OnTakeDamage` linux offset **61** (css34)
8. Every SDKTools / SDKHooks vtable offset in the installed gamedata matches the `CCSPlayer` / `CWeaponCSBase` vtables of the v34 `server_i486.so` (`check-css34-vtables.py`; needs `python3` + `c++filt`, otherwise SKIP — the `debian` / `rockylinux` smoke containers have neither, so in CI it only runs in `test-built-smoke` on the host runner)
9. No segfault; not flooded with `Unknown command` (buffer bug signature)

The **botplay-stress** matrix (`test-built-botplay-matrix`) is the largest CI gate: SMAC + 8 bots + map rotation + `css34_botplay_stress.smx` SDKHook_OnTakeDamage probe (requires OnTakeDamage hits in SM logs) + `css34_cstrike_forward_probe.smx` (requires cstrike TerminateRound / buy / price detour hits and a `GetPlayerWeaponSlot` → `CS_DropWeapon` → `GivePlayerItem` round, `css34_cs_probe_mode 8` in `botplay-stress.cfg`)) + `css34_dhooks_probe.smx` (where dhooks.ext ships: DHooks virtual hooks on `CCSPlayer::OnTakeDamage`, `CBasePlayer::EyePosition` (Vector return, override) and `CCSPlayer::PlayStepSound` (float param, `MRES_ChangedHandled` recall), and detours on `CCSPlayer::RoundRespawn` and `CWeaponCSBase::GetMaxSpeed` (float return, override) must install, fire and return sane values; probe gamedata lives in `testing/plugins/gamedata/`; lines without DHooks log `available=0` and are skipped). Runs for all `CSS34_LINE` builds on every `master` push.

## `srcds_run` / engine launch flags

String-audited notes for CSS v34 (`-dev`, `-debug`, `-norestart`, `-tickrate`, dedicated/engine layers, MyArena cross-checks): [docs/srcds-params.md](docs/srcds-params.md). Re-scrape stock binaries with `testing/scripts/extract-srcds-params.sh`.

## Buffer / modern-OS fixes

See [docs/bufferfix.md](docs/bufferfix.md). CI defaults to:

- minimal `cstrike/cfg/valve.rc`
- **srcds_patch** — ELF rewrite memcpy→memmove (`patch-srcds-bufferfix.py`)

## Botplay baseline (rom4s + SMAC)

`test-rom4s-botplay` boots the css34 server with **rom4s** Metamod 1.10.6 + SourceMod 6572, compiles [smac_v34](https://github.com/fmu1337/smac_v34), spawns 4 bots (`botplay-server.cfg`), records **600s** by default, then parses `cstrike/console.log` for `round_start`, `round_end`, and kills.

`test-built-botplay-matrix` runs the same session with the **built** MM + SM packages of every line and compares against `testing/botplay/rom4s-baseline.json` for information only. Event-count differences do not fail CI; the botplay crash, extension and API/ABI checks remain required. The redundant single-line job has been removed.

`test-release-botplay` downloads published GitHub Release packages and runs the same stress session for:

| Line | Tag | Packages |
|------|-----|----------|
| sm12 | `1.12.0.7253-mm1.12.0` | SM 1.12.0.7253 + MM 1.12.0-dev (git1226) |
| sm13 | `1.13.0.7472-mm1.12.0` | SM 1.13.0.7472 + MM 1.12.0-dev (git1226) |

SM 1.12+ `geoip.ext` needs a GeoIP2 `*.mmdb` under `configs/geoip/`. Our packages ship `GeoLite2-Country.mmdb` (`prepare-package.sh`, enforced by `check-package.sh`); `botplay-test.sh` also installs one via `install-geoip2-db.sh` when it is missing (e.g. for rom4s packages).

**Stress profile (default):** `botplay-stress.cfg` execs `botplay-server.cfg` (fast 1‑minute rounds) then raises `bot_quota` to 8. Plugin `css34_botplay_stress.smx` rotates maps every 3 rounds (`de_dust2` → `de_inferno` → `de_nuke`) and logs sdkhooks/sdktools ABI probe results each round.

**When they run:** `test-built-botplay-matrix` (`debian:11`, 300 s per line) runs on every push / PR. `test-rom4s-botplay` and `test-release-botplay` (`debian:latest`) only on `workflow_dispatch` with `run_reference_botplay=true`; extra images (`debian:11`, `debian:12`, `rockylinux:9`) for rom4s / built (`sm13-latest`) only with `botplay_extra_distros=true`.

| File | Role |
|------|------|
| `testing/cfg/botplay-server.cfg` | Base bots + fast rounds |
| `testing/cfg/botplay-stress.cfg` | Stress overlay (more bots, map/plugin cvars) |
| `testing/plugins/css34_botplay_stress.sp` | Map rotation + ABI probe |
| `testing/plugins/css34_sm_api_probe.sp` | Broad SM API exerciser: extensions inventory, core/clients/entity/sdktools/sdkhooks/cstrike, menus, usermessages, geoip, clientprefs, dbi/sqlite, regex, adt, sorting, keyvalues, lang. Skips `SlapPlayer` / `ForcePlayerSuicide` on bots (SM 1.12/1.13 CI segfault; wrong CommitSuicide/Teleport slots before #60); kills via `FakeClientCommand("kill")` instead. |

Override: `BOTPLAY_CFG=botplay-server.cfg` for the lighter profile without extra bots / plugin cvars.

Local short run (built):

```bash
chmod +x testing/scripts/*.sh
SM_PACKAGE="$(ls $PWD/packages/sourcemod-*-css34-linux.tar.gz)" \
MM_PACKAGE="$(ls $PWD/packages/mmsource-*-css34-linux.tar.gz)" \
BOTPLAY_PROFILE=built \
REPORT_JSON=$PWD/.ci-server/built-botplay-report.json \
RECORD_SECS=120 \
  testing/scripts/botplay-test.sh
testing/scripts/compare-botplay-reports.sh \
  testing/botplay/rom4s-baseline.json \
  .ci-server/built-botplay-report.json
```

Local short run (rom4s):

```bash
chmod +x testing/scripts/*.sh
SERVER_DIR=$PWD/.ci-server CACHE_DIR=$PWD/.ci-cache RECORD_SECS=120 \
  testing/scripts/fetch-server.sh
APPLY_VALVE_RC=1 APPLY_SRCDS_PATCH=1 testing/scripts/apply-valve-rc-fix.sh
APPLY_SRCDS_PATCH=1 testing/scripts/apply-srcds-patch.sh
KEEP_MAP=de_dust2 testing/scripts/trim-server-maps.sh
BOTPLAY_PROFILE=rom4s RECORD_SECS=120 testing/scripts/botplay-test.sh
cat .ci-server/botplay-report.txt
```

Artifacts: `botplay-report.json`, `built-botplay-report.json`, `botplay-compare.txt`, `cstrike/console.log`.

### Botplay bisect (built crash)

`test-botplay-bisect` is **off by default** (workflow_dispatch + `run_botplay_bisect`). It runs short (90s) cases via `testing/scripts/botplay-bisect.sh` on `debian:latest`. Set `BISECT_SET=quick` (5 cases, ~15 min) or `BISECT_SET=full` (19 cases, ~50 min).

**Root cause (2026-07):** built SM binaries are fine on CS:S v34; the crash (`Bad entity in IndexOfEdict()`) comes from **upstream `sdkhooks.games` gamedata** shipped in the package (wrong vtable offsets for ep1/CSS). Overlaying rom4s `gamedata/sdkhooks.games` onto a built install fixes botplay; `prepare-package.sh` now copies css34-specific sdkhooks gamedata from `builder/assets/gamedata/sdkhooks.games/`.

Reverse bisect (`rom4s` SM + one built `.so` at a time) passes for every binary; `rom4s` gamedata + built binaries also passes.

## Windows packages (Wine and native Windows)

`build.yml` `wine-smoke` boots the Windows packages on the Windows v34 server:
game content from the Linux server tree (or `srcds_css34_4044.zip`), Windows
binaries from rom4s `srcds_css34_w_a.zip` (`srcds.exe`, `bin/*.dll`,
`cstrike/bin/server.dll`), run with 32-bit Wine under Xvfb.
`testing/scripts/wine-smoke-test.sh` drives it over RCON
(`testing/scripts/rcon.py`): Metamod / SourceMod versions, the expected
extensions (`LOAD_EXTS` are loaded first), then a `changelevel`. On a failure
`testing/scripts/wine-crash-report.py` maps every access violation in the
Wine log (`WINEDEBUG=+seh,+loaddll`) to module + RVA and symbolizes it with
`llvm-symbolizer` when the `.pdb` from the Windows build sits next to the DLL.

The same script runs natively under Git Bash on Windows (`uname -s` MINGW /
MSYS): the `build.yml` `windows` job runs it on `windows-latest` right after
the build, with `spcomp.exe` run directly and `srcds.exe` started in its own
console window (`Start-Process`; with a pipe as stdin `-console` spins on
`GetNumberOfConsoleInputEvents` and never loads the map), game content
from `srcds_css34_4044.zip` (cached), the Windows Error Reporting dialog off
and WER LocalDumps writing a minidump of a crash to `.ci-winserver/dumps`
(printed with `cdb` and the PDBs when the SDK debuggers are installed;
uploaded as the `windows-smoke-<line>` artifact on a failure).

```bash
# needs wine32, xvfb, unzip, python3 (e.g. an ubuntu:22.04 container)
SM_WIN_PACKAGE="$(ls packages/sourcemod-*-css34-windows.zip)" \
MM_WIN_PACKAGE="$(ls packages/mmsource-*-css34-windows.zip)" \
SM_VERSION_EXPECT=1.13.0.7472 MM_VERSION_EXPECT=1.12.0 \
  testing/scripts/wine-smoke-test.sh
```

## Local run

```bash
chmod +x testing/scripts/*.sh

# Test freshly built SM + MM from builder/docker/legacy-build.sh (primary path).
# run-smoke.sh picks packages/*.tar.gz by itself; CSS34_LINE sets the expected versions.
CSS34_LINE=sm13-latest testing/scripts/run-smoke.sh

# Or the Metamod build tree instead of the MM tarball (default path is the MM 1.10 tree):
USE_BUILT_MM=1 BUILT_MM_PACKAGE=$PWD/deps/mmsource-1.12/build/package \
CSS34_LINE=sm13-latest \
  testing/scripts/run-smoke.sh
```

Needs root (or passwordless sudo) inside the target distro for package installs.
Without `SM_PACKAGE` / `MM_PACKAGE` and without `packages/*.tar.gz`, `install-addons.sh` downloads the
rom4s SM 6572 + MM 1.10.6 drops, i.e. it tests rom4s, not this repo.

## Version URLs

Published release pairs of the five `CSS34_LINE`s, mix PASS/FAIL notes, and historical community URLs live in [`versions/matrix.json`](versions/matrix.json) (`releases`, `compatibility`, `reference`). What each line pointer serves right now is in [`lines-index/lines.json`](https://github.com/fmu1337/sourcemod-css34/releases/download/lines-index/lines.json). CI smoke builds only in-tree pure-source packages — it does not download `reference.*` URLs.

## CI hygiene regression checks

Run `bash testing/scripts/check-package-paths.sh` and `actionlint` after workflow changes.
`ci-hygiene.yml` deliberately runs smoke against an empty server directory, requires
the expected missing-server failure, and uploads `negative-smoke-logs` for seven days.
After that workflow completes, verify the artifact is still downloadable. This
negative test does not relax any real server smoke or botplay gate.
