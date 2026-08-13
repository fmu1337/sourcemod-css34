#!/usr/bin/env bash
# Resolve SOURCEMOD_* / MMS_* from CSS34_LINE or explicit env overrides.
set -euo pipefail

builder_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$builder_dir/versions.env"

resolve_mm() {
  local mode="$1"
  case "$mode" in
    1.10)
      MMS_COMMIT="$MM_110_COMMIT"; MMS_BRANCH="$MM_110_BRANCH"
      MMS_DIRNAME="$MM_110_DIRNAME"; MMS_MODE="$MM_110_MODE"
      ;;
    1.11)
      MMS_COMMIT="$MM_111_COMMIT"; MMS_BRANCH="$MM_111_BRANCH"
      MMS_DIRNAME="$MM_111_DIRNAME"; MMS_MODE="$MM_111_MODE"
      ;;
    1.12)
      MMS_COMMIT="$MM_112_COMMIT"; MMS_BRANCH="$MM_112_BRANCH"
      MMS_DIRNAME="$MM_112_DIRNAME"; MMS_MODE="$MM_112_MODE"
      ;;
    2.0)
      MMS_COMMIT="$MM_20_COMMIT"; MMS_BRANCH="$MM_20_BRANCH"
      MMS_DIRNAME="$MM_20_DIRNAME"; MMS_MODE="$MM_20_MODE"
      ;;
    *)
      echo "Unknown MM mode '$mode'" >&2
      exit 1
      ;;
  esac
}

apply_sm_line() {
  local line="$1"
  case "$line" in
    sm11-oldstable|sm11|oldstable)
      SOURCEMOD_COMMIT="$SM_OLDSTABLE_COMMIT"
      SOURCEMOD_GIT_REV="$SM_OLDSTABLE_REV"
      SOURCEMOD_MAJOR="$SM_OLDSTABLE_MAJOR"
      resolve_mm 1.10
      ;;
    sm12-latest|sm12|latest)
      SOURCEMOD_COMMIT="$SM_LATEST_COMMIT"
      SOURCEMOD_GIT_REV="$SM_LATEST_REV"
      SOURCEMOD_MAJOR="$SM_LATEST_MAJOR"
      resolve_mm 1.12
      ;;
    sm13-dev|sm13|dev)
      SOURCEMOD_COMMIT="$SM_DEV_COMMIT"
      SOURCEMOD_GIT_REV="$SM_DEV_REV"
      SOURCEMOD_MAJOR="$SM_DEV_MAJOR"
      resolve_mm 1.12
      ;;
    sm13-mm20|sm13-mm2)
      SOURCEMOD_COMMIT="$SM_DEV_COMMIT"
      SOURCEMOD_GIT_REV="$SM_DEV_REV"
      SOURCEMOD_MAJOR="$SM_DEV_MAJOR"
      resolve_mm 2.0
      ;;
    sm11-mm111)
      SOURCEMOD_COMMIT="$SM_OLDSTABLE_COMMIT"
      SOURCEMOD_GIT_REV="$SM_OLDSTABLE_REV"
      SOURCEMOD_MAJOR="$SM_OLDSTABLE_MAJOR"
      resolve_mm 1.11
      ;;
    *)
      echo "Unknown CSS34_LINE='$line' (expected sm11-oldstable|sm12-latest|sm13-dev|sm13-mm20|sm11-mm111)" >&2
      exit 1
      ;;
  esac
}

line="${CSS34_LINE:-}"
if [[ -n "$line" ]]; then
  apply_sm_line "$line"
elif [[ -n "${SOURCEMOD_COMMIT:-}" && -n "${SOURCEMOD_GIT_REV:-}" ]]; then
  SOURCEMOD_MAJOR="${SOURCEMOD_MAJOR:-}"
  if [[ -z "$SOURCEMOD_MAJOR" ]]; then
    if [[ "$SOURCEMOD_GIT_REV" -ge 7300 ]]; then SOURCEMOD_MAJOR=13
    elif [[ "$SOURCEMOD_GIT_REV" -ge 7000 ]]; then SOURCEMOD_MAJOR=12
    else SOURCEMOD_MAJOR=11
    fi
  fi
  if [[ -z "${MMS_COMMIT:-}" || -z "${MMS_DIRNAME:-}" || -z "${MMS_MODE:-}" ]]; then
    if [[ -n "${MMS_LINE:-}" ]]; then
      case "${MMS_LINE}" in
        1.10|mm110|mm10) resolve_mm 1.10 ;;
        1.11|mm111|mm11) resolve_mm 1.11 ;;
        1.12|mm112|mm12) resolve_mm 1.12 ;;
        2.0|mm20|mm2) resolve_mm 2.0 ;;
        *) echo "Unknown MMS_LINE='${MMS_LINE}'" >&2; exit 1 ;;
      esac
    elif [[ "$SOURCEMOD_MAJOR" -ge 12 ]]; then
      resolve_mm 1.12
    else
      resolve_mm 1.10
    fi
  fi
else
  apply_sm_line "${CSS34_LINE:-sm13-dev}"
fi

# Optional MMS_LINE override after a SM line was chosen.
if [[ -n "${MMS_LINE:-}" && -n "${CSS34_LINE:-}" ]]; then
  case "${MMS_LINE}" in
    1.10|mm110|mm10) resolve_mm 1.10 ;;
    1.11|mm111|mm11) resolve_mm 1.11 ;;
    1.12|mm112|mm12) resolve_mm 1.12 ;;
    2.0|mm20|mm2) resolve_mm 2.0 ;;
  esac
fi

export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV SOURCEMOD_MAJOR
export MMS_COMMIT MMS_BRANCH MMS_DIRNAME MMS_MODE
export CSS34_LINE="${CSS34_LINE:-custom}"

echo "==> CSS34_LINE=${CSS34_LINE} SM=${SOURCEMOD_GIT_REV} (${SOURCEMOD_COMMIT:0:9}) MM=${MMS_MODE} (${MMS_COMMIT:0:9})" >&2
