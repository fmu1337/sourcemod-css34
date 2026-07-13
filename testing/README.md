# Server smoke testing (CS:S v34)

Scripts and workflows that boot a Counter-Strike: Source **v34** dedicated server with Metamod:Source + SourceMod on a matrix of Linux distributions.

## Distro matrix

| Job | Images | SourceMod under test |
|---|---|---|
| `test-debian` | `debian:8` … `13` / `latest` | rom4s **reference** 1.11.0.6572 (or `sm_url`) |
| `test-centos` | `centos:7`, `rockylinux:8`, `rockylinux:9` | same reference |
| `check-built-package` | ubuntu-22.04 | freshly built artifact (CreateInterface + DT_NEEDED) |
| `test-built-smoke` | ubuntu-22.04 | **built MM** + rom4s SM 6572 (until in-tree SM smoke is green) |

Rocky Linux stands in for modern CentOS-stream/RHEL-family hosts (CentOS 8+ is EOL).

When the CI server tree is trimmed to a single map (`de_dust2`), `testing/scripts/trim-server-maps.sh` also rewrites `mapcycle.txt` so the engine does not spam `Map_IsValid: No such map` for deleted BSPs.

## Smoke logging

| Variable | Default | Effect |
|---|---|---|
| `SMOKE_CONDEBUG=1` | on | srcds `-condebug` → `cstrike/console.log` |
| `SMOKE_VERBOSE=1` | off in local runs | expect `log_user 1`, `+log on +sv_logfile 1` |

On failure, smoke prints tails of `smoke.log`, `console-probe.log`, `cstrike/console.log`, and SourceMod `L*.log`. CI uploads them as the `built-smoke-logs` artifact from `test-built-smoke`.

The distro matrix uses the known-good rom4s package so OS/deps/`srcds_patch` stay covered on old glibc. Host-built packages need CreateInterface + real `tier0`/`vstdlib` link libs; they may require GLIBC 2.29+ (Debian 11+ / modern Rocky), while rom4s 6572 stays on ~2.4 for Debian 8–10 / CentOS 7.

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

# Uses rom4s SM 1.11.0.6572 by default:
SERVER_DIR=$PWD/.ci-server CACHE_DIR=$PWD/.ci-cache testing/scripts/run-smoke.sh

# Test freshly built SM + MM from builder/run/linux.sh:
USE_BUILT_MM=1 \
SM_PACKAGE=$PWD/packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz \
  testing/scripts/run-smoke.sh

# Or explicit Metamod package tarball:
MM_PACKAGE=$PWD/packages/mmsource-1.10.7-dev-css34-linux.tar.gz \
SM_PACKAGE=$PWD/packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz \
  testing/scripts/run-smoke.sh
```

Needs root (or passwordless sudo) inside the target distro for package installs, plus network access to Bitbucket/GitHub downloads.

## Version URLs

Known SM/MM download URLs used in the community builds are listed in [`versions/matrix.json`](versions/matrix.json). Workflow dispatch accepts an optional `sm_url` to test a published package instead of building from this repo.
