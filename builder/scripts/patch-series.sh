#!/usr/bin/env bash
# Maintain a patch series (T3.4): builder/patches/series/<line>/ for SourceMod,
# builder/patches/series/<MM pin>/ (MM_112) for Metamod.
#
#   builder/scripts/patch-series.sh refresh <series> [workdir]
#       Rebase the series onto its pinned commit (read from builder/lines.json,
#       so it works right after a pin edit, before `lines.py gen`):
#       fetch it, apply each patch with `git apply --3way`, rewrite every patch
#       from the result (keeping its description) and series.json (commit and
#       trees). A patch that no longer applies stops with the conflict left in
#       <workdir> for a manual fix; rerun after editing that patch.
#   builder/scripts/patch-series.sh check <series> [workdir]
#       Fetch the pinned commit and run builder/patches/apply-series.sh on it.
#
# After a pin bump: refresh, review the patch diff, build and smoke.
set -euo pipefail

cmd="${1:?usage: patch-series.sh refresh|check <series> [workdir]}"
name="${2:?series name (a line or an MM_ pin) required}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
series="$root/builder/patches/series/$name"
[[ -f "$series/series.json" ]] || { echo "FAIL: no patch series $name ($series)" >&2; exit 1; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], sys.argv[3]))' "$series/series.json" "$@"; }
top="$(field root sourcemod)"

# The pin straight from builder/lines.json (not the generated versions.env):
# after a pin bump, `lines.py gen` refuses to run until the series is
# refreshed, so the order is edit lines.json -> refresh -> lines.py gen.
pin_commit() { # <series name> <root>
  python3 - "$root/builder/lines.json" "$1" "$2" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
name, top = sys.argv[2], sys.argv[3]
if top == "sourcemod":
    pin = data["pins"][data["lines"][name]["sourcemod"]]
else:
    pin = data["pins"][name]
print(pin["commit"])
PY
}
commit="$(pin_commit "$name" "$top" 2>/dev/null || true)"
if [[ "$top" == sourcemod ]]; then
  url="https://github.com/alliedmodders/sourcemod"
  label=SourceMod
else
  url="https://github.com/alliedmodders/metamod-source"
  label=Metamod:Source
fi
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "FAIL: cannot resolve the pinned commit of $name" >&2; exit 1; }
work="${3:-$(mktemp -d)}"
sm="$work/$top"
SOURCEMOD_URL="$url" bash "$root/builder/fetch-sourcemod.sh" "$sm" "$commit" "$label"

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
  [[ "$name" == "$top" ]] || repos+=("$name")
done
repos+=("$top")
for repo in "${repos[@]}"; do
  if [[ "$repo" == "$top" ]]; then target="$sm"; else target="$sm/$repo"; fi
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

python3 - "$series/series.json" "$commit" "${trees[@]}" <<'PY'
import json, sys
path, commit, *trees = sys.argv[1:]
data = json.load(open(path))
data["commit"] = commit
data["trees"] = dict(sorted(t.split("=", 1) for t in trees))
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print("==> wrote " + path)
PY
