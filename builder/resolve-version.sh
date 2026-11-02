#!/usr/bin/env bash
# Resolve SOURCEMOD_* / MMS_* (the primary Metamod) from CSS34_LINE.
# Builders also call css34_require_buildable: master builds SourceMod 1.12+ only.
set -euo pipefail

builder_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$builder_dir/versions.env"

# Every line's primary Metamod is MM 1.12; a line's MM 1.10 bridge_metamod
# comes from resolve-metamod-pins.py.
use_mm_112() {
  MMS_COMMIT="$MM_112_COMMIT"; MMS_BRANCH="$MM_112_BRANCH"
  MMS_DIRNAME="$MM_112_DIRNAME"; MMS_MODE="$MM_112_MODE"
  MMS_GIT_REV="$MM_112_REV"
}

apply_sm_line() {
  local line="$1"
  case "$line" in
    sm12-latest|sm12|latest)
      SOURCEMOD_COMMIT="$SM_LATEST_COMMIT"
      SOURCEMOD_GIT_REV="$SM_LATEST_REV"
      SOURCEMOD_MAJOR="$SM_LATEST_MAJOR"
      use_mm_112
      ;;
    sm13-latest|sm13|bleeding)
      SOURCEMOD_COMMIT="$SM_LATEST_13_COMMIT"
      SOURCEMOD_GIT_REV="$SM_LATEST_13_REV"
      SOURCEMOD_MAJOR="$SM_LATEST_13_MAJOR"
      use_mm_112
      ;;
    # Frozen (T2.7): resolved only for the expectations of its published
    # packages (smoke, package names). The builder refuses SourceMod < 1.12.
    sm11-oldstable|sm11|oldstable)
      SOURCEMOD_COMMIT="$SM_OLDSTABLE_COMMIT"
      SOURCEMOD_GIT_REV="$SM_OLDSTABLE_REV"
      SOURCEMOD_MAJOR="$SM_OLDSTABLE_MAJOR"
      # D7: its primary Metamod is the frozen MM 1.12 (lines.json "metamod").
      MMS_COMMIT="$MM_112_FROZEN_COMMIT"; MMS_BRANCH="$MM_112_FROZEN_BRANCH"
      MMS_DIRNAME="$MM_112_FROZEN_DIRNAME"; MMS_MODE="$MM_112_FROZEN_MODE"
      MMS_GIT_REV="$MM_112_FROZEN_REV"
      ;;
    sm13-mm20|sm13-mm2|sm13-mm20-khook|sm13-khook|khook)
      echo "This build line is archived; use the archive/khook branch" >&2
      exit 1
      ;;
    *)
      echo "Unknown CSS34_LINE='$line' (expected sm12-latest|sm13-latest)" >&2
      exit 1
      ;;
  esac
}

# versions.env defaults CSS34_LINE to lines.json's default_line.
apply_sm_line "${CSS34_LINE:-sm13-latest}"

css34_require_buildable() {
  if [[ "$SOURCEMOD_MAJOR" -lt 12 ]]; then
    echo "FAIL: ${CSS34_LINE} (SourceMod 1.${SOURCEMOD_MAJOR}) is frozen: master builds SourceMod 1.12+ only;" \
      "rebuild it from its freeze tag and input archive (docs/FREEZE.md)" >&2
    return 1
  fi
}

SOURCEMOD_MERGE_MASTER="${SOURCEMOD_MERGE_MASTER:-}"
SOURCEMOD_BUILD_COMMIT="${SOURCEMOD_BUILD_COMMIT:-}"
export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV SOURCEMOD_MAJOR SOURCEMOD_MERGE_MASTER SOURCEMOD_BUILD_COMMIT
MMS_GIT_REV="${MMS_GIT_REV:-}"
export MMS_COMMIT MMS_BRANCH MMS_DIRNAME MMS_MODE MMS_GIT_REV
export CSS34_LINE

echo "==> CSS34_LINE=${CSS34_LINE} SM=${SOURCEMOD_GIT_REV} (${SOURCEMOD_COMMIT:0:9}) MM=${MMS_MODE} (${MMS_COMMIT:0:9})" >&2
