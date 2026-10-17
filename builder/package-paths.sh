#!/usr/bin/env bash
# Source to resolve exact Linux archive paths for the selected build line.
# This does not require the packages to exist (local runners may use URLs).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-version.sh"

case "$MMS_MODE" in
  1.10) package_mm_version=1.10.7 ;;
  1.12) package_mm_version=1.12.0 ;;
  *) echo "Unsupported package MM mode: $MMS_MODE" >&2; return 1 ;;
esac
SM_PACKAGE="${PACKAGES_DIR:-packages}/sourcemod-1.${SOURCEMOD_MAJOR}.0-git${SOURCEMOD_GIT_REV}-css34-linux.tar.gz"
MM_PACKAGE="${PACKAGES_DIR:-packages}/mmsource-${package_mm_version}-git${MMS_GIT_REV}-css34-linux.tar.gz"
export SM_PACKAGE MM_PACKAGE
unset package_mm_version
