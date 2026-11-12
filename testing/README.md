# Server smoke testing (CS:S v34)

Scripts and workflows that boot a Counter-Strike: Source **v34** dedicated server with **our** Metamod:Source + SourceMod packages on a matrix of Linux distributions.

## Distro matrix

| Job | Images | Lines |
|---|---|---|
| `build-linux` (`.github/actions/build-linux`: build + ABI / export checks) | `builder/docker/build.sh` (manylinux2014) on ubuntu-22.04 | every active line |
| `smoke`, suite `pr` (PRs, `master` pushes) | `centos:7`, `ubuntu:24.04`, `debian:13` | every active line |
| `smoke`, suite `weekly` (Monday schedule, dispatch `suite=weekly`; also release.yml `smoke-release`) | `debian:8`, `debian:9`, `debian:10`, `debian:11`, `ubuntu:14.04`, `ubuntu:16.04`, `ubuntu:18.04`, `rockylinux:9` | every active line |
| `botplay`, suite `pr` | `debian:11` | every active line |
| `botplay`, suite `weekly` (also release.yml `botplay-release`) | `centos:7` | every active line |
| `host-checks` (install, core PLAPI probe, smoke) | ubuntu-22.04 host | every active line |
| `build-windows` (build + native Windows smoke + PLAPI probe) | windows-2022 | lines with `"windows": true` |
| `wine-smoke` (weekly suite only) | `ubuntu:22.04` + Wine | lines with `"windows": true` |
| `gate` | — | always, including doc-only PRs |

`builder/scripts/ci_planner.py` picks the suite and the matrices; `ci_gate.py` checks that every
job the plan requires succeeded. Dispatch inputs: `suite` (`pr` / `weekly`) and `css34_line`
(one active line).

`debian:11` is no longer a per-PR smoke image. The single per-PR botplay run still uses it. Every image above is pinned by digest in `builder/lines.json` (`python3 builder/lines.py gen`).

### Prebuilt test images

Smoke, botplay and frozen-verify containers do not install their runtime on every run.
`.github/workflows/test-images.yml` builds each image above `FROM <name>@<digest>` with
`testing/scripts/install-deps.sh` run at build time (`testing/docker/test-image.Dockerfile`)
and pushes `ghcr.io/fmu1337/css34-test:<slug>-<12 hex of sha256(install-deps.sh, base digest)>`.
`builder/lines.json` `test_images` records the pushed digests:

```json
"test_images": {"debian:11": {"ref": "ghcr.io/fmu1337/css34-test@sha256:…", "base": "sha256:<base digest>", "deps_hash": "<sha256 of install-deps.sh>"}}
```

- `lines.py` puts a current entry into the matrix rows as `image` (with `base_image`, the
  pinned base, and `prebuilt: "1"`); without one the row runs the base image as before.
  `lines.py check` refuses entries that are not smoke/botplay images, malformed refs, and
  entries whose `deps_hash` / `base` no longer match `install-deps.sh` / `images`
  (`python3 builder/lines.py test-images-prune && python3 builder/lines.py gen`).
- Jobs still call `install-deps.sh`. In a prebuilt image it finds
  `/etc/css34-install-deps.sha256` equal to its own sha256 and prints
  `Dependencies prebuilt in this image (…); nothing to install.` (no apt/yum traffic); in any
  other image, or with `CSS34_DEPS_FORCE=1`, it installs as before.
