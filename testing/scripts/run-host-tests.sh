#!/usr/bin/env bash
# Run every host regression test (testing/scripts/test-*.py and test-*.sh),
# then the negative smoke check, and print a summary. New tests are picked up
# automatically. Optional arguments name tests (file names or paths) to run
# instead of the full set; the negative smoke check then runs only when
# "negative-smoke" is among them.
#
# Not -e: every test runs and all failures are reported at the end.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
SCRIPTS=testing/scripts

names=()
statuses=()
secs=()
failed=()

record() { # name status seconds
  names+=("$1")
  statuses+=("$2")
  secs+=("$3")
  [ "$2" = PASS ] || failed+=("$1")
}

run_test() {
  local path=$1 name start rc dur runner
  name=$(basename "$path")
  case $name in
    *.py) runner=python3 ;;
    *) runner=bash ;;
  esac
  echo "::group::$name"
  start=$SECONDS
  timeout 1800 "$runner" "$path"
  rc=$?
  dur=$((SECONDS - start))
  if [ "$rc" -eq 0 ]; then
    echo "PASS $name (${dur}s)"
    record "$name" PASS "$dur"
  else
    if [ "$rc" -eq 124 ]; then echo "TIMEOUT after 1800s"; fi
    echo "FAIL $name (exit $rc, ${dur}s)"
    record "$name" FAIL "$dur"
  fi
  echo "::endgroup::"
}

negative_smoke() {
  local dir log start rc dur status=PASS
  dir=$(mktemp -d)
  log="$dir/negative-smoke.log"
  mkdir -p "$dir/absent-css34-server"
  echo "::group::negative-smoke"
  start=$SECONDS
  SERVER_DIR="$dir/absent-css34-server" bash "$SCRIPTS/smoke-test.sh" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ]; then
    echo "smoke-test.sh succeeded with a missing server; it must fail"
    status=FAIL
  elif ! grep -q 'No srcds_i686/i486 binary found' "$log"; then
    echo "expected message 'No srcds_i686/i486 binary found' missing from output"
    status=FAIL
  fi
  dur=$((SECONDS - start))
  echo "$status negative-smoke (${dur}s)"
  echo "::endgroup::"
  rm -rf "$dir"
  record negative-smoke "$status" "$dur"
}

tests=()
want_negative=1
if [ "$#" -gt 0 ]; then
  want_negative=0
  for a in "$@"; do
    if [ "$a" = negative-smoke ]; then
      want_negative=1
    elif [ -f "$a" ]; then
      tests+=("$a")
    elif [ -f "$SCRIPTS/$a" ]; then
      tests+=("$SCRIPTS/$a")
    else
      echo "unknown test: $a" >&2
      exit 2
    fi
  done
else
  while IFS= read -r f; do tests+=("$f"); done < <(
    find "$SCRIPTS" -maxdepth 1 -type f \( -name 'test-*.py' -o -name 'test-*.sh' \) | LC_ALL=C sort
  )
fi

for t in "${tests[@]}"; do
  run_test "$t"
done
if [ "$want_negative" -eq 1 ]; then negative_smoke; fi

echo
printf '%-45s %-6s %7s\n' TEST STATUS SECONDS
for i in "${!names[@]}"; do
  printf '%-45s %-6s %7s\n' "${names[$i]}" "${statuses[$i]}" "${secs[$i]}"
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Host regression tests"
    echo
    echo "| Test | Status | Seconds |"
    echo "| --- | --- | ---: |"
    for i in "${!names[@]}"; do
      echo "| ${names[$i]} | ${statuses[$i]} | ${secs[$i]} |"
    done
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo
  echo "FAILED (${#failed[@]}):"
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
echo
echo "All ${#names[@]} checks passed."
exit 0
