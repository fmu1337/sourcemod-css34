# shellcheck shell=bash
# Pinned downloads for the builder (sourced; defines fetch_pinned).
#
#   fetch_pinned URL DEST SHA256 [NAME]
#
# NAME (default: the URL's basename) is the file's name in the input archive
# of a frozen line (T2.7):
#   CSS34_DOWNLOADS=DIR       take NAME from DIR instead of the network
#   CSS34_OFFLINE=1           never touch the network; NAME must be in DIR
#   CSS34_SAVE_DOWNLOADS=DIR  also copy every verified file to DIR/NAME
#                             (builder/freeze/collect-inputs.sh)
# The sha256 is checked whatever the source; a mismatch deletes DEST and fails.
fetch_pinned() {
  local url="$1" dest="$2" expect="$3" name="${4:-}" got
  [[ -n "$name" ]] || name="$(basename "$url")"
  if [[ -n "${CSS34_DOWNLOADS:-}" && -f "${CSS34_DOWNLOADS}/${name}" ]]; then
    cp -f "${CSS34_DOWNLOADS}/${name}" "$dest"
  elif [[ "${CSS34_OFFLINE:-0}" == 1 ]]; then
    echo "FAIL: offline build: ${name} is not in CSS34_DOWNLOADS=${CSS34_DOWNLOADS:-<unset>}" >&2
    exit 1
  else
    curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
  fi
  got="$(sha256sum "$dest" | awk '{print $1}')"
  if [[ "$got" != "$expect" ]]; then
    echo "FAIL: sha256 mismatch for ${dest}" >&2
    echo "  url:      ${url}" >&2
    echo "  expected: ${expect}" >&2
    echo "  got:      ${got}" >&2
    rm -f "$dest"
    exit 1
  fi
  if [[ -n "${CSS34_SAVE_DOWNLOADS:-}" ]]; then
    mkdir -p "${CSS34_SAVE_DOWNLOADS}"
    cp -f "$dest" "${CSS34_SAVE_DOWNLOADS}/${name}"
  fi
}

# AMBuild's pyproject.toml builds with setuptools, which pip's build isolation
# would otherwise take from PyPI, unpinned. Fetch one pinned wheel into
# DEPS/wheels; install AMBuild with: pip install --no-index --find-links DEPS/wheels
CSS34_SETUPTOOLS_WHEEL="setuptools-80.9.0-py3-none-any.whl"
css34_fetch_build_wheels() {
  local deps="$1"
  mkdir -p "$deps/wheels"
  [[ -f "$deps/wheels/$CSS34_SETUPTOOLS_WHEEL" ]] && return 0
  fetch_pinned \
    "https://files.pythonhosted.org/packages/a3/dc/17031897dae0efacfea57dfd3a82fdd2a2aeb58e0ff71b77b87e44edc772/$CSS34_SETUPTOOLS_WHEEL" \
    "$deps/wheels/$CSS34_SETUPTOOLS_WHEEL" 062d34222ad13e0cc312a4c02d73f059e86a4acbfbdea8f8f76b28c99f306922
}
