#!/usr/bin/env bash
# Switch the per-line pointer release (tag line-<line>) to a smoke-tested build.
#
#   update-line-pointer.sh <line> <source-tag> <sm.tar.gz> <mm.tar.gz>
#
# Stable asset URLs (never renamed, never drafted):
#   releases/download/line-<line>/sourcemod-css34-linux.tar.gz
#   releases/download/line-<line>/mmsource-css34-linux.tar.gz
#   releases/download/line-<line>/SHA256SUMS
#   releases/download/line-<line>/lines.json
# lines.json (all lines) is also mirrored to the `lines-index` release.
#
# Swap order per asset: upload "<name>.next" → delete old "<name>" → rename
# "<name>.next" to "<name>". The old file stays downloadable during the whole
# upload; the only window is the two back-to-back API calls of the swap.
# GitHub cannot replace an asset atomically, so this is the minimum.
#
# Requires: gh (GH_TOKEN), python3, GITHUB_REPOSITORY. Optional SMOKE=pass|fail:
# with fail, assets are left alone and only lines.json[line].candidate records it.
set -euo pipefail

LINE="${1:?line required}"
SRC_TAG="${2:?source tag required}"
SM_PKG="${3:?sm package required}"
MM_PKG="${4:?mm package required}"
SMOKE="${SMOKE:-pass}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
PTR_TAG="line-${LINE}"
INDEX_TAG="lines-index"
TARGET="${GITHUB_SHA:-$(git rev-parse HEAD)}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

ensure_release() {
  local tag="$1" title="$2" notes="$3"
  if ! gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "$tag" --repo "$REPO" --target "$TARGET" \
      --title "$title" --notes "$notes" --latest=false
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

swap_asset() {
  local tag="$1" src="$2" name="$3"
  local next="${work}/${name}.next"
  cp -f "$src" "$next"
  local stale
  stale="$(asset_id "$tag" "${name}.next")"
  [[ -n "$stale" ]] && gh api -X DELETE "repos/${REPO}/releases/assets/${stale}" >/dev/null
  gh release upload "$tag" --repo "$REPO" "$next"
  local new_id old_id
  new_id="$(asset_id "$tag" "${name}.next")"
  old_id="$(asset_id "$tag" "$name")"
  [[ -n "$new_id" ]] || { echo "upload of ${name}.next did not appear" >&2; exit 1; }
  [[ -n "$old_id" ]] && gh api -X DELETE "repos/${REPO}/releases/assets/${old_id}" >/dev/null
  gh api -X PATCH "repos/${REPO}/releases/assets/${new_id}" -f name="$name" >/dev/null
  echo "==> ${tag}/${name} ← $(basename "$src")"
}

manifest="$(tar -xzOf "$SM_PKG" addons/sourcemod/css34-package.json)"
mm_manifest="$(tar -xzOf "$MM_PKG" addons/metamod/css34-package.json)"

# Current lines.json (index release is the source of truth).
lines_json="${work}/lines.json"
if ! gh release download "$INDEX_TAG" --repo "$REPO" -p lines.json -D "$work" 2>/dev/null; then
  echo '{}' > "$lines_json"
fi

python3 - "$lines_json" "$LINE" "$SRC_TAG" "$SMOKE" "$manifest" "$mm_manifest" "$PTR_TAG" "$REPO" <<'PY'
import json, sys, datetime
path, line, tag, smoke, sm, mm, ptr, repo = sys.argv[1:9]
sm, mm = json.loads(sm), json.loads(mm)
data = json.load(open(path))
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
    "smoke": smoke,
    "updated": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "sourcemod_url": f"https://github.com/{repo}/releases/download/{ptr}/sourcemod-css34-linux.tar.gz",
    "mmsource_url": f"https://github.com/{repo}/releases/download/{ptr}/mmsource-css34-linux.tar.gz",
}
if smoke == "pass":
    data[line] = entry
else:
    # Pointer keeps serving the last passing build; only note the failed candidate.
    data.setdefault(line, {"smoke": "fail", "tag": None})
    data[line]["candidate"] = {"tag": tag, "smoke": "fail", "updated": entry["updated"]}
json.dump(dict(sorted(data.items())), open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
cat "$lines_json"

ensure_release "$INDEX_TAG" "lines-index" \
  "Machine-readable index of css34 line pointers (lines.json). Updated by release.yml."

if [[ "$SMOKE" == "pass" ]]; then
  ensure_release "$PTR_TAG" "${PTR_TAG} (stable pointer)" \
    "Stable pointer for line \`${LINE}\`: always the latest smoke-passed build. Asset names never change; see lines.json for the source tag."
  cp -f "$SM_PKG" "${work}/sourcemod-css34-linux.tar.gz"
  cp -f "$MM_PKG" "${work}/mmsource-css34-linux.tar.gz"
  (cd "$work" && sha256sum sourcemod-css34-linux.tar.gz mmsource-css34-linux.tar.gz > SHA256SUMS)
  swap_asset "$PTR_TAG" "${work}/sourcemod-css34-linux.tar.gz" sourcemod-css34-linux.tar.gz
  swap_asset "$PTR_TAG" "${work}/mmsource-css34-linux.tar.gz" mmsource-css34-linux.tar.gz
  swap_asset "$PTR_TAG" "${work}/SHA256SUMS" SHA256SUMS
  swap_asset "$PTR_TAG" "$lines_json" lines.json
  gh release edit "$PTR_TAG" --repo "$REPO" \
    --notes "Stable pointer for line \`${LINE}\` → [\`${SRC_TAG}\`](https://github.com/${REPO}/releases/tag/${SRC_TAG}) (smoke: pass)."
fi
swap_asset "$INDEX_TAG" "$lines_json" lines.json
