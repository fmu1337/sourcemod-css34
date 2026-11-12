#!/usr/bin/env bash
# Botplay gate for plugins built by old compilers (testing/plugins/legacy-smx/)
# and for plugin load / forward errors in general.
#
# usage: check-legacy-plugins.sh BOTPLAY_LOG LOG_FILE...
#   BOTPLAY_LOG  the srcds console transcript (sm plugins list output)
#   LOG_FILE...  SourceMod logs (L*.log, errors_*.log) and cstrike/console.log
#
# Fails on
#  - a plugin listed as <Failed> or <Error> by "sm plugins list", or an
#    "Errors:" section in it;
#  - 'Native "..." was not found', 'Unable to load plugin', 'Failed to load
#    plugin', and forward/call argument errors ("Invalid parameter or parameter
#    type", "Maximum number of parameters reached") in any log;
#  - an exception blamed on a legacy plugin;
#  - a legacy stock plugin missing from the plugin list (matched by the
#    "(<SOURCEMOD_VERSION of its compiler>)" version it reports);
#  - css34_legacy_forward_probe: fewer than LEGACY_FWD_MIN_COMPILERS copies
#    reporting, a copy with fail/bad_args > 0, ok < LEGACY_FWD_MIN_OK or fewer
#    than LEGACY_FWD_MIN_COMPILERS listeners;
#  - with LEGACY_FWD_REQUIRE_VARARGS=1 only: a Param_VarArgs forward call that
#    errors or does not run (reported as INFO otherwise).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LEGACY_DIR="${LEGACY_DIR:-${ROOT}/testing/plugins/legacy-smx}"
BOTPLAY_LOG="${1:?BOTPLAY_LOG is required}"
shift
LOGS=("$@")
LEGACY_FWD_MIN_OK="${LEGACY_FWD_MIN_OK:-4}"

failed=0
fail() { echo "FAIL: $*" >&2; failed=1; }
final_plugins=""

# --- sm plugins list --------------------------------------------------------
if [[ ! -f "${BOTPLAY_LOG}" ]]; then
  fail "botplay log ${BOTPLAY_LOG} missing"
else
  # Check the last snapshot on its own: summing the boot and final listings
  # can let two sightings of one plugin hide another plugin's disappearance.
  final_plugins="$(tr -d '\r' <"${BOTPLAY_LOG}" | awk '
    /\[SM\] (Listing [0-9]+ plugins?:|No plugins loaded)/ { listing=""; found=1 }
    found { listing=listing $0 ORS }
    END { printf "%s", listing }
  ')"
  [[ -n "${final_plugins}" ]] || fail "no sm plugins list snapshot found"
  if tr -d '\r' <"${BOTPLAY_LOG}" | grep -qE '^[[:space:]]*Errors:[[:space:]]*$'; then
    fail "Errors: section in sm plugins list"
  fi
  bad_plugins="$(tr -d '\r' <"${BOTPLAY_LOG}" | grep -E '^[[:space:]]*[0-9]+ <(Failed|Error)>' || true)"
  if [[ -n "${bad_plugins}" ]]; then
    fail "plugin(s) listed as <Failed>/<Error>:"
    printf '%s\n' "${bad_plugins}" >&2
    tr -d '\r' <"${BOTPLAY_LOG}" | grep -A20 -E '^Errors:$' | head -n 40 >&2 || true
  else
    echo "OK: no <Failed>/<Error> plugins in sm plugins list"
  fi
fi

# --- SourceMod logs ---------------------------------------------------------
existing=()
for f in ${LOGS[@]+"${LOGS[@]}"}; do
  [[ -f "${f}" ]] && existing+=("${f}")
