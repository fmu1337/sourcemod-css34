#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="${1:?package directory required}"
OUTPUT_DIR="${2:?output directory required}"
SOURCEMOD_DIR="${3:?sourcemod directory required}"
BUILDER_DIR="${4:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DEPS_DIR="${5:-$(cd "$BUILDER_DIR/.." && pwd)/deps}"

bash "$BUILDER_DIR/prepare-package.sh" \
  "$PACKAGE_DIR" \
  "$SOURCEMOD_DIR" \
  "$BUILDER_DIR" \
  "$DEPS_DIR"

mkdir -p "$OUTPUT_DIR"

rev="${SOURCEMOD_GIT_REV:-$(git -C "$SOURCEMOD_DIR" rev-list --count HEAD)}"
version="$(tr -d '\r\n' < "$SOURCEMOD_DIR/product.version")"
filename="sourcemod-${version}-git${rev}-css34-linux.tar.gz"
archive="$OUTPUT_DIR/$filename"

required=(
  "addons/metamod/sourcemod.vdf"
  "addons/sourcemod/bin/sourcemod.2.ep1.so"
  "addons/sourcemod/extensions/dbi.mysql.ext.so"
  "addons/sourcemod/extensions/dbi.sqlite.ext.so"
  "addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so"
  "addons/sourcemod/gamedata/core.games/blacklist.plugins.txt"
  "addons/sourcemod/gamedata/core.games/common.games.txt"
  "addons/sourcemod/gamedata/core.games/engine.ep1.txt"
  "addons/sourcemod/gamedata/core.games/master.games.txt"
  "addons/sourcemod/gamedata/funcommands.games.txt"
  "addons/sourcemod/gamedata/sdkhooks.games/common.games.txt"
  "addons/sourcemod/gamedata/sdkhooks.games/game.cstrike.txt"
  "addons/sourcemod/gamedata/sdkhooks.games/master.games.txt"
  "addons/sourcemod/gamedata/sdktools.games/common.games.txt"
  "addons/sourcemod/gamedata/sdktools.games/engine.ep1.txt"
  "addons/sourcemod/gamedata/sdktools.games/game.cstrike.txt"
  "addons/sourcemod/gamedata/sdktools.games/master.games.txt"
  "addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt"
  "addons/sourcemod/gamedata/sm-cstrike.games/master.games.txt"
  "addons/sourcemod/scripting/include/version_auto.inc"
  "cfg/sourcemod/sourcemod.cfg"
)

# Dual 1.ep1 + 2.ep1 packages (SM 1.11) contain both core binaries and extensions.
if [[ -e "$PACKAGE_DIR/addons/sourcemod/bin/sourcemod.1.ep1.so" \
   && -e "$PACKAGE_DIR/addons/sourcemod/bin/sourcemod.2.ep1.so" ]]; then
  required=(
    "addons/metamod/sourcemod.vdf"
    "addons/sourcemod/bin/sourcemod.1.ep1.so"
    "addons/sourcemod/bin/sourcemod.2.ep1.so"
    "addons/sourcemod/extensions/dbi.mysql.ext.so"
    "addons/sourcemod/extensions/dbi.sqlite.ext.so"
    "addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so"
    "addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so"
    "addons/sourcemod/extensions/sdkhooks.ext.1.ep1.so"
    "addons/sourcemod/extensions/sdkhooks.ext.2.ep1.so"
    "addons/sourcemod/extensions/sdktools.ext.1.ep1.so"
    "addons/sourcemod/extensions/sdktools.ext.2.ep1.so"
    "addons/sourcemod/extensions/dhooks.ext.2.ep1.so"
    "addons/sourcemod/gamedata/core.games/blacklist.plugins.txt"
    "addons/sourcemod/gamedata/core.games/common.games.txt"
    "addons/sourcemod/gamedata/core.games/engine.ep1.txt"
    "addons/sourcemod/gamedata/core.games/master.games.txt"
    "addons/sourcemod/gamedata/funcommands.games.txt"
    "addons/sourcemod/gamedata/sdkhooks.games/common.games.txt"
    "addons/sourcemod/gamedata/sdkhooks.games/game.cstrike.txt"
    "addons/sourcemod/gamedata/sdkhooks.games/master.games.txt"
    "addons/sourcemod/gamedata/sdktools.games/common.games.txt"
    "addons/sourcemod/gamedata/sdktools.games/engine.ep1.txt"
    "addons/sourcemod/gamedata/sdktools.games/game.cstrike.txt"
    "addons/sourcemod/gamedata/sdktools.games/master.games.txt"
    "addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt"
    "addons/sourcemod/gamedata/sm-cstrike.games/master.games.txt"
    "addons/sourcemod/scripting/include/version_auto.inc"
    "cfg/sourcemod/sourcemod.cfg"
  )
