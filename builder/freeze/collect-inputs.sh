#!/usr/bin/env bash
# T2.7: build a line online once and archive every input of that build, so it
# can be rebuilt later with --network none (builder/freeze/build-offline.sh).
#
#   CSS34_LINE=<line> builder/freeze/collect-inputs.sh OUT_DIR   (sm11: at the sm11-freeze tag)
#
# Run it in a fresh checkout (no deps/, sourcemod submodule not initialized):
# cached deps skip their downloads, and those files would be missing.
#
# OUT_DIR/assets gets, each as its own file (release sm11-freeze-inputs):
#   git-<owner>-<repo>.tar.zst   bare mirror holding the pinned commit(s) of a
#                                repository the build clones (SourceMod and its
#                                submodules, Metamod 1.10 / 1.12 + submodules,
#                                hl2sdk episode1, AMBuild; sm11's also ep1c)
#   dl-<name>                    every pinned download (zlib, OpenSSL, MySQL,
#                                GeoLite2; sm11's also hl2sdk css headers)
#   build-image.tar.zst          docker save of the build image, tagged
#                                css34-build-ml2014:<line>-freeze
#   <package>                    the packages of this online build
#   MANIFEST.json, SHA256SUMS
# IMAGE_REGISTRY_REF (optional) is recorded as the image's registry copy
# (ghcr.io/fmu1337/css34-build-ml2014@sha256:..., pushed by freeze-inputs.yml).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:?output directory required}"
LINE="${CSS34_LINE:?CSS34_LINE required}"
IMAGE="${ML2014_IMAGE:-quay.io/pypa/manylinux2014_i686@sha256:30305867f278896ee117b0d162a8e4f9b7b16819e6590f6139e14c5ed5b23fdd}"
FREEZE_TAG="css34-build-ml2014:${LINE}-freeze"
ZSTD_LEVEL="${ZSTD_LEVEL:-19}"

docker_cmd() { if docker info >/dev/null 2>&1; then docker "$@"; else sudo docker "$@"; fi; }
die() { echo "FAIL: $*" >&2; exit 1; }

command -v zstd >/dev/null || die "zstd is required"
[[ ! -e "$ROOT/deps" ]] || die "$ROOT/deps exists: collect from a fresh checkout"
[[ ! -e "$ROOT/sourcemod/.git" ]] || die "$ROOT/sourcemod is initialized: collect from a fresh checkout"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
assets="$OUT/assets"
work="$OUT/work"
rm -rf "$assets" "$work"
mkdir -p "$assets" "$work/downloads" "$work/git"

echo "==> Online build of ${LINE}, recording downloads"
CSS34_LINE="$LINE" ML2014_IMAGE="$IMAGE" PACKAGES_DIR="$work/packages" \
  CSS34_SAVE_DOWNLOADS="$work/downloads" bash "$ROOT/builder/docker/build.sh"

