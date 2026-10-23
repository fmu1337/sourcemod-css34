#!/usr/bin/env bash
# Smoke (+ extra dual probe) for the dual-build research.
# Based on research/oldos/scripts/run-case-lite.sh; uses research/dual-build/repo-copy
# (install-deps fixes for old images + dual-extra-probe.exp).
# usage: run-dual.sh <name> <image> <sm.tgz> <mm.tgz> <sm_ver> <mm_ver> <sm_commit> <mm_commit>
set -uo pipefail
S=/tmp/claude-0/-home-user-sourcemod-css34/ffbe8980-eece-56cf-8782-bc5e5af6297c/scratchpad
B=$S/research/dual-build
name="$1" image="$2" sm="$3" mm="$4"
out="$B/runs/$name"; rm -rf "$out"; mkdir -p "$out/pkg"
cp -f "$sm" "$out/pkg/sm.tar.gz"; cp -f "$mm" "$out/pkg/mm.tar.gz"
docker run --rm --platform linux/amd64 \
  -v "$B/repo-copy:/repo" -v /root/.ccr/ca-bundle.crt:/proxy-ca.crt:ro -v "$out:/out" \
  -v "$S/css34-server.tar.gz:/server.tgz:ro" -v "$S/srv/hl2:/srv-hl2:ro" -v "$S/cache:/cache:ro" \
  -e SERVER_DIR=/out/srv -e CACHE_DIR=/cache -e SM_PACKAGE=/out/pkg/sm.tar.gz -e MM_PACKAGE=/out/pkg/mm.tar.gz \
  -e SM_VERSION_EXPECT="$5" -e MM_VERSION_EXPECT="$6" -e SM_COMMIT_EXPECT="$7" -e MM_COMMIT_EXPECT="$8" \
  -e TIMEOUT_SECS=120 -e SMOKE_CONDEBUG=1 -e SMOKE_VERBOSE=1 -e MAP2=de_inferno \
  "$image" bash -lc '
    set -euo pipefail
    mkdir -p /out/srv && tar -xzf /server.tgz -C /out/srv --exclude=./hl2 && ln -s /srv-hl2 /out/srv/hl2
    if [ -f /etc/redhat-release ]; then cp /proxy-ca.crt /etc/pki/ca-trust/source/anchors/proxy-ca.crt && update-ca-trust; fi
    /repo/testing/scripts/install-deps.sh >/out/deps.log 2>&1 || { echo DEPS_FAIL; tail -20 /out/deps.log; exit 3; }
    /repo/testing/scripts/install-addons.sh >/out/addons.log 2>&1
    { grep PRETTY /etc/os-release; ldd --version 2>&1 | sed -n 1p; } | sed "s/^/OSINFO: /" || true
    ls /out/srv/cstrike/addons/metamod/bin /out/srv/cstrike/addons/sourcemod/bin | sed "s/^/LAYOUT: /"
    rc=0; /repo/testing/scripts/smoke-test.sh || rc=$?
    echo "SMOKE_RC=$rc"
    cp -r /out/srv/cstrike/addons/sourcemod/logs /out/sm-logs-smoke 2>/dev/null || true
    rm -f /out/srv/cstrike/addons/sourcemod/logs/*.log
    erc=0; EXTRA_PROBE_LOG=/out/extra-probe.log timeout 700 /usr/bin/expect /repo/testing/scripts/dual-extra-probe.exp > /out/extra-run.log 2>&1 || erc=$?
    echo "EXTRA_RC=$erc"
    exit $rc
  ' > "$out/run.log" 2>&1
rc=$?
for f in console-probe.log smoke.log; do [ -f "$out/srv/$f" ] && cp "$out/srv/$f" "$out/"; done
cp -r "$out/srv/cstrike/addons/sourcemod/logs" "$out/sm-logs-extra" 2>/dev/null
cp "$out/srv/cstrike/console.log" "$out/console-extra.log" 2>/dev/null
find "$out/srv" -name "*fatal*" -exec cp {} "$out/" \; 2>/dev/null
rm -rf "$out/srv"
echo "== $name ($image) rc=$rc"
grep -E "^OSINFO|^FAIL|SMOKE_RC|EXTRA_RC|free\(\)|invalid pointer|Aborted|Segmentation|GLIBC_|srcds exited|DEPS_FAIL|Mapchange to|Smoke test" "$out/run.log" | sort | uniq -c | head -20
grep -cE "^OK" "$out/run.log" | sed 's/^/  OK-count: /'
grep -E "EXTRA" "$out/extra-run.log" 2>/dev/null | head
exit $rc
