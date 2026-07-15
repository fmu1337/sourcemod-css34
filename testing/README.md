# Server smoke testing (CS:S v34)

Scripts and workflows that boot a Counter-Strike: Source **v34** dedicated server with **our** Metamod:Source + SourceMod packages on a matrix of Linux distributions.

## Distro matrix

| Job | Images | Packages under test |
|---|---|---|
| `test-built-debian` | `debian:11` … `13` / `latest` | **built** MM 1.10.7 + SM 6572 |
| `test-built-rhel` | `rockylinux:9` | **built** MM 1.10.7 + SM 6572 |
| `test-built-smoke` | ubuntu-22.04 host | **built** MM 1.10.7 + SM 6572 |
| `check-built-package` | ubuntu-22.04 | freshly built SM artifact (CreateInterface + DT_NEEDED) |

CI installs **only** the in-tree `packages/mmsource-*-css34-linux.tar.gz` and `packages/sourcemod-*-css34-linux.tar.gz` artifacts from `build-linux`. rom4s reference drops are not used in this workflow.

Packages come from `legacy-build.sh` (`debian:11`), so the smoke matrix starts at Debian 11+ / Rocky 9.

When the CI server tree is trimmed to a single map (`de_dust2`), `testing/scripts/trim-server-maps.sh` also rewrites `mapcycle.txt` so the engine does not spam `Map_IsValid: No such map` for deleted BSPs.

## Smoke logging

| Variable | Default | Effect |
|---|---|---|
| `SMOKE_CONDEBUG=1` | on | srcds `-condebug` → `cstrike/console.log` |
| `SMOKE_VERBOSE=1` | off in local runs | expect `log_user 1`, `+log on +sv_logfile 1` |

On failure, smoke prints tails of `smoke.log`, `console-probe.log`, `cstrike/console.log`, and SourceMod `L*.log`. CI uploads them as smoke-log artifacts from built jobs.

## What the smoke test checks

1. Game DLL loads (`Counter-Strike: Source`)
2. Map / dedicated server config starts (`Mapchange to …` in console)
3. `sm version` — expected MM/SM versions
4. `sm exts list` — prints full list; fails on `<FAILED>`; requires SDK Tools + CS Tools
5. `sm plugins list` — every enabled `.smx` listed as Running (not `<Failed>`)
6. SourceMod session log (`addons/sourcemod/logs/L*.log`) — no error markers
7. No segfault; not flooded with `Unknown command` (buffer bug signature)

## `srcds_run` / engine launch flags

String-audited notes for CSS v34 (`-dev`, `-debug`, `-norestart`, `-tickrate`, dedicated/engine layers, MyArena cross-checks): [docs/srcds-params.md](docs/srcds-params.md). Re-scrape stock binaries with `testing/scripts/extract-srcds-params.sh`.

## Buffer / modern-OS fixes

See [docs/bufferfix.md](docs/bufferfix.md). CI defaults to:

- minimal `cstrike/cfg/valve.rc`
- **srcds_patch** (bruno_args) — verified memcpy→memmove rewrite

## Botplay baseline (rom4s + SMAC)

`test-rom4s-botplay` boots the css34 server with **rom4s** Metamod 1.10.6 + SourceMod 6572, compiles [smac_v34](https://github.com/fmu1337/smac_v34), spawns 4 bots (`botplay-server.cfg`), records **600s** by default, then parses `cstrike/console.log` for `round_start`, `round_end`, and kills.

`test-built-botplay` runs the same session with **built** MM 1.10.7 + SM 6572 and compares against `testing/botplay/rom4s-baseline.json` (candidate must reach ≥75% of baseline event counts).

**Stress profile (default):** `botplay-stress.cfg` execs `botplay-server.cfg` (fast 1‑minute rounds) then raises `bot_quota` to 8. Plugin `css34_botplay_stress.smx` rotates maps every 3 rounds (`de_dust2` → `de_inferno` → `de_nuke`) and logs sdkhooks/sdktools ABI probe results each round.

**CI distro default:** `test-rom4s-botplay` and `test-built-botplay` run on **`debian:latest` only** (~20 min total on `cursor/**` pushes). Extra images (`debian:11`, `debian:12`, `rockylinux:9`) are optional via workflow_dispatch input `botplay_extra_distros`.

| File | Role |
|------|------|
| `testing/cfg/botplay-server.cfg` | Base bots + fast rounds |
| `testing/cfg/botplay-stress.cfg` | Stress overlay (more bots, map/plugin cvars) |
| `testing/plugins/css34_botplay_stress.sp` | Map rotation + ABI probe |

Override: `BOTPLAY_CFG=botplay-server.cfg` for the lighter profile without extra bots / plugin cvars.

Local short run (built):

```bash
chmod +x testing/scripts/*.sh
SM_PACKAGE=$PWD/packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz \
MM_PACKAGE=$PWD/packages/mmsource-1.10.7-dev-css34-linux.tar.gz \
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

## Local run

```bash
chmod +x testing/scripts/*.sh

# Test freshly built SM + MM from builder/run/linux.sh (primary path):
MM_PACKAGE=$PWD/packages/mmsource-1.10.7-dev-css34-linux.tar.gz \
SM_PACKAGE=$PWD/packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz \
MM_VERSION_EXPECT=1.10.7 \
  testing/scripts/run-smoke.sh

# Or USE_BUILT_MM against deps/mmsource-1.10/build/package + local SM tarball:
USE_BUILT_MM=1 \
SM_PACKAGE=$PWD/packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz \
MM_VERSION_EXPECT=1.10.7 \
  testing/scripts/run-smoke.sh
```

Needs root (or passwordless sudo) inside the target distro for package installs.

## Version URLs

Historical community SM/MM download URLs are listed in [`versions/matrix.json`](versions/matrix.json) for local comparison only — CI does not pull them.
