#!/usr/bin/env bash
# Like run-case2.sh but: uses research/oldos/repo-copy (install-deps fixes for bash4.3/centos vault https),
# and does not copy hl2/ (564MB) — symlinks it to a read-only mount of scratchpad/srv/hl2. Deletes srv after run.
# usage: run-case-lite.sh <name> <image> <sm.tgz|""> <mm.tgz|""> <sm_ver> <mm_ver> <sm_commit> <mm_commit> [nosm]
set -uo pipefail
S=/tmp/claude-0/-home-user-sourcemod-css34/ffbe8980-eece-56cf-8782-bc5e5af6297c/scratchpad
name="$1" image="$2" sm="$3" mm="$4" nosm="${9:-0}"
out="$S/smoke-$name"; rm -rf "$out"; mkdir -p "$out/pkg"
smenv=(); mmenv=()
[[ -n "$sm" ]] && { cp -f "$sm" "$out/pkg/sm.tar.gz"; smenv=(-e SM_PACKAGE=/out/pkg/sm.tar.gz); }
[[ -n "$mm" ]] && { cp -f "$mm" "$out/pkg/mm.tar.gz"; mmenv=(-e MM_PACKAGE=/out/pkg/mm.tar.gz); }
docker run --rm --platform linux/amd64 \
  -v "$S/research/oldos/repo-copy:/repo" -v /root/.ccr/ca-bundle.crt:/proxy-ca.crt:ro -v "$out:/out" -v "$S/css34-server.tar.gz:/server.tgz:ro" -v "$S/srv/hl2:/srv-hl2:ro" -v "$S/cache:/cache:ro" \
  -e SERVER_DIR=/out/srv -e CACHE_DIR=/cache "${smenv[@]}" "${mmenv[@]}" -e NOSM="$nosm" \
  -e SM_VERSION_EXPECT="$5" -e MM_VERSION_EXPECT="$6" -e SM_COMMIT_EXPECT="$7" -e MM_COMMIT_EXPECT="$8" \
  -e TIMEOUT_SECS=120 -e SMOKE_CONDEBUG=1 -e SMOKE_VERBOSE=1 \
  "$image" bash -lc '
    set -euo pipefail
    mkdir -p /out/srv && tar -xzf /server.tgz -C /out/srv --exclude=./hl2 && ln -s /srv-hl2 /out/srv/hl2
    if [ -f /etc/redhat-release ]; then cp /proxy-ca.crt /etc/pki/ca-trust/source/anchors/proxy-ca.crt && update-ca-trust; fi
    /repo/testing/scripts/install-deps.sh >/out/deps.log 2>&1 || { echo DEPS_FAIL; tail -20 /out/deps.log; exit 3; }
    /repo/testing/scripts/install-addons.sh >/out/addons.log 2>&1
    if [[ "$NOSM" == 1 ]]; then rm -f /out/srv/cstrike/addons/metamod/sourcemod.vdf; echo "NOSM: removed sourcemod.vdf"; fi
    { grep PRETTY /etc/os-release; ldd --version 2>&1 | sed -n 1p; } | sed "s/^/OSINFO: /" || true
    /repo/testing/scripts/smoke-test.sh
  ' > "$out/run.log" 2>&1
rc=$?
# keep logs, drop the big tree
for f in console-probe.log smoke.log; do [ -f "$out/srv/$f" ] && cp "$out/srv/$f" "$out/"; done
cp -r "$out/srv/cstrike/addons/sourcemod/logs" "$out/sm-logs" 2>/dev/null
find "$out/srv" -name "*fatal*" -exec cp {} "$out/" \; 2>/dev/null; find "$out/srv/cstrike/addons/metamod" -maxdepth 2 -name "*.log" -exec cp {} "$out/" \; 2>/dev/null
rm -rf "$out/srv"
echo "== $name ($image) rc=$rc"
grep -E "^OSINFO|^FAIL|free\(\)|invalid pointer|Aborted|Segmentation|GLIBC_|not found|srcds exited|DEPS_FAIL|Package ABI|Mapchange to|Smoke test" "$out/run.log" | sort | uniq -c | head -15
grep -cE "^OK" "$out/run.log" | sed 's/^/  OK-count: /'
exit $rc
