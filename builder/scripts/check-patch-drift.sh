#!/usr/bin/env bash
#
# check-patch-drift.sh - Dry-run a css34 patch series on another upstream commit
#
# Usage:
#   builder/scripts/check-patch-drift.sh --dir <path> [--series <series>]
#   builder/scripts/check-patch-drift.sh --sm-commit <commit|rev> [--line <line>]
#   builder/scripts/check-patch-drift.sh --mm-commit <commit> [--series MM_112]
#   builder/scripts/check-patch-drift.sh --range <old>..<new> [--line <line>]
#   builder/scripts/check-patch-drift.sh --check-pins
#   builder/scripts/check-patch-drift.sh --help
#
# T3.4: the patches are git series (builder/patches/series/<line or MM pin>/).
# A drift check applies each patch to a copy of the target with
# `git apply --3way`, the way `patch-series.sh refresh` will after the bump, and
# names the first patch that no longer applies. --check-pins applies every
# series to its own pin exactly (patch-series.sh check: trees must match) and
# dry-runs the MM 1.10 bridge patcher on the bridge pins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERIES_DIR="$ROOT_DIR/builder/patches/series"

show_help() {
  cat <<'EOF'
check-patch-drift.sh - Dry-run a css34 patch series to detect upstream drift.

Options:
  --dir <path>             SourceMod or Metamod checkout to dry-run the series on
                           (a copy is patched; the directory is left untouched).
  --series <series>        Patch series: a line (sm12-latest, sm13-latest) or an
                           MM pin (MM_112). Default: --line, or MM_112 for Metamod.
  --mode mm110             With --dir/--mm-commit: dry-run the MM 1.10 bridge
                           patcher (apply-mmsource-css34.sh) instead of a series.
  --sm-commit <commit|rev> Fetch a SourceMod commit or revision and dry-run the line's series.
  --mm-commit <commit>     Fetch a Metamod commit and dry-run the MM series.
  --range <old>..<new>     Dry-run both ends of a revision bump (e.g. 7472..7477).
  --line <line>            Line for SourceMod checks (default: sm13-latest).
  --check-pins             Every series on its own pin (exact trees) and the bridge pins.
  --help                   Show this help message.
EOF
}

SERIES=""
MODE=""
TARGET_DIR=""
SM_COMMIT=""
MM_COMMIT=""
RANGE=""
LINE="sm13-latest"
CHECK_PINS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) TARGET_DIR="$2"; shift 2 ;;
    --series) SERIES="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --sm-commit) SM_COMMIT="$2"; shift 2 ;;
    --mm-commit) MM_COMMIT="$2"; shift 2 ;;
    --range) RANGE="$2"; shift 2 ;;
    --line) LINE="$2"; shift 2 ;;
    --check-pins) CHECK_PINS=1; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "FAIL: Unknown argument or option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TARGET_DIR" && -z "$SM_COMMIT" && -z "$MM_COMMIT" && -z "$RANGE" && $CHECK_PINS -eq 0 ]]; then
  CHECK_PINS=1
fi
if [[ -n "$MODE" && "$MODE" != mm110 ]]; then
  echo "FAIL: Unknown patch mode: $MODE (series replace the sm12/sm13/mm112 modes; use --series)" >&2
  exit 1
fi

series_root() { # <series dir>
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("root", "sourcemod"))' "$1/series.json"
}

report_fail() { # <target desc> <what> <log>
  echo "" >&2
  echo "========================================================================" >&2
  echo "FAIL: Patch drift detected for '$1'" >&2
  echo "$2" >&2
  echo "------------------------------------------------------------------------" >&2
  cat "$3" >&2
  echo "========================================================================" >&2
}