- `testing/scripts/pull-test-image.sh "$IMAGE" "$BASE_IMAGE"` logs in to ghcr.io with
  `GHCR_TOKEN` (the job's `GITHUB_TOKEN`, `packages: read`), pulls, and falls back to the
  base image when the prebuilt one cannot be pulled. `release-smoke.sh` does the same
  (`lines.py test-image-ref <name>` when no `IMAGE` is given).
- New digests: on master (`install-deps.sh`, the Dockerfile or `lines.json` changed), weekly and on
  dispatch, the workflow builds what `lines.json` lacks (dispatch `rebuild_all`: everything;
  weekly: also recorded images that can no longer be pulled) and opens the PR
  `test-images/update` with the bump GitHub App. On a same-repository PR touching
  `install-deps.sh` it pushes the images and prints `results.json` in the `record` job;
  commit it with `python3 builder/lines.py test-images-record results.json && python3 builder/lines.py gen`.

CI installs **only** the in-tree `packages/mmsource-*-css34-linux.tar.gz` and `packages/sourcemod-*-css34-linux.tar.gz` from `build-linux` (handed to later jobs via Actions cache, not artifacts). rom4s reference drops are not used in this workflow.

Packages come from `builder/docker/build.sh` (manylinux2014, glibc 2.17). `debian:latest` remains only on the opt-in reference botplay jobs, and that tag is pinned too.

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
3. `meta version` / `sm version` — `+<MM_REV>` and `Build ID: <MM_REV>:<sha prefix>`, and `SourceMod Version: <major>.<SM_REV>`
4. `sm exts load dbi.mysql.ext` and `sm exts load dbi.pgsql.ext` must succeed. `geoip.ext` and `regex.ext` are loaded too, and a failure there is recorded but does not fail the run. `sm exts list` prints the full list; fails on `<FAILED>`; requires BinTools + SDK Tools + CS Tools + **SDK Hooks**
5. `sm plugins list` — every enabled `.smx` listed as Running (not `<Failed>`)
6. SourceMod session log (`addons/sourcemod/logs/L*.log`) — no error markers
7. **sdkhooks.games** `OnTakeDamage` linux offset **61** (css34)
8. Every SDKTools / SDKHooks vtable offset in the installed gamedata matches the `CCSPlayer` / `CWeaponCSBase` vtables of the v34 `server_i486.so` (`check-css34-vtables.py`; needs `python3` + `c++filt`, which `install-deps.sh` provides, including Python 3.4 on Debian 8 and Ubuntu 14.04). `CSS34_CI=1` fails the run if that check is skipped.
9. No segfault; not flooded with `Unknown command` (buffer bug signature)
10. With `SMOKE_EXPECT_CORE=1.ep1|2.ep1` (CI sets it from the matrix row): the expected SourceMod core runs, and DHooks loads exactly on the 2.ep1 core. Built lines run `2.ep1`; `1.ep1` is left for the frozen dual-core SM 1.11 (`frozen-verify.yml` smokes its pointer's `mmsource-legacy` on MM 1.10.7, where its `dhooks.ext.2.ep1` must not load).

`BOTPLAY_EXPECT_DHOOKS` (from the row's `dhooks_expect`) makes the botplay DHooks probe mandatory.

The **botplay-stress** matrix (`test-built-botplay-matrix`) is the largest CI gate: SMAC + 8 bots + map rotation + `css34_botplay_stress.smx` SDKHook_OnTakeDamage probe (requires OnTakeDamage hits in SM logs) + `css34_cstrike_forward_probe.smx` (requires cstrike TerminateRound / buy / price detour hits and a `GetPlayerWeaponSlot` → `CS_DropWeapon` → `GivePlayerItem` round, `css34_cs_probe_mode 8` in `botplay-stress.cfg`)) + `css34_dhooks_probe.smx` (where dhooks.ext ships: DHooks virtual hooks on `CCSPlayer::OnTakeDamage`, `CBasePlayer::EyePosition` (Vector return, override) and `CCSPlayer::PlayStepSound` (float param, `MRES_ChangedHandled` recall), and detours on `CCSPlayer::RoundRespawn` and `CWeaponCSBase::GetMaxSpeed` (float return, override) must install, fire and return sane values; probe gamedata lives in `testing/plugins/gamedata/`; lines without DHooks log `available=0` and are skipped) + `css34_gamedata_probe.smx` (gamedata `"library" "engine"` symbols `@sv`, `@Cmd_ExecuteString` and navfile_blocker's `@CDownloadListGenerator::OnResourcePrecachedFullPath`, and `"library" "server"` `@CWeaponCSBase::GetMaxSpeed`, must resolve; it also logs the engine's `GAMEBIN` / `EXECUTABLE_PATH` search paths) + prebuilt plugins from spcomp 1.7.3 and 1.11 (`testing/plugins/legacy-smx/`: stock `adminmenu` / `basecommands` / `funcommands` / `basechat` / `basecomm` / `playercommands` replace the package copies, and `css34_legacy_forward_probe` calls global, private and function forwards with mixed parameter types across the 1.7.3, 1.11 and package-compiled copies; `check-legacy-plugins.sh` fails on `<Failed>` / `<Error>` plugins, missing natives, plugin load errors and forward argument errors) + `css34_upstream_probe.smx` (sound hook `Plugin_Changed` continues into the next hook on SM 1.13.0.7475+, a `HookSingleEntityOutput` does not fire on a new `logic_relay` after a map change, and `GetClientOfUserId` rejects out-of-range userids). Runs for all `CSS34_LINE` builds on every `master` push.

## `srcds_run` / engine launch flags

String-audited notes for CSS v34 (`-dev`, `-debug`, `-norestart`, `-tickrate`, dedicated/engine layers, MyArena cross-checks): [docs/srcds-params.md](docs/srcds-params.md). Re-scrape stock binaries with `testing/scripts/extract-srcds-params.sh`.

## Buffer / modern-OS fixes

See [docs/bufferfix.md](docs/bufferfix.md). CI defaults to:

- minimal `cstrike/cfg/valve.rc`
- **srcds_patch** — ELF rewrite memcpy→memmove (`patch-srcds-bufferfix.py`)

## Botplay baseline (rom4s + SMAC)

`testing/botplay/rom4s-baseline.json` holds the counters of a session with **rom4s** Metamod 1.10.6 + SourceMod 6572: compile [smac_v34](https://github.com/fmu1337/smac_v34), spawn bots (`botplay-server.cfg`), record, then parse `cstrike/console.log` for `round_start`, `round_end`, and kills. To re-record it, run `testing/scripts/botplay-test.sh` locally with `BOTPLAY_PROFILE=rom4s` (the CI job for it was removed: it never ran).

`ci.yml` `botplay` runs the same session with the **built** MM + SM packages of every line and compares against `testing/botplay/rom4s-baseline.json` for information only (the comparison goes to the job summary). Event-count differences do not fail CI; the botplay crash, extension, gamedata and API/ABI checks remain required. Published releases get the same session in release.yml `botplay-release` (`BOTPLAY_PROFILE=release`).

SM 1.12+ `geoip.ext` needs a GeoIP2 `*.mmdb` under `configs/geoip/`. Our packages ship `GeoLite2-Country.mmdb` (`prepare-package.sh`, enforced by `check-package.sh`); `botplay-test.sh` also installs one via `install-geoip2-db.sh` when it is missing (e.g. for rom4s packages).

**Stress profile (default):** `botplay-stress.cfg` execs `botplay-server.cfg` (fast 1‑minute rounds) then raises `bot_quota` to 8. Plugin `css34_botplay_stress.smx` rotates maps every 3 rounds (`de_dust2` → `de_inferno` → `de_nuke`) and logs sdkhooks/sdktools ABI probe results each round.

**When they run:** `botplay` (300 s per line) runs on `debian:11` on every push / PR and on `centos:7` in the weekly suite; release.yml `botplay-release` runs it on `centos:7` against the published URLs.

| File | Role |
|------|------|
| `testing/cfg/botplay-server.cfg` | Base bots + fast rounds |
| `testing/cfg/botplay-stress.cfg` | Stress overlay (more bots, map/plugin cvars) |
| `testing/plugins/css34_botplay_stress.sp` | Map rotation + ABI probe |
| `testing/plugins/css34_sm_api_probe.sp` | Broad SM API exerciser: extensions inventory, core/clients/entity/sdktools/sdkhooks/cstrike, menus, usermessages, geoip, clientprefs, dbi/sqlite, regex, adt, sorting, keyvalues, lang. Skips `SlapPlayer` / `ForcePlayerSuicide` on bots (SM 1.12/1.13 CI segfault; wrong CommitSuicide/Teleport slots before #60); kills via `FakeClientCommand("kill")` instead. |
| `testing/plugins/css34_upstream_probe.sp` | Sound `Plugin_Changed` chain (#2586), entity output hook cleared across a map change (#2589), userid lookup bounds (#2577). `testing/scripts/check-upstream-probe.sh` reads the log line. |

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

`testing/scripts/botplay-bisect.sh` runs short (90s) cases locally (the CI job for it was removed: it never ran). Set `BISECT_SET=quick` (5 cases, ~15 min) or `BISECT_SET=full` (19 cases, ~50 min).

**Root cause (2026-07):** built SM binaries are fine on CS:S v34; the crash (`Bad entity in IndexOfEdict()`) comes from **upstream `sdkhooks.games` gamedata** shipped in the package (wrong vtable offsets for ep1/CSS). Overlaying rom4s `gamedata/sdkhooks.games` onto a built install fixes botplay; `prepare-package.sh` now copies css34-specific sdkhooks gamedata from `builder/assets/gamedata/sdkhooks.games/`.

Reverse bisect (`rom4s` SM + one built `.so` at a time) passes for every binary; `rom4s` gamedata + built binaries also passes.

## Legacy-plugin bridge (T2.9)

Every MM 1.12 package with the bridge (`sm12-latest` / `sm13-latest` through
`bridge_metamod` in `builder/lines.json`, and the frozen `sm11-oldstable`) ships
`metamod.2.ep1` and the MM 1.10 legacy core `metamod.1.ep1`. MM 1.12 refuses PLAPI 7-12 plugins upstream ("Older Metamod
version required"); with the bridge it loads `metamod.1.ep1` on first use and
lets it host them, so old MM 1.4-1.10 plugins run next to SourceMod (2.ep1
core, any of 1.11 / 1.12 / 1.13) without deleting any Metamod file. Each old plugin shows in `meta list` and
answers `meta unload` / `meta pause`.

`testing/plugins/css34_legacy_probe` is a PLAPI 11 plugin built with the MM
1.10 build. It writes `addons/metamod/css34_legacy_probe.log`
(`load api=11 late=0`, `all_loaded`, `level_init map=…`, `unload`).
`testing/scripts/legacy-bridge-test.sh` (Linux, after `smoke-test.sh` on the
rows with `legacy_bridge=1`) and `wine-smoke-test.sh` with `LEGACY_PROBE`
(Windows) require it to load through the bridge, hook `LevelInit` with
SourceHook v4 and show in `meta list`; the Linux test also unloads it.

```bash
SERVER_DIR=.ci-server LEGACY_PROBE=packages/test-plugins/css34_legacy_probe.so \
  testing/scripts/legacy-bridge-test.sh
```

## MySQL/MariaDB TLS probe (T4.5)

sm13's Linux `dbi.mysql.ext` statically links MariaDB Connector/C and OpenSSL
3.5 and reads `ssl_mode` / `ssl_ca` from `databases.cfg` (`docs/PATCHES.md`,
"sm13 MySQL dependencies" and "sm13 MySQL TLS options"). The PR and weekly smoke
jobs start three containers on network `css34-db` with one throwaway CA
(`testing/scripts/mysql-tls-server.sh start DIR`; images pinned in
`builder/lines.json`): `css34-mariadb` (MariaDB 11.8), `css34-mysql` (MySQL 8.4,
`caching_sha2_password`) and `css34-mysql-notls` (MySQL 8.4 with TLS turned
off). The server certificate names `css34-mariadb` and `css34-mysql`, no IP
address. Each server has `css34_tls` (`REQUIRE SSL`) and `css34_plain`.
`testing/scripts/mysql-tls-test.sh` runs after `smoke-test.sh`; it is skipped
when the installed extension embeds no OpenSSL (sm12).

1. `packages/test-plugins/css34_mysql_tls_probe` (built from the extension's own
   archives, never released) must connect to MariaDB with verified TLS to the
   `REQUIRE SSL` account, client and server must agree on the TLS version and
   cipher, and the TLS library must be the OpenSSL the build compiled against.
   A plaintext login and TLS against an unrelated CA must be refused.
2. `testing/plugins/css34_mysql_probe/css34_mysql_probe.sp` runs in srcds: the
   script adds `databases.cfg` entries (CA files under
   `addons/sourcemod/configs/css34-mysql-probe/`, `ssl_ca` relative), boots the
   server once and runs one RCON command per case. The server's view of each
   session (`Ssl_version`, `Ssl_cipher`, `@@character_set_client`) is logged
   and compared with the expectation:

| Case | Configuration | Expected |
|------|---------------|----------|
| `identity` | `verify_identity`, `ssl_ca`, MySQL by name | TLS 1.2+, `utf8mb4` |
| `ca_ip` | `VERIFY_CA` (any case), by IP address | TLS (no host name check) |
| `identity_ip` | `verify_identity` by IP address | refused, `[2026]` host name |
| `required` | `required`, no CA | TLS |
| `default` | no `ssl_*` keys, `css34_plain` | plaintext (default `disabled`) |
| `default_tls_user` | no `ssl_*` keys, `REQUIRE SSL` account | refused, `[1045]` |
| `preferred` | `preferred`, `css34_plain` | TLS |
| `disabled_plain` | `disabled`, `css34_plain` | plaintext (`caching_sha2_password` over RSA) |
| `disabled` | `disabled`, `REQUIRE SSL` account | refused, `[1045]` |
| `wrong_ca` | `verify_identity`, unrelated CA | refused, `[2026]` |
| `bad_mode` | `ssl_mode verify_full` | refused, `[0]: ssl_mode "verify_full" is not one of ...` |
| `no_ca` | `verify_ca` without `ssl_ca` | refused, `[0]: ... needs ssl_ca` |
| `async` | `Database.Connect` (worker thread), `verify_identity` | TLS |
| `persist_plain`, `persist_tls` | persistent `disabled`, then persistent `preferred` with the same host/user/password | plaintext, then TLS (no reuse) |
| `custom`, `custom_bad` | `SQL_ConnectCustom` KeyValues with `ssl_mode` / `ssl_ca` | TLS; unknown mode refused |
| `notls_preferred` | `preferred`, server without TLS | plaintext (`preferred` falls back) |
| `notls_required`, `notls_verify` | `required`, `verify_ca`, server without TLS | refused before login, `[2026]` |
| `mdb_default`, `mdb_identity` | MariaDB, no keys and `verify_identity` | plaintext; TLS |

```bash
testing/scripts/mysql-tls-server.sh start .ci-mysql-tls
# inside the smoke container, on network css34-db:
SERVER_DIR=.ci-server MYSQL_TLS_CERTS=.ci-mysql-tls \
  MYSQL_TLS_PROBE=packages/test-plugins/css34_mysql_tls_probe testing/scripts/mysql-tls-test.sh
testing/scripts/mysql-tls-server.sh stop
```

## Windows packages (Wine and native Windows)

`testing/scripts/wine-smoke-test.sh` boots the Windows packages on the Windows v34 server,
natively in `build-windows` (every PR) and under Wine in `wine-smoke` (weekly suite):
game content from the Linux server tree (or `srcds_css34_4044.zip`), Windows
binaries from rom4s `srcds_css34_w_a.zip` (`srcds.exe`, `bin/*.dll`,
`cstrike/bin/server.dll`), run with 32-bit Wine under Xvfb.
`testing/scripts/wine-smoke-test.sh` drives it over RCON
(`testing/scripts/rcon.py`): Metamod / SourceMod versions, the expected
extensions (`LOAD_EXTS` are loaded first; the matrix loads `sdkhooks` and
requires **SDK Hooks**). When the package contains `dhooks.ext.dll` the script
also loads it and requires **DHooks**. `DHOOKS_EXPECT` (from the matrix
`dhooks_expect`) overrides that. Then a `changelevel`.

Both run one row per line (`windows` matrix) on the line's MM 1.12 zip, with
`LEGACY_PROBE` on lines with a `bridge_metamod`. `build-windows` then runs
`check-core-plapi.sh` on the installed server: the probe is built with `cl`
and requires PLAPI 11 from `sourcemod.1.ep1.dll` and 16 from `sourcemod.2.ep1.dll`. On a failure
`testing/scripts/wine-crash-report.py` maps every access violation in the
Wine log (`WINEDEBUG=+seh,+loaddll`) to module + RVA and symbolizes it with
`llvm-symbolizer` when the `.pdb` from the Windows build sits next to the DLL.

The same script runs natively under Git Bash on Windows (`uname -s` MINGW /
MSYS): the `ci.yml` `build-windows` job runs it on `windows-2022` right after
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
SM_VERSION_EXPECT=1.13.0.7488 MM_VERSION_EXPECT=1.12.0 \
EXPECT_EXTS='CS Tools,SDK Tools,BinTools,SDK Hooks' LOAD_EXTS=sdkhooks \
  testing/scripts/wine-smoke-test.sh
```

**Accepted gap:** this smoke is not the Linux botplay-stress profile. It does not
run SMAC, the cstrike native round, or the SDKHooks `OnTakeDamage` hit counter.
When `dhooks.ext.dll` is in the package, `DHOOKS_PROBE_SECS` still plays bots on
`de_dust2` and checks the DHooks probe. A separate short Wine botplay beyond that
probe is not part of the gate.

## Local run

```bash
chmod +x testing/scripts/*.sh

# Test freshly built SM + MM from builder/docker/build.sh (primary path).
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

Run `actionlint` (`testing/scripts/install-actionlint.sh` installs the pinned version) and
`bash testing/scripts/run-host-tests.sh` after workflow changes. The runner runs every
`testing/scripts/test-*.py` / `test-*.sh` and the negative smoke check (needs GCC, binutils
and Expect); pass test names to run only those, e.g.
`bash testing/scripts/run-host-tests.sh test-glibc-imports.py test-console-probe.py`.
CI `hygiene` runs the whole set, so a new `test-*` script is picked up without a workflow edit.
The `hygiene` job in `ci.yml` deliberately runs smoke against an empty server directory, requires
the expected missing-server failure, and uploads `negative-smoke-logs` for seven days.
After that workflow completes, verify the artifact is still downloadable. This
negative test does not relax any real server smoke or botplay gate.