# Every repository of the build: "<dir> <url> <commit>".
list_repos() {
  local dir url
  echo "$ROOT/sourcemod $(git -C "$ROOT" config -f .gitmodules submodule.sourcemod.url) $(git -C "$ROOT/sourcemod" rev-parse HEAD)"
  # linux.sh first checks out the superproject's gitlink, then the pinned commit.
  echo "- $(git -C "$ROOT" config -f .gitmodules submodule.sourcemod.url) $(git -C "$ROOT" ls-tree HEAD sourcemod | awk '{print $3}')"
  for dir in "$ROOT/sourcemod" "$ROOT"/deps/*/; do
    dir="${dir%/}"
    [[ -e "$dir/.git" ]] || continue
    if [[ "$dir" != "$ROOT/sourcemod" ]]; then
      url="$(git -C "$dir" config remote.origin.url)"
      echo "$dir $url $(git -C "$dir" rev-parse HEAD)"
    fi
    git -C "$dir" submodule foreach --quiet --recursive \
      'echo "$toplevel/$sm_path $(git config remote.origin.url) $(git rev-parse HEAD)"'
  done
}

mirror_of() { # url -> owner/repo
  local u="${1%/}"
  [[ "$u" == https://github.com/* ]] || die "not a github.com URL: $1"
  u="${u#https://github.com/}"
  echo "${u%.git}"
}

echo "==> Mirroring pinned commits"
list_repos | sort -u >"$work/repos.txt"
while read -r dir url commit; do
  name="$(mirror_of "$url")"
  mirror="$work/git/$name"
  if [[ ! -d "$mirror" ]]; then
    git init -q --bare "$mirror"
    git -C "$mirror" config uploadpack.allowAnySHA1InWant true
    git -C "$mirror" config uploadpack.allowReachableSHA1InWant true
    ln -sfn "$(basename "$name")" "$mirror.git"   # URLs with and without .git
  fi
  if [[ "$dir" == - ]]; then
    git -C "$mirror" fetch -q --depth 1 "$url" "$commit"
  else
    git -C "$mirror" fetch -q --depth 1 "file://$dir" "$commit"
  fi
  git -C "$mirror" update-ref "refs/heads/css34/$commit" "$commit"
  # A plain `git clone` takes HEAD; clone_repo then fetches the pinned commit.
  git -C "$mirror" symbolic-ref HEAD >/dev/null 2>&1 &&
    git -C "$mirror" rev-parse -q --verify HEAD >/dev/null ||
    git -C "$mirror" symbolic-ref HEAD "refs/heads/css34/$commit"
  echo "    ${name} ${commit}"
done <"$work/repos.txt"

for mirror in "$work"/git/*/*; do
  [[ -d "$mirror" && ! -L "$mirror" ]] || continue
  name="${mirror#"$work/git/"}"
  git -C "$mirror" gc -q --prune=now
  tar -C "$work/git" -cf - "$name" "$name.git" | zstd -q -T0 "-$ZSTD_LEVEL" -o "$assets/git-${name//\//-}.tar.zst"
done

for f in "$work"/downloads/*; do
  cp -f "$f" "$assets/dl-$(basename "$f")"
done
[[ -n "$(ls "$work/downloads")" ]] || die "the build recorded no downloads (deps were cached?)"

echo "==> Saving the build image ${IMAGE} as ${FREEZE_TAG}"
docker_cmd image inspect "$IMAGE" >/dev/null 2>&1 || docker_cmd pull "$IMAGE"
docker_cmd tag "$IMAGE" "$FREEZE_TAG"
image_id="$(docker_cmd image inspect --format '{{.Id}}' "$FREEZE_TAG")"
docker_cmd save "$FREEZE_TAG" | zstd -q -T0 "-$ZSTD_LEVEL" -o "$assets/build-image.tar.zst"

cp -f "$work"/packages/*.tar.gz "$assets/"

echo "==> MANIFEST.json"
LINE="$LINE" IMAGE="$IMAGE" FREEZE_TAG="$FREEZE_TAG" IMAGE_ID="$image_id" \
  IMAGE_REGISTRY_REF="${IMAGE_REGISTRY_REF:-}" ROOT="$ROOT" WORK="$work" ASSETS="$assets" \
  python3 - <<'PY'
import hashlib, json, os, subprocess
from pathlib import Path

root, work, assets = Path(os.environ["ROOT"]), Path(os.environ["WORK"]), Path(os.environ["ASSETS"])

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def git(*args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()

repos = {}
for line in (work / "repos.txt").read_text().splitlines():
    d, url, commit = line.split()
    repos.setdefault(url.rstrip("/").removesuffix(".git"), set()).add(commit)
toolchain = {}
for line in (root / "builder/windows-toolchain.env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.split("=", 1)
        toolchain[k.strip()] = v.strip().strip('"')
packages = {}
for p in sorted(assets / q.name for q in (work / "packages").glob("*.tar.gz")):
    m = subprocess.run(["tar", "-xzOf", str(p), "addons/sourcemod/css34-package.json"],
                       capture_output=True, text=True)
    if m.returncode:
        m = subprocess.run(["tar", "-xzOf", str(p), "addons/metamod/css34-package.json"],
                           capture_output=True, text=True, check=True)
    packages[p.name] = {"sha256": sha(p), "manifest": json.loads(m.stdout)}
manifest = {
    "line": os.environ["LINE"],
    "builder_commit": git("rev-parse", "HEAD"),
    "image": {"source": os.environ["IMAGE"], "tag": os.environ["FREEZE_TAG"], "id": os.environ["IMAGE_ID"],
              "registry": os.environ.get("IMAGE_REGISTRY_REF") or None},
    "repositories": {url: sorted(c) for url, c in sorted(repos.items())},
    "windows_toolchain": toolchain,
    "packages": packages,
    "assets": {p.name: sha(p) for p in sorted(assets.iterdir())},
}
(assets / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
(cd "$assets" && sha256sum -- * >SHA256SUMS)
echo "==> Inputs of ${LINE}: $assets"
ls -la "$assets"
