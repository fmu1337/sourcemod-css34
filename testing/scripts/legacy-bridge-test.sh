#!/usr/bin/env bash
# T2.9 legacy-plugin bridge: a PLAPI 11 Metamod plugin must run on metamod.2.ep1
# (MM 1.12) through the nested metamod.1.ep1, next to SourceMod, without
# removing any Metamod binary.
#
# Usage: SERVER_DIR=<srcds root with the MM 1.12 package and SourceMod installed> \
#        LEGACY_PROBE=<packages/test-plugins/css34_legacy_probe.so> legacy-bridge-test.sh
#
# The probe (testing/plugins/css34_legacy_probe) logs its events to
# addons/metamod/css34_legacy_probe.log. metaplugins.ini is restored afterwards.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
LEGACY_PROBE="${LEGACY_PROBE:?LEGACY_PROBE is required}"
mm="${SERVER_DIR}/cstrike/addons/metamod"
session="${LEGACY_BRIDGE_LOG:-${SERVER_DIR}/legacy-bridge.log}"
events="${mm}/css34_legacy_probe.log"
fail=0

die() { echo "FAIL: $*" >&2; exit 1; }
check() { # pattern file label
  if grep -Eq -- "$1" "$2"; then
    echo "OK: $3"
  else
    echo "FAIL: $3 (no line matching: $1)" >&2
    fail=1
  fi
}

[[ -f "${LEGACY_PROBE}" ]] || die "probe plugin not found: ${LEGACY_PROBE}"
for core in metamod.2.ep1.so metamod.1.ep1.so; do
  [[ -f "${mm}/bin/${core}" ]] || die "${mm}/bin/${core} missing: install the MM 1.12 package with the legacy core"
done

cp -f "${LEGACY_PROBE}" "${mm}/css34_legacy_probe.so"
rm -f "${events}"
cp -p "${mm}/metaplugins.ini" "${mm}/metaplugins.ini.legacy-bridge"
trap 'mv -f "${mm}/metaplugins.ini.legacy-bridge" "${mm}/metaplugins.ini"; rm -f "${mm}/css34_legacy_probe.so"' EXIT
printf '%s\n' "addons/metamod/css34_legacy_probe.so" >>"${mm}/metaplugins.ini"

echo "==> Booting srcds with the PLAPI 11 probe in metaplugins.ini"
SERVER_DIR="${SERVER_DIR}" LEGACY_BRIDGE_LOG="${session}" /usr/bin/expect "${root}/testing/scripts/legacy-bridge.exp" \
  || echo "WARN: expect session returned $? (judged from the logs below)"

echo "==== legacy-bridge session (Metamod lines) ===="
grep -E 'META|CSS34|Legacy|Plugin|plugin|SourceMod Version' "${session}" | tail -n 40 || true
echo "==== ${events##*/} ===="
cat "${events}" 2>/dev/null || echo "(missing)"

check 'Started metamod\.1\.ep1\.so for PLAPI 7-12 plugins' "${session}" "metamod.2.ep1 started the nested legacy core"
check 'Old plugin ".*css34_legacy_probe\.so" \(PLAPI 11\) runs in metamod\.1\.ep1\.so' "${session}" "the probe runs as an old plugin"
check '\] CSS34 Legacy Probe' "${session}" "meta list shows the probe"
check 'SourceMod Version: ' "${session}" "SourceMod (2.ep1) still answers"
if [[ -f "${events}" ]]; then
  check '^load api=11 late=0$' "${events}" "the probe loaded with PLAPI 11 at startup"
  check '^all_loaded$' "${events}" "the probe got AllPluginsLoaded"
  check '^level_init map=de_dust2$' "${events}" "its SourceHook v4 LevelInit hook fired"
  check '^unload$' "${events}" "meta unload reached the probe"
else
  echo "FAIL: the probe wrote no ${events##*/}" >&2
  fail=1
fi
if grep -q 'Older Metamod version required' "${session}"; then
  echo "FAIL: metamod.2.ep1 refused the old plugin" >&2
  fail=1
fi

[[ "${fail}" -eq 0 ]] && echo "Legacy-plugin bridge test PASSED"
exit "${fail}"
