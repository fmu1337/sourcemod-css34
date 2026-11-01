#!/usr/bin/env bash
# Validate core PLAPI with the actual game server providers.
# Linux: gcc -m32 probe against sourcemod.<core>.so. Windows (Git Bash on the
# windows-2022 runner, MSVC x86 environment): cl probe against sourcemod.<core>.dll.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
server="${SERVER_DIR:?SERVER_DIR required}"
server="$(cd "$server" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    ext=dll
    probe="$work/plapi-probe.exe"
    # cl takes /switches; keep MSYS from rewriting its arguments
    (cd "$work" && MSYS2_ARG_CONV_EXCL='*' cl -nologo -W3 -WX \
      "$(cygpath -w "$root/testing/tools/plapi-probe.c")" -Fe:plapi-probe.exe >cl.log 2>&1) \
      || { cat "$work/cl.log" >&2; echo "FAIL: cl could not build plapi-probe.c" >&2; exit 1; }
    export PATH="$server/bin:$server:$PATH"
    native() { "$probe" "$(cygpath -w "$1")"; }
    ;;
  *)
    ext=so
    probe="$work/plapi-probe"
    gcc -m32 -Wall -Wextra -Werror "$root/testing/tools/plapi-probe.c" -o "$probe" -ldl
    export LD_LIBRARY_PATH="$server/bin:$server:${LD_LIBRARY_PATH:-}"
    native() { "$probe" "$1"; }
    ;;
esac
for suffix in 1.ep1 2.ep1; do
  module="$server/cstrike/addons/sourcemod/bin/sourcemod.$suffix.$ext"
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
  output="$(native "$module" | tr -d '\r')"
  [[ "$output" == "PLAPI:$expected" ]] || {
    echo "FAIL: $module returned $output, expected PLAPI:$expected" >&2
    exit 1
  }
  echo "OK: $(basename "$module") $output"
done
