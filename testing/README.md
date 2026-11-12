# Testing

Every check boots a real CS:S v34 dedicated server (`srcds_i686`, build 4044) with our packages.

## What runs where

| Job (`ci.yml`) | Images | When |
|---|---|---|
| `build-linux`: build + static checks (glibc ≤ 2.17, exports, unversioned imports, gamedata) | manylinux2014 | every PR |
| `smoke` | `centos:7`, `ubuntu:24.04`, `debian:13` | every PR |
| `smoke` | `debian:8`–`11`, `ubuntu:14.04`–`18.04`, `rockylinux:9` | weekly, release |
| `botplay` | `debian:11` (PR), `centos:7` (weekly, release) | |
| `host-checks`: install, core PLAPI probe, smoke on the runner | ubuntu-22.04 | every PR |
| `build-windows`: build + native Windows smoke | windows-2022 | every PR |
| `wine-smoke` | ubuntu:22.04 + Wine | weekly |
| `hygiene`: host tests + a negative smoke | | every PR |

Images are pinned by digest in `builder/lines.json`. `test-images.yml` bakes `install-deps.sh` into
`ghcr.io/fmu1337/css34-test` images (`lines.json` `test_images`); after editing `install-deps.sh`, run
`python3 builder/lines.py test-images-prune && python3 builder/lines.py gen` and let the workflow open
the `test-images/update` PR.

## Smoke (`smoke-test.sh`)

1. The game DLL loads and the map starts; no segfault, no `Unknown command` flood (buffer bug).
2. `meta version` has `+<MM_REV>` and `Build ID: <MM_REV>:<sha>`; `sm version` is `<major>.<SM_REV>`.
3. `dbi.mysql`, `dbi.pgsql` load; BinTools, SDK Tools, CS Tools, SDK Hooks run; no `<FAILED>` extension
   or plugin; no errors in the SourceMod log.
4. Gamedata: `OnTakeDamage` linux 61, and every SDKTools / SDKHooks vtable offset matches the v34
   `server_i486.so` (`check-css34-vtables.py`).
5. The expected core runs (`SMOKE_EXPECT_CORE`, `2.ep1`; `1.ep1` only for sm11's `mmsource-legacy`).
6. Legacy-plugin bridge: the PLAPI 11 probe `css34_legacy_probe` loads through MM 1.12, hooks
   `LevelInit` and unloads (`legacy-bridge-test.sh`).
7. sm13 MySQL TLS: against MariaDB 11.8, MySQL 8.4 and MySQL 8.4 without TLS
   (`mysql-tls-server.sh`, `mysql-tls-test.sh`) every `ssl_mode` behaves as documented, a plaintext login
   to a `REQUIRE SSL` account and a wrong CA are refused.

The server tree comes from `fetch-server.sh` → `apply-valve-rc-fix.sh` → `apply-srcds-patch.sh`
(memcpy → memmove rewrite of the v34 binaries, [docs/bufferfix.md](docs/bufferfix.md)) →
`trim-server-maps.sh`.

## Botplay (`botplay-test.sh`)

SMAC ([smac_v34](https://github.com/fmu1337/smac_v34)) + 8 bots, map rotation `de_dust2` → `de_inferno` →
`de_nuke`, 300 s per line. Required:

- `css34_botplay_stress`: `SDKHook_OnTakeDamage` hits, SDKHooks / SDKTools ABI probe each round;
- `css34_cstrike_forward_probe`: TerminateRound / buy / price detours fire, `CS_DropWeapon` round;
- `css34_dhooks_probe` (where DHooks ships): virtual hooks, detours, `Vector` / `float` returns, recall;
- `css34_gamedata_probe`: `"library" "engine"` / `"server"` signatures resolve;
- `css34_sm_api_probe`: a broad SourceMod API pass (sdktools, sdkhooks, cstrike, menus, dbi, …);
- `css34_upstream_probe`: upstream fixes SM #2586, #2589, #2577 still hold;
- `.smx` built by spcomp 1.7.3 and 1.11 (`plugins/legacy-smx/`) load and call forwards correctly.

## Local runs

```bash
CSS34_LINE=sm13-latest testing/scripts/run-smoke.sh          # picks packages/*.tar.gz

SM_PACKAGE="$(ls $PWD/packages/sourcemod-*-css34-linux.tar.gz)" \
MM_PACKAGE="$(ls $PWD/packages/mmsource-*-css34-linux.tar.gz)" \
RECORD_SECS=120 testing/scripts/botplay-test.sh

# Windows packages under Wine (wine32, xvfb, unzip, python3)
SM_WIN_PACKAGE="$(ls packages/sourcemod-*-css34-windows.zip)" \
MM_WIN_PACKAGE="$(ls packages/mmsource-*-css34-windows.zip)" \
SM_VERSION_EXPECT=1.13.0.<SM_REV> MM_VERSION_EXPECT=1.12.0 \
EXPECT_EXTS='CS Tools,SDK Tools,BinTools,SDK Hooks' LOAD_EXTS=sdkhooks \
  testing/scripts/wine-smoke-test.sh

bash testing/scripts/run-host-tests.sh                        # all test-*.py / test-*.sh (needs gcc, binutils, expect)
```

Smoke needs root (or passwordless sudo) in the target distro. `install-addons.sh` fails without
`SM_PACKAGE` / `MM_PACKAGE`. The Windows smoke covers no SMAC / cstrike botplay, only the DHooks probe.