elif [[ ! -e "$PACKAGE_DIR/addons/sourcemod/bin/sourcemod.2.ep1.so" \
   && -e "$PACKAGE_DIR/addons/sourcemod/bin/sourcemod.1.ep1.so" ]]; then
  required=(
    "addons/metamod/sourcemod.vdf"
    "addons/sourcemod/bin/sourcemod.1.ep1.so"
    "addons/sourcemod/extensions/dbi.mysql.ext.so"
    "addons/sourcemod/extensions/dbi.sqlite.ext.so"
    "addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so"
    "addons/sourcemod/gamedata/core.games/blacklist.plugins.txt"
    "addons/sourcemod/gamedata/core.games/common.games.txt"
    "addons/sourcemod/gamedata/core.games/engine.ep1.txt"
    "addons/sourcemod/gamedata/core.games/master.games.txt"
    "addons/sourcemod/gamedata/funcommands.games.txt"
    "addons/sourcemod/gamedata/sdkhooks.games/common.games.txt"
    "addons/sourcemod/gamedata/sdkhooks.games/game.cstrike.txt"
    "addons/sourcemod/gamedata/sdkhooks.games/master.games.txt"
    "addons/sourcemod/gamedata/sdktools.games/common.games.txt"
    "addons/sourcemod/gamedata/sdktools.games/engine.ep1.txt"
    "addons/sourcemod/gamedata/sdktools.games/game.cstrike.txt"
    "addons/sourcemod/gamedata/sdktools.games/master.games.txt"
    "addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt"
    "addons/sourcemod/gamedata/sm-cstrike.games/master.games.txt"
    "addons/sourcemod/scripting/include/version_auto.inc"
    "cfg/sourcemod/sourcemod.cfg"
  )
fi

for rel in "${required[@]}"; do
  if [ ! -e "$PACKAGE_DIR/$rel" ]; then
    echo "Missing required package file: $rel" >&2
    exit 1
  fi
done

python3 "$BUILDER_DIR/../testing/scripts/check-css34-gamedata.py" \
  "$PACKAGE_DIR/addons/sourcemod/gamedata" --source "$SOURCEMOD_DIR"

sdkhooks_master="$PACKAGE_DIR/addons/sourcemod/gamedata/sdkhooks.games/master.games.txt"
if ! grep -Fq '"game.cstrike.txt"' "$sdkhooks_master"; then
  echo "SDKHooks master.games.txt does not load CS:S v34 gamedata" >&2
  exit 1
fi

if [[ -e "$PACKAGE_DIR/addons/sourcemod/bin/sourcemod.1.ep1.so" && "${MMS_MODE:-}" == "1.10" ]]; then
  mm_binary=metamod.1.ep1
else
  mm_binary=metamod.2.ep1
fi
SOURCEMOD_DIR="$SOURCEMOD_DIR" SOURCEMOD_GIT_REV="$rev" \
  bash "$BUILDER_DIR/write-package-manifest.sh" \
  "$PACKAGE_DIR/addons/sourcemod/css34-package.json" "$mm_binary"

tar -C "$PACKAGE_DIR" -czf "$archive" addons cfg
echo "$archive"