# Apply <series> with --3way to a copy of <dir>.
dry_run_series() ( # <dir> <series name> <target desc>
  local src_dir="$1" name="$2" desc="$3"
  local series="$SERIES_DIR/$name"
  [[ -f "$series/series.json" ]] || { echo "FAIL: no patch series $name ($series)" >&2; exit 1; }
  [[ -e "$src_dir/.git" ]] || { echo "FAIL: $src_dir is not a git checkout" >&2; exit 1; }
  local root work target repo patch
  root="$(series_root "$series")"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  cp -a "$src_dir" "$work/repo"
  local repos=()
  for dir in "$series"/*/; do
    repo="$(basename "$dir")"
    [[ "$repo" == "$root" ]] || repos+=("$repo")
  done
  repos+=("$root")
  echo "==> Testing patch drift for '${desc}' (series: ${name})..."
  for repo in "${repos[@]}"; do
    if [[ "$repo" == "$root" ]]; then target="$work/repo"; else target="$work/repo/$repo"; fi
    [[ -e "$target/.git" ]] || { echo "FAIL: $target is not a git checkout" >&2; exit 1; }
    # The copy has new inodes and ctimes: refresh the index's stat data first.
    git -C "$target" update-index -q --refresh >/dev/null 2>&1 || true
    for patch in "$series/$repo"/*.patch; do
      if ! git -c core.autocrlf=false -C "$target" apply --3way --index --whitespace=nowarn \
          "$patch" >"$work/apply.log" 2>&1; then
        report_fail "$desc" "Series: $name  Patch: $repo/$(basename "$patch")" "$work/apply.log"
        exit 1
      fi
    done
  done
  echo "==> [OK] No patch drift detected for '${desc}'"
)

# The MM 1.10 bridge core still comes from a fail-closed patch script.
dry_run_mm110() ( # <dir> <target desc>
  local work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  cp -a "$1" "$work/repo"
  echo "==> Testing patch drift for '$2' (mode: mm110)..."
  if ! bash "$ROOT_DIR/builder/patches/apply-mmsource-css34.sh" "$work/repo" >"$work/patch.log" 2>&1 ||
      grep -q 'FAIL:\|WARN:' "$work/patch.log"; then
    report_fail "$2" "Script: builder/patches/apply-mmsource-css34.sh" "$work/patch.log"
    exit 1
  fi
  echo "==> [OK] No patch drift detected for '$2'"
)

resolve_sm_rev_commit() {
  local target_rev="$1"
  local branch="${2:-master}"
  local cache_dir="${TMPDIR:-/tmp}/css34-drift-cache/sourcemod"
  mkdir -p "$cache_dir"

  if [[ ! -d "$cache_dir/.git" ]]; then
    git clone --quiet --filter=blob:none --no-checkout "https://github.com/alliedmodders/sourcemod.git" "$cache_dir"
  fi
  git -C "$cache_dir" fetch --quiet origin "$branch"

  if [[ "$target_rev" =~ ^[0-9]+$ ]]; then
    local total
    total="$(git -C "$cache_dir" rev-list --count "origin/$branch")"
    local offset=$((total - target_rev))
    if [[ $offset -lt 0 ]]; then
      echo "FAIL: revision $target_rev exceeds $branch tip count $total" >&2
      return 1
    fi
    local sha
    sha="$(git -C "$cache_dir" rev-list -n 1 --skip="$offset" "origin/$branch")"
    # Revision numbers are ancestor counts; refuse a commit that does not carry it.
    if [[ -z "$sha" || "$(git -C "$cache_dir" rev-list --count "$sha")" != "$target_rev" ]]; then
      echo "FAIL: cannot map revision $target_rev on $branch to a commit" >&2
      return 1
    fi
    echo "$sha"
  else
    git -C "$cache_dir" rev-parse "$target_rev"
  fi
}

fetch_into() { # <url> <dir> <commit> <label>
  SOURCEMOD_URL="$1" bash "$ROOT_DIR/builder/fetch-sourcemod.sh" "$2" "$3" "$4" >/dev/null
}

test_sm_commit() ( # <commit|rev> <line>
  local line="$2" branch=master sha work
  [[ "$line" == sm12* ]] && branch="1.12-dev"
  sha="$(resolve_sm_rev_commit "$1" "$branch")"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  echo "==> Fetching SourceMod $1 (${sha:0:8}) for drift testing..."
  fetch_into https://github.com/alliedmodders/sourcemod "$work/sourcemod" "$sha" SourceMod
  dry_run_series "$work/sourcemod" "${SERIES:-$line}" "SourceMod $1 (${sha:0:8})"
)

test_mm_commit() ( # <commit> <series|mm110>
  local work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  echo "==> Fetching Metamod $1 for drift testing..."
  fetch_into https://github.com/alliedmodders/metamod-source "$work/metamod" "$1" Metamod:Source
  if [[ "$2" == mm110 ]]; then
    dry_run_mm110 "$work/metamod" "Metamod $1"
  else
    dry_run_series "$work/metamod" "$2" "Metamod $1"
  fi
)

if [[ -n "$TARGET_DIR" ]]; then
  [[ -d "$TARGET_DIR" ]] || { echo "FAIL: Directory does not exist: $TARGET_DIR" >&2; exit 1; }
  if [[ "$MODE" == mm110 ]]; then
    dry_run_mm110 "$TARGET_DIR" "$TARGET_DIR"
  elif [[ -n "$SERIES" ]]; then
    dry_run_series "$TARGET_DIR" "$SERIES" "$TARGET_DIR"
  elif [[ -f "$TARGET_DIR/core/ISmmAPI.h" ]]; then
    dry_run_series "$TARGET_DIR" MM_112 "$TARGET_DIR"
  else
    dry_run_series "$TARGET_DIR" "$LINE" "$TARGET_DIR"
  fi
  exit 0
fi

if [[ -n "$SM_COMMIT" ]]; then
  test_sm_commit "$SM_COMMIT" "$LINE"
  exit 0
fi

if [[ -n "$MM_COMMIT" ]]; then
  test_mm_commit "$MM_COMMIT" "${MODE:-${SERIES:-MM_112}}"
  exit 0
fi

if [[ -n "$RANGE" ]]; then
  old_rev="${RANGE%%..*}"
  new_rev="${RANGE##*..}"
  if [[ "$RANGE" != *..* || -z "$old_rev" || -z "$new_rev" ]]; then
    echo "FAIL: range must be OLD..NEW" >&2
    exit 1
  fi
  echo "==> Testing patch drift across revision bump ${RANGE} (line: ${LINE})..."
  test_sm_commit "$old_rev" "$LINE"
  test_sm_commit "$new_rev" "$LINE"
  exit 0
fi

if [[ $CHECK_PINS -eq 1 ]]; then
  echo "==> Running patch drift check on current pins..."
  errors=0
  for manifest in "$SERIES_DIR"/*/series.json; do
    name="$(basename "$(dirname "$manifest")")"
    work="$(mktemp -d)"
    if bash "$ROOT_DIR/builder/scripts/patch-series.sh" check "$name" "$work" >"$work.log" 2>&1; then
      echo "==> [OK] series $name applies to its pin"
    else
      report_fail "series $name" "patch-series.sh check $name" "$work.log"
      errors=$((errors + 1))
    fi
    rm -rf "$work" "$work.log"
  done
  bridges="$(python3 - "$ROOT_DIR/builder/lines.json" <<'PYPINS'
import json, sys
data = json.load(open(sys.argv[1]))
seen = set()
for line in data["lines"].values():
    if line.get("status") == "active" and "bridge_metamod" in line:
        mm = data["pins"][line["bridge_metamod"]]
        if mm["commit"] not in seen:
            print("mm" + mm["mode"].replace(".", ""), mm["commit"]); seen.add(mm["commit"])
PYPINS
)"
  while read -r mode commit; do
    [[ -n "$mode" ]] || continue
    if [[ "$mode" != mm110 ]]; then
      echo "FAIL: unsupported bridge Metamod mode $mode" >&2; errors=$((errors + 1)); continue
    fi
    test_mm_commit "$commit" mm110 || errors=$((errors + 1))
  done <<< "$bridges"

  if [[ $errors -eq 0 ]]; then
    echo "==> [OK] All pin drift checks passed."
    exit 0
  fi
  echo "==> FAIL: Patch drift detected during pin check!" >&2
  exit 1
fi
