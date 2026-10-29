#!/usr/bin/env bash
#
# check-patch-drift.sh - Dry-run css34 patch layer on target commit/directory to detect anchor drift
#
# Usage:
#   builder/scripts/check-patch-drift.sh --dir <path> [--mode sm12|sm13|sm11|mm112|mm110]
#   builder/scripts/check-patch-drift.sh --sm-commit <commit_or_rev> [--mode sm12|sm13]
#   builder/scripts/check-patch-drift.sh --mm-commit <commit_or_rev> [--mode mm112|mm110]
#   builder/scripts/check-patch-drift.sh --range <old>..<new> [--line sm12|sm13|mm112]
#   builder/scripts/check-patch-drift.sh --check-pins
#   builder/scripts/check-patch-drift.sh --help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

show_help() {
  cat <<'EOF'
check-patch-drift.sh - Dry-run css34 patch layer to detect patch anchor drift.

Options:
  --dir <path>             Path to SourceMod or Metamod directory to dry-run patch layer on.
  --mode <mode>            Patch mode: sm12, sm13, sm11, mm112, mm110 (default: sm13 or auto-detect).
  --sm-commit <commit|rev> Fetch/checkout SourceMod commit or revision and test for drift.
  --mm-commit <commit|rev> Fetch/checkout Metamod commit or revision and test for drift.
  --range <old>..<new>     Test patch drift across a revision bump (e.g. 7253..7255 or 7472..7477).
  --line <line>            Line to target for range/commit checks (default: sm13-latest).
  --check-pins             Check all active pins defined in versions.env / lines.json for drift.
  --help                   Show this help message.
EOF
}

MODE=""
TARGET_DIR=""
SM_COMMIT=""
MM_COMMIT=""
RANGE=""
LINE="sm13-latest"
CHECK_PINS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --sm-commit)
      SM_COMMIT="$2"
      shift 2
      ;;
    --mm-commit)
      MM_COMMIT="$2"
      shift 2
      ;;
    --range)
      RANGE="$2"
      shift 2
      ;;
    --line)
      LINE="$2"
      shift 2
      ;;
    --check-pins)
      CHECK_PINS=1
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      if [[ -z "$TARGET_DIR" && -d "$1" ]]; then
        TARGET_DIR="$1"
        shift
      else
        echo "FAIL: Unknown argument or option: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ $# -eq 0 && -z "$TARGET_DIR" && -z "$SM_COMMIT" && -z "$MM_COMMIT" && -z "$RANGE" && $CHECK_PINS -eq 0 ]]; then
  CHECK_PINS=1
fi

dry_run_patch_dir() {
  local src_dir="$1"
  local mode="$2"
  local target_desc="${3:-$src_dir}"

  if [[ ! -d "$src_dir" ]]; then
    echo "FAIL: Directory does not exist: $src_dir" >&2
    return 1
  fi

  local work_dir
  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT

  local temp_target="${work_dir}/repo"
  cp -r "$src_dir" "$temp_target"

  local patch_script=""
  case "$mode" in
    sm12|sm13|sm12-latest|sm13-latest|sm13-dev)
      patch_script="$ROOT_DIR/builder/patches/apply-sourcemod-v112.sh"
      ;;
    sm11|sm11-oldstable)
      patch_script="$ROOT_DIR/builder/patches/apply-sourcemod.sh"
      ;;
    mm112|mm112_frozen|MM_112)
      patch_script="$ROOT_DIR/builder/patches/apply-mmsource-v112.sh"
      ;;
    mm110|MM_110)
      patch_script="$ROOT_DIR/builder/patches/apply-mmsource-css34.sh"
      ;;
    *)
      if [[ -f "$temp_target/hl2sdk-manifests/manifests/episode1.json" ]]; then
        patch_script="$ROOT_DIR/builder/patches/apply-sourcemod-v112.sh"
        mode="sm13"
      elif [[ -f "$temp_target/core/ISmmAPI.h" ]]; then
        patch_script="$ROOT_DIR/builder/patches/apply-mmsource-v112.sh"
        mode="mm112"
      else
        echo "FAIL: Could not auto-detect patch mode for $src_dir. Please specify --mode." >&2
        return 1
      fi
      ;;
  esac

  local log_file="${work_dir}/patch.log"
  local rc=0

  echo "==> Testing patch drift for target '${target_desc}' (mode: ${mode})..."
  set +e
  bash "$patch_script" "$temp_target" >"$log_file" 2>&1
  rc=$?
  set -e

  local log_content
  log_content="$(cat "$log_file")"

  if [[ $rc -ne 0 || "$log_content" == *"FAIL:"* || "$log_content" == *"WARN:"* ]]; then
    echo "" >&2
    echo "========================================================================" >&2
    echo "FAIL: Patch drift detected for '${target_desc}'" >&2
    echo "Script: $patch_script" >&2
    echo "Mode:   $mode" >&2
    echo "------------------------------------------------------------------------" >&2
    echo "$log_content" >&2
    echo "========================================================================" >&2
    rm -rf "$work_dir"
    trap - EXIT
    return 1
  fi

  echo "==> [OK] No patch drift detected for '${target_desc}'"
  rm -rf "$work_dir"
  trap - EXIT
  return 0
}

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
      offset=0
    fi
    git -C "$cache_dir" rev-list -n 1 --skip="$offset" "origin/$branch"
  else
    git -C "$cache_dir" rev-parse "$target_rev"
  fi
}

