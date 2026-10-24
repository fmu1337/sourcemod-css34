#!/usr/bin/env bash
# Switch the per-line pointer release (tag line-<line>) to a smoke-tested build.
#
#   update-line-pointer.sh <line> <source-tag> <sm.tar.gz> <mm.tar.gz>
#
# Stable asset URLs (never renamed, never drafted):
#   releases/download/line-<line>/sourcemod-css34-linux.tar.gz
#   releases/download/line-<line>/mmsource-css34-linux.tar.gz
#   releases/download/line-<line>/SHA256SUMS
#   releases/download/line-<line>/lines.json      {"<line>": {...}} — this line only
#   releases/download/lines-index/lines.json      {"<line>": {...}, ...} — all lines
#
# Concurrency: release.yml serializes runs per line, so line-<line> has one
# writer. Different lines run in parallel, so lines-index/lines.json is never
# read-modify-written: it is rebuilt from every line-*/lines.json and checked
# again after upload (see publish_index).
#
# Swap order per asset: upload "<name>.next-<run>" → delete old "<name>" →
# rename to "<name>". The old file stays downloadable during the whole upload;
# the only window is the two back-to-back API calls of the swap. GitHub cannot
# replace an asset atomically, so this is the minimum.
#
# Requires: gh (GH_TOKEN), python3, GITHUB_REPOSITORY. SMOKE=pass|fail: with
# fail, packages are left alone and only lines.json[line].candidate records it.
set -euo pipefail

LINE="${1:?line required}"
SRC_TAG="${2:?source tag required}"
SM_PKG="${3:?sm package required}"
MM_PKG="${4:?mm package required}"
SMOKE="${SMOKE:-pass}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
PTR_TAG="line-${LINE}"
INDEX_TAG="lines-index"
TARGET="${TARGET:-${GITHUB_SHA:-$(git rev-parse HEAD)}}"
# Unique per run: parallel runs must never touch each other's temp assets.
RUN_KEY="${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-0}"
# Commit time of the tagged commit: when two tags of one line finish out of
# order, the older one must not switch the pointer back.
SRC_TIME="${SRC_TIME:-$(git show -s --format=%ct "$TARGET" 2>/dev/null || echo 0)}"
FORCE_REPOINT="${FORCE_REPOINT:-0}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

ensure_release() {
  local tag="$1" title="$2" notes="$3"
  if ! gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    # A parallel run (another line, for lines-index) may create it first.
    gh release create "$tag" --repo "$REPO" --target "$TARGET" \
      --title "$title" --notes "$notes" --latest=false \
      || gh release view "$tag" --repo "$REPO" >/dev/null
  fi
  # A pointer must never be a draft (draft asset URLs 404).
  if [[ "$(gh release view "$tag" --repo "$REPO" --json isDraft -q .isDraft)" == "true" ]]; then
    gh release edit "$tag" --repo "$REPO" --draft=false --latest=false
  fi
}

asset_id() {
  local tag="$1" name="$2"
  gh api "repos/${REPO}/releases/tags/${tag}" \
    -q ".assets[] | select(.name == \"${name}\") | .id" 2>/dev/null || true
}

# Not `gh … | grep -q`: under pipefail an early grep exit can SIGPIPE gh.
has_asset() {
  local names
  names="$(gh release view "$1" --repo "$REPO" --json assets -q '.assets[].name')"
  grep -qxF "$2" <<<"$names"
}

swap_asset() {
  local tag="$1" src="$2" name="$3"
  local tmp_name="${name}.next-${RUN_KEY}"
  local next="${work}/upload/${tmp_name}"
  mkdir -p "${work}/upload"
  cp -f "$src" "$next"
  local stale
  stale="$(asset_id "$tag" "$tmp_name")"
  if [[ -n "$stale" ]]; then
    gh api -X DELETE "repos/${REPO}/releases/assets/${stale}" >/dev/null
  fi
  gh release upload "$tag" --repo "$REPO" "$next"
  local new_id old_id attempt
  new_id="$(asset_id "$tag" "$tmp_name")"
  [[ -n "$new_id" ]] || { echo "upload of ${tmp_name} did not appear" >&2; exit 1; }
  for attempt in 1 2 3 4 5; do
    old_id="$(asset_id "$tag" "$name")"
    if [[ -n "$old_id" ]]; then
      # Tolerate a concurrent run having deleted it already.
      gh api -X DELETE "repos/${REPO}/releases/assets/${old_id}" >/dev/null 2>&1 || true
    fi
    # Fails (422) if a concurrent run renamed its upload in between: retry.
    if gh api -X PATCH "repos/${REPO}/releases/assets/${new_id}" -f name="$name" >/dev/null; then
      echo "==> ${tag}/${name} ← $(basename "$src")"
      return 0
    fi
    sleep "$attempt"
  done
  echo "could not rename ${tag}/${tmp_name} → ${name}" >&2
  exit 1
}

# Merge every published line-*/lines.json into one {line: entry} document.
build_index() {
  local out="$1" dir="${work}/index-src"
  rm -rf "$dir"
  mkdir -p "$dir"
  local tag
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    mkdir -p "${dir}/${tag}"
    if has_asset "$tag" lines.json; then
      gh release download "$tag" --repo "$REPO" -p lines.json -D "${dir}/${tag}"
    fi
  done < <(gh api --paginate "repos/${REPO}/releases?per_page=100" \
    -q '.[] | select(.draft == false and (.tag_name | startswith("line-"))) | .tag_name')
  python3 - "$dir" "$out" <<'PY'
import json, pathlib, sys
src, out = pathlib.Path(sys.argv[1]), sys.argv[2]
index = {}
for f in sorted(src.glob("*/lines.json")):
    index.update(json.loads(f.read_text()))
with open(out, "w") as fh:
    json.dump(dict(sorted(index.items())), fh, indent=2)
    fh.write("\n")
PY
}

