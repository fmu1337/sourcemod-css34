#!/usr/bin/env bash
# Validate core PLAPI with the actual game server providers.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
server="${SERVER_DIR:?SERVER_DIR required}"
server="$(cd "$server" && pwd)"
probe="$(mktemp)"
trap 'rm -f "$probe"' EXIT
gcc -m32 -Wall -Wextra -Werror "$root/testing/tools/plapi-probe.c" -o "$probe" -ldl
export LD_LIBRARY_PATH="$server/bin:$server:${LD_LIBRARY_PATH:-}"
for suffix in 1.ep1 2.ep1; do
  module="$server/cstrike/addons/sourcemod/bin/sourcemod.$suffix.so"
  # 1.ep1 exists only in dual packages; 2.ep1 is required in every package.
  if [[ "$suffix" == 1.ep1 && ! -e "$module" ]]; then
    if [[ "${CSS34_LINE:-}" == sm11* ]]; then
      echo "FAIL: ${CSS34_LINE} package has no $(basename "$module")" >&2
      exit 1
    fi
    continue
  fi
  test -f "$module"
  expected=16
  [[ "$suffix" != 1.ep1 ]] || expected=11
  output="$("$probe" "$module")"
  [[ "$output" == "PLAPI:$expected" ]] || {
    echo "FAIL: $module returned $output, expected PLAPI:$expected" >&2
    exit 1
  }
  echo "OK: $(basename "$module") $output"
done