test_sm_commit() {
  local commit_or_rev="$1"
  local mode="${2:-sm13}"
  local branch="master"
  if [[ "$mode" == "sm12"* ]]; then
    branch="1.12-dev"
  fi

  local sha
  sha="$(resolve_sm_rev_commit "$commit_or_rev" "$branch")"

  local work_dir
  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT

  echo "==> Fetching SourceMod ${commit_or_rev} (${sha:0:8}) for drift testing..."
  local sm_dir="${work_dir}/sourcemod"
  git clone --quiet --no-checkout "https://github.com/alliedmodders/sourcemod.git" "$sm_dir"
  git -C "$sm_dir" checkout --quiet "$sha"
  git -C "$sm_dir" submodule update --quiet --init --recursive

  dry_run_patch_dir "$sm_dir" "$mode" "SourceMod ${commit_or_rev} (${sha:0:8})"
  local rc=$?
  rm -rf "$work_dir"
  trap - EXIT
  return $rc
}

if [[ -n "$TARGET_DIR" ]]; then
  dry_run_patch_dir "$TARGET_DIR" "$MODE" "$TARGET_DIR"
  exit $?
fi

if [[ -n "$SM_COMMIT" ]]; then
  test_sm_commit "$SM_COMMIT" "${MODE:-sm13}"
  exit $?
fi

if [[ -n "$RANGE" ]]; then
  old_rev="${RANGE%%..*}"
  new_rev="${RANGE##*..}"
  echo "==> Testing patch drift across revision bump ${RANGE} (line: ${LINE})..."

  mode="sm13"
  if [[ "$LINE" == "sm12"* || "$old_rev" == "72"* || "$new_rev" == "72"* ]]; then
    mode="sm12"
  fi

  test_sm_commit "$new_rev" "$mode"
  exit $?
fi

test_mm_commit() {
  local commit_or_rev="$1"
  local mode="${2:-mm112}"
  local branch="1.12-dev"

  local work_dir
  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT

  echo "==> Fetching Metamod ${commit_or_rev} for drift testing..."
  local mm_dir="${work_dir}/metamod"
  git clone --quiet --no-checkout "https://github.com/alliedmodders/metamod-source.git" "$mm_dir"
  git -C "$mm_dir" checkout --quiet "$commit_or_rev"
  git -C "$mm_dir" submodule update --quiet --init --recursive

  dry_run_patch_dir "$mm_dir" "$mode" "Metamod ${commit_or_rev}"
  local rc=$?
  rm -rf "$work_dir"
  trap - EXIT
  return $rc
}

if [[ -n "$MM_COMMIT" ]]; then
  test_mm_commit "$MM_COMMIT" "${MODE:-mm112}"
  exit $?
fi

if [[ $CHECK_PINS -eq 1 ]]; then
  echo "==> Running patch drift check on current active line pins..."

  if [[ -f "$ROOT_DIR/builder/versions.env" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/builder/versions.env"
  fi

  errors=0

  if [[ -n "${SM_LATEST_13_COMMIT:-}" ]]; then
    test_sm_commit "${SM_LATEST_13_COMMIT}" "sm13" || errors=$((errors + 1))
  fi

  if [[ -n "${SM_LATEST_COMMIT:-}" ]]; then
    test_sm_commit "${SM_LATEST_COMMIT}" "sm12" || errors=$((errors + 1))
  fi

  if [[ -n "${MM_112_COMMIT:-}" ]]; then
    test_mm_commit "${MM_112_COMMIT}" "mm112" || errors=$((errors + 1))
  fi

  if [[ $errors -eq 0 ]]; then
    echo "==> [OK] All pin drift checks passed."
    exit 0
  else
    echo "==> FAIL: Patch drift detected during pin check!" >&2
    exit 1
  fi
fi
