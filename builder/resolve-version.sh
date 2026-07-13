#!/usr/bin/env bash
# Resolve SOURCEMOD_COMMIT / SOURCEMOD_GIT_REV from profile or explicit overrides.
set -euo pipefail

builder_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$builder_dir/versions.env"

if [ -n "${SOURCEMOD_COMMIT:-}" ] && [ -n "${SOURCEMOD_GIT_REV:-}" ]; then
  export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV
  exit 0
fi

case "${SOURCEMOD_PROFILE:-stable}" in
  experimental)
    export SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:-$SOURCEMOD_EXPERIMENTAL_COMMIT}"
    export SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV:-$SOURCEMOD_EXPERIMENTAL_REV}"
    ;;
  mid|6588)
    export SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:-$SOURCEMOD_MID_COMMIT}"
    export SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV:-$SOURCEMOD_MID_REV}"
    ;;
  stable|*)
    export SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:-$SOURCEMOD_STABLE_COMMIT}"
    export SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV:-$SOURCEMOD_STABLE_REV}"
    ;;
esac
