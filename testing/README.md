# Server smoke testing (CS:S v34)

Scripts and workflows that boot a Counter-Strike: Source **v34** dedicated server with Metamod:Source + SourceMod on a matrix of Linux distributions.

## Distro matrix

| Job | Images | Packages under test |
|---|---|---|
| `test-built-debian` | `debian:11` … `13` / `latest` | **our built** MM 1.10.7 + SM 6572 |
| `test-built-rhel` | `rockylinux:9` | **our built** MM 1.10.7 + SM 6572 |
| `test-built-smoke` | ubuntu-22.04 host | **our built** MM 1.10.7 + SM 6572 |
| `check-built-package` | ubuntu-22.04 | freshly built SM artifact (CreateInterface + DT_NEEDED) |
| `test-reference-legacy` | `debian:8`–`10`, `centos:7` | rom4s reference MM 1.10.6 + SM 6572 |

Rocky Linux stands in for modern CentOS-stream/RHEL-family hosts (CentOS 8+ is EOL).

Primary CI gate is **our in-tree packages** on Debian 11+ / Rocky 9 / Ubuntu host. Legacy distros stay on rom4s reference so `deps` / `srcds_patch` / boot remain covered on old glibc (our `debian:11` legacy-build packages are too new for Debian 8–10 / CentOS 7).

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

## Buffer / modern-OS fixes

See [docs/bufferfix.md](docs/bufferfix.md). CI defaults to:

- minimal `cstrike/cfg/valve.rc`
- **srcds_patch** (bruno_args) — verified memcpy→memmove rewrite

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

# Reference rom4s packages (legacy glibc / harness debug):
SERVER_DIR=$PWD/.ci-server CACHE_DIR=$PWD/.ci-cache testing/scripts/run-smoke.sh
```

Needs root (or passwordless sudo) inside the target distro for package installs, plus network access to Bitbucket/GitHub downloads.

## Version URLs

Known SM/MM download URLs used in the community builds are listed in [`versions/matrix.json`](versions/matrix.json). Workflow dispatch accepts an optional `sm_url` to override the reference SourceMod package on legacy jobs.