# Upload the rebuilt index, then rebuild again from the sources. Any run whose
# upload missed a line written in between sees the difference and re-uploads,
# so the last writer always leaves a complete index.
publish_index() {
  local attempt
  for attempt in 1 2 3 4 5; do
    build_index "${work}/index.json"
    swap_asset "$INDEX_TAG" "${work}/index.json" lines.json
    sleep $((5 + RANDOM % 10))
    build_index "${work}/index.check.json"
    if cmp -s "${work}/index.json" "${work}/index.check.json"; then
      cat "${work}/index.json"
      return 0
    fi
    echo "==> lines-index changed while publishing (attempt ${attempt}); rebuilding"
  done
  echo "lines-index did not settle after 5 attempts" >&2
  exit 1
}

manifest="$(tar -xzOf "$SM_PKG" addons/sourcemod/css34-package.json)"
mm_manifest="$(tar -xzOf "$MM_PKG" addons/metamod/css34-package.json)"

ensure_release "$PTR_TAG" "${PTR_TAG} (stable pointer)" \
  "Stable pointer for line \`${LINE}\`: always the latest smoke-passed build. Asset names never change; see lines.json for the source tag."
ensure_release "$INDEX_TAG" "lines-index" \
  "Machine-readable index of css34 line pointers (lines.json). Updated by release.yml."

# This line's own entry (only this line's runs write it).
line_json="${work}/lines.json"
if has_asset "$PTR_TAG" lines.json; then
  gh release download "$PTR_TAG" --repo "$REPO" -p lines.json -D "$work"
else
  echo '{}' > "$line_json"
fi

decision="${work}/decision"
python3 - "$line_json" "$LINE" "$SRC_TAG" "$SMOKE" "$manifest" "$mm_manifest" "$PTR_TAG" "$REPO" "$SRC_TIME" "$FORCE_REPOINT" "$decision" <<'PY'
import json, sys, datetime
path, line, tag, smoke, sm, mm, ptr, repo, src_time, force_repoint, decision = sys.argv[1:12]
sm, mm = json.loads(sm), json.loads(mm)
src_time = int(src_time or 0)
force = force_repoint == "1"
current = json.load(open(path)).get(line)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
served_time = int((current or {}).get("source_commit_time") or 0)
if not force and smoke == "pass" and current and current.get("smoke") == "pass" and served_time > src_time:
    # A newer tag of this line already switched the pointer: leave it.
    open(decision, "w").write("stale")
    print(f"pointer already serves {current['tag']} (commit time {served_time} > {src_time}); not switching",
          file=sys.stderr)
    sys.exit(0)
open(decision, "w").write("switch" if smoke == "pass" else "record")
if smoke == "pass":
    entry = {
        "tag": tag,
        "pointer_tag": ptr,
        "sm_version": sm["sm_version"],
        "sm_commit": sm["sm_commit"],
        "mm_version": mm["mm_version"],
        "mm_commit": mm["mm_commit"],
        "extension_api": sm["extension_api"],
        "extension_api_min": sm["extension_api_min"],
        "metamod_binary": mm["metamod_binary"],
        "smoke": "pass",
        "source_commit_time": src_time,
        "updated": now,
        "sourcemod_url": f"https://github.com/{repo}/releases/download/{ptr}/sourcemod-css34-linux.tar.gz",
        "mmsource_url": f"https://github.com/{repo}/releases/download/{ptr}/mmsource-css34-linux.tar.gz",
    }
else:
    # The pointer keeps serving the last passing build (if any); only note the
    # failed candidate. A line that never passed has tag=null, smoke=fail.
    entry = current or {"tag": None, "pointer_tag": ptr, "smoke": "fail"}
    entry["candidate"] = {"tag": tag, "smoke": "fail", "updated": now}
with open(path, "w") as fh:
    json.dump({line: entry}, fh, indent=2)
    fh.write("\n")
PY
cat "$line_json"
if [[ "$(cat "$decision")" == "stale" ]]; then
  echo "::notice::line-${LINE} already serves a newer tag than ${SRC_TAG}; pointer unchanged"
  publish_index
  exit 0
fi

if [[ "$SMOKE" == "pass" ]]; then
  cp -f "$SM_PKG" "${work}/sourcemod-css34-linux.tar.gz"
  cp -f "$MM_PKG" "${work}/mmsource-css34-linux.tar.gz"
  (cd "$work" && sha256sum sourcemod-css34-linux.tar.gz mmsource-css34-linux.tar.gz > SHA256SUMS)
  swap_asset "$PTR_TAG" "${work}/sourcemod-css34-linux.tar.gz" sourcemod-css34-linux.tar.gz
  swap_asset "$PTR_TAG" "${work}/mmsource-css34-linux.tar.gz" mmsource-css34-linux.tar.gz
  swap_asset "$PTR_TAG" "${work}/SHA256SUMS" SHA256SUMS
  gh release edit "$PTR_TAG" --repo "$REPO" \
    --notes "Stable pointer for line \`${LINE}\` → [\`${SRC_TAG}\`](https://github.com/${REPO}/releases/tag/${SRC_TAG}) (smoke: pass)."
fi
swap_asset "$PTR_TAG" "$line_json" lines.json
publish_index