done
if [[ ${#existing[@]} -eq 0 ]]; then
  fail "no SourceMod logs to check"
else
  error_re='Native "[^"]+" was not found|Unable to load plugin|Failed to load plugin|Invalid parameter or parameter type|Maximum number of parameters reached'
  matches="$(grep -hE -- "${error_re}" "${existing[@]}" 2>/dev/null | sort | uniq -c | head -n 40 || true)"
  if [[ -n "${matches}" ]]; then
    fail "plugin load / native / forward argument errors in SourceMod logs:"
    printf '%s\n' "${matches}" >&2
  else
    echo "OK: no missing natives, plugin load or forward argument errors in SourceMod logs"
  fi
fi

# --- legacy plugins -----------------------------------------------------------
legacy_names=()
declare -A stock_per_version=()
while IFS=$'\t' read -r ver source installed_as; do
  [[ -z "${ver}" || "${ver}" == \#* ]] && continue
  legacy_names+=("${installed_as%.smx}")
  if [[ "${source}" != css34_legacy_forward_probe ]]; then
    stock_per_version["${ver}"]=$(( ${stock_per_version["${ver}"]:-0} + 1 ))
  fi
done <"${LEGACY_DIR}/plugins.tsv"

if [[ ${#existing[@]} -gt 0 ]]; then
  blame_re="Blaming: ($(IFS='|'; echo "${legacy_names[*]}"))\.smx"
  blamed="$(grep -hE -B3 -A6 -- "${blame_re}" "${existing[@]}" 2>/dev/null | head -n 60 || true)"
  if [[ -n "${blamed}" ]]; then
    fail "exception(s) in legacy plugins:"
    printf '%s\n' "${blamed}" >&2
  else
    echo "OK: no exceptions blamed on legacy plugins"
  fi
fi

compilers=()
for ver in "${!stock_per_version[@]}"; do
  spver="$(awk '{ print $NF }' "${LEGACY_DIR}/${ver}/SPCOMP_VERSION")"
  compilers+=("${spver}")
  want="${stock_per_version[${ver}]}"
  have=0
  if [[ -n "${final_plugins}" ]]; then
    have="$(grep -E '^[[:space:]]*[0-9]+ "' <<<"${final_plugins}" | sort -u | grep -cF "(${spver})" || true)"
  fi
  if [[ "${have}" -ge "${want}" ]]; then
    echo "OK: ${want} stock plugin(s) built by spcomp ${spver} listed as running"
  else
    fail "expected ${want} running stock plugin(s) built by spcomp ${spver}, found ${have}"
  fi
done

LEGACY_FWD_MIN_COMPILERS="${LEGACY_FWD_MIN_COMPILERS:-$(( ${#compilers[@]} + 1 ))}"
probe_lines=""
if [[ ${#existing[@]} -gt 0 ]]; then
  probe_lines="$(grep -hE '\[css34_legacy_fwd\] compiler=[^ ]+ round=' "${existing[@]}" 2>/dev/null || true)"
fi
reported=0
while IFS= read -r compiler; do
  [[ -z "${compiler}" ]] && continue
  reported=$((reported + 1))
  last="$(grep -F "compiler=${compiler} round=" <<<"${probe_lines}" | tail -n1)"
  field() { grep -Eo " $1=[0-9]+" <<<"${last}" | grep -Eo '[0-9]+' | tail -n1; }
  ok="$(field ok)"; fl="$(field fail)"; lst="$(field listeners)"; bad="$(field bad_args)"
  if [[ "${ok:-0}" -ge "${LEGACY_FWD_MIN_OK}" && "${fl:-1}" -eq 0 && "${bad:-1}" -eq 0 \
        && "${lst:-0}" -ge "${LEGACY_FWD_MIN_COMPILERS}" ]]; then
    echo "OK: legacy forward probe compiler=${compiler} ok=${ok} fail=0 bad_args=0 listeners=${lst}"
  else
    fail "legacy forward probe compiler=${compiler}: ${last}"
  fi
done < <(grep -Eo 'compiler=[^ ]+' <<<"${probe_lines}" | cut -d= -f2 | sort -u)
for spver in "${compilers[@]}"; do
  if ! grep -qF "compiler=${spver} round=" <<<"${probe_lines}"; then
    fail "no [css34_legacy_fwd] line from the copy built by spcomp ${spver}"
  fi
done
if [[ "${reported}" -lt "${LEGACY_FWD_MIN_COMPILERS}" ]]; then
  fail "legacy forward probe: ${reported} compiler(s) reported, expected ${LEGACY_FWD_MIN_COMPILERS}"
fi
probe_errors=""
if [[ ${#existing[@]} -gt 0 ]]; then
  probe_errors="$(grep -hE '\[css34_legacy_fwd\].*(FAIL|bad (global|private) args| err=)' "${existing[@]}" 2>/dev/null | head -n 20 || true)"
fi
if [[ -n "${probe_errors}" ]]; then
  fail "legacy forward probe errors:"
  printf '%s\n' "${probe_errors}" >&2
fi

# Varargs forwards (Param_VarArgs, pre-1.13 includes only): SourceMod 1.13 has
# none; report what the core does with them, enforce on request.
varargs_lines=""
if [[ ${#existing[@]} -gt 0 ]]; then
  varargs_lines="$(grep -hE '\[css34_legacy_fwd\] compiler=[^ ]+ varargs ' "${existing[@]}" 2>/dev/null || true)"
fi
if [[ "${LEGACY_FWD_REQUIRE_VARARGS:-0}" == "1" ]]; then
  for spver in "${compilers[@]}"; do
    if ! grep -qF "compiler=${spver} varargs " <<<"${varargs_lines}"; then
      fail "no varargs forward results from spcomp ${spver}"
    fi
  done
fi
while IFS= read -r compiler; do
  [[ -z "${compiler}" ]] && continue
  last="$(grep -F "compiler=${compiler} varargs " <<<"${varargs_lines}" | tail -n1)"
  summary="${last#*varargs }"
  vfield() { grep -Eo "(^| )$1=[0-9]+" <<<"${summary}" | grep -Eo '[0-9]+' | tail -n1; }
  if [[ "${LEGACY_FWD_REQUIRE_VARARGS:-0}" == "1" ]]; then
    if [[ "$(vfield errors)" == "0" && "$(vfield runs)" == "$(vfield calls)" ]]; then
      echo "OK: varargs forward compiler=${compiler}: ${summary}"
    else
      fail "varargs forward compiler=${compiler}: ${summary}"
    fi
  else
    echo "INFO: varargs forward compiler=${compiler}: ${summary} (not enforced, LEGACY_FWD_REQUIRE_VARARGS=1 to require runs=calls errors=0)"
  fi
done < <(grep -Eo 'compiler=[^ ]+ varargs' <<<"${varargs_lines}" | cut -d= -f2 | cut -d' ' -f1 | sort -u)

if [[ "${failed}" -ne 0 ]]; then
  echo "Legacy plugin check FAILED" >&2
  exit 1
fi
echo "Legacy plugin check PASSED"
