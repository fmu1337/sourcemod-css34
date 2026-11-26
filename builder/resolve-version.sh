#!/usr/bin/env bash
# Resolve SOURCEMOD_* / MMS_* (the primary Metamod) from CSS34_LINE.
# Builders also call css34_require_buildable: master builds SourceMod 1.12+ only.
set -euo pipefail

builder_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$builder_dir/versions.env"

# Aliases for a line name; CSS34_LINE is always the canonical name afterwards
# (it is written to css34-package.json "line").
css34_canonical_line() {
  case "$1" in
    sm12|latest) echo sm12-latest ;;
    sm13|bleeding) echo sm13-latest ;;
    sm11|oldstable) echo sm11-oldstable ;;
    sm13-mm2) echo sm13-mm20 ;;
    sm13-khook|khook) echo sm13-mm20-khook ;;
    *) echo "$1" ;;
  esac
}

pin_field() {
  local name="$1_$2"
  printf '%s' "${!name:-}"
}

# The line -> pin table is css34_line_pins in versions.env, generated from
# lines.json: there is no second copy here.
apply_sm_line() {
  local line="$1" pins sm_pin mm_pin status
  if ! pins="$(css34_line_pins "$line")"; then
    echo "Unknown CSS34_LINE='$line' (lines in builder/lines.json)" >&2
    exit 1
  fi
  read -r sm_pin mm_pin status <<<"$pins"
  if [[ "$status" == retired || "$(pin_field "$mm_pin" MODE)" == 2.* ]]; then
    echo "This build line is archived; use the archive/khook branch" >&2
    exit 1
  fi
  # Frozen lines (T2.7) resolve only for the expectations of their published
  # packages (smoke, package names); css34_require_buildable refuses them.
  SOURCEMOD_COMMIT="$(pin_field "$sm_pin" COMMIT)"
  SOURCEMOD_GIT_REV="$(pin_field "$sm_pin" REV)"
  SOURCEMOD_MAJOR="$(pin_field "$sm_pin" MAJOR)"
  MMS_COMMIT="$(pin_field "$mm_pin" COMMIT)"
  MMS_BRANCH="$(pin_field "$mm_pin" BRANCH)"
  MMS_DIRNAME="$(pin_field "$mm_pin" DIRNAME)"
  MMS_MODE="$(pin_field "$mm_pin" MODE)"
  MMS_GIT_REV="$(pin_field "$mm_pin" REV)"
  CSS34_LINE_STATUS="$status"
}

# versions.env defaults CSS34_LINE to lines.json's default_line.
CSS34_LINE="$(css34_canonical_line "${CSS34_LINE:-sm13-latest}")"
apply_sm_line "$CSS34_LINE"

css34_require_buildable() {
  if [[ "$CSS34_LINE_STATUS" != active || "$SOURCEMOD_MAJOR" -lt 12 ]]; then
    echo "FAIL: ${CSS34_LINE} (SourceMod 1.${SOURCEMOD_MAJOR}) is ${CSS34_LINE_STATUS}: master builds active" \
      "SourceMod 1.12+ lines only; rebuild a frozen line from its freeze tag and input archive (docs/MAINTAINING.md)" >&2
    return 1
  fi
}

export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV SOURCEMOD_MAJOR
MMS_GIT_REV="${MMS_GIT_REV:-}"
export MMS_COMMIT MMS_BRANCH MMS_DIRNAME MMS_MODE MMS_GIT_REV
export CSS34_LINE CSS34_LINE_STATUS

echo "==> CSS34_LINE=${CSS34_LINE} SM=${SOURCEMOD_GIT_REV} (${SOURCEMOD_COMMIT:0:9}) MM=${MMS_MODE} (${MMS_COMMIT:0:9})" >&2
