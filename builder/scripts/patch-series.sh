#!/usr/bin/env bash
# Maintain a line's SourceMod patch series (T3.4, builder/patches/series/<line>/).
#
#   builder/scripts/patch-series.sh refresh <line> [workdir]
#       Rebase the series onto the line's pinned SourceMod commit (lines.json):
#       fetch it, apply each patch with `git apply --3way`, rewrite every patch
#       from the result (keeping its description) and series.json (commit and
#       trees). A patch that no longer applies stops with the conflict left in
#       <workdir> for a manual fix; rerun after editing that patch.
#   builder/scripts/patch-series.sh check <line> [workdir]
#       Fetch the pinned commit and run builder/patches/apply-series.sh on it.
#
# After a pin bump: refresh, review the patch diff, build and smoke.
set -euo pipefail

cmd="${1:?usage: patch-series.sh refresh|check <line> [workdir]}"
line="${2:?line required}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
series="$root/builder/patches/series/$line"
[[ -f "$series/series.json" ]] || { echo "FAIL: no patch series for $line ($series)" >&2; exit 1; }

commit="$(CSS34_LINE="$line" bash -c 'source "$1/builder/resolve-version.sh" >/dev/null 2>&1 && echo "$SOURCEMOD_COMMIT"' _ "$root")"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "FAIL: cannot resolve the SourceMod pin of $line" >&2; exit 1; }
work="${3:-$(mktemp -d)}"
sm="$work/sourcemod"
bash "$root/builder/fetch-sourcemod.sh" "$sm" "$commit"

case "$cmd" in
  check)
    bash "$root/builder/patches/apply-series.sh" "$series" "$sm"
    exit 0
    ;;
  refresh) ;;
  *) echo "FAIL: unknown command $cmd" >&2; exit 1 ;;
esac

git_c() { git -c core.autocrlf=false -c user.name=css34 -c user.email=css34@localhost -C "$@"; }
trees=()
repos=()
for dir in "$series"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == sourcemod ]] || repos+=("$name")
done
repos+=(sourcemod)
for repo in "${repos[@]}"; do
  if [[ "$repo" == sourcemod ]]; then target="$sm"; else target="$sm/$repo"; fi
  base="$(git -C "$target" rev-parse HEAD)"
  for patch in "$series/$repo"/*.patch; do
    if ! git_c "$target" apply --3way --index --whitespace=nowarn "$patch"; then
      echo "FAIL: $(basename "$patch") does not apply to $repo at $(git -C "$target" rev-parse --short HEAD);" \
        "fix it in $target, then copy the result into the patch and rerun" >&2
      exit 1
    fi
    git_c "$target" commit -q --no-verify -m "$(basename "$patch")"
    # Keep the description (everything before the first diff), regenerate the diff.
    desc="$(awk '/^diff --git /{exit} {print}' "$patch")"
    { printf '%s\n\n' "$desc"; git_c "$target" diff --no-color --full-index HEAD~1 HEAD; } > "$patch.new"
    mv "$patch.new" "$patch"
  done
  # Trees as apply-series.sh sees them: the index after `git apply --index`.
  git_c "$target" reset -q --soft "$base"
  trees+=("$repo=$(git -C "$target" write-tree)")
  echo "==> $repo: series refreshed"
done

python3 - "$series/series.json" "$line" "$commit" "${trees[@]}" <<'PY'
import json, sys
path, line, commit, *trees = sys.argv[1:]
data = {"line": line, "commit": commit,
        "trees": dict(sorted(t.split("=", 1) for t in trees))}
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print("==> wrote " + path)
PY
