#!/usr/bin/env bash
# Pre-dual-ABI i386 libstdc++4.9 for logic.so (gcc-8 static archive leaks __cxx11).
# Core/extensions still use host gcc-9/clang-9; logic alone uses this tree.
set -euo pipefail

DEPS_DIR="${1:?deps directory required}"
SYSROOT="$DEPS_DIR/sysroot-i386"
DEBIAN_ARCHIVE="${DEBIAN_ARCHIVE:-http://archive.debian.org/debian}"
POOL="${DEBIAN_ARCHIVE}/pool/main"
GCC49_VER="${GCC49_VER:-4.9.2-10+deb8u1}"
MARKER="$SYSROOT/.installed-jessie-gcc49-i386"

if [[ -f "$MARKER" ]]; then
  echo "==> gcc-4.9 i386 logic sysroot already installed at $SYSROOT" >&2
  exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fetch_deb() {
  local url="$1"
  local out="$2"
  if [[ ! -f "$out" ]]; then
    curl -fsSL -o "$out" "$url"
  fi
  echo "$out"
}

echo "==> Installing jessie gcc-4.9 i386 logic sysroot under $SYSROOT" >&2
rm -rf "$SYSROOT"
mkdir -p "$SYSROOT"

libstdcxx="$(fetch_deb "${POOL}/g/gcc-4.9/libstdc++-4.9-dev_${GCC49_VER}_amd64.deb" "$TMP/libstdc++-4.9-dev.deb")"
lib32stdcxx="$(fetch_deb "${POOL}/g/gcc-4.9/lib32stdc++-4.9-dev_${GCC49_VER}_amd64.deb" "$TMP/lib32stdc++-4.9-dev.deb")"
libgcc="$(fetch_deb "${POOL}/g/gcc-4.9/libgcc-4.9-dev_${GCC49_VER}_amd64.deb" "$TMP/libgcc-4.9-dev.deb")"
lib32gcc="$(fetch_deb "${POOL}/g/gcc-4.9/lib32gcc-4.9-dev_${GCC49_VER}_amd64.deb" "$TMP/lib32gcc-4.9-dev.deb")"

for deb in "$libstdcxx" "$lib32stdcxx" "$libgcc" "$lib32gcc"; do
  dpkg-deb -x "$deb" "$SYSROOT"
done

if [[ ! -f "$SYSROOT/usr/lib/gcc/x86_64-linux-gnu/4.9/32/libstdc++.a" \
  && ! -f "$SYSROOT/usr/lib/gcc/i686-linux-gnu/4.9/libstdc++.a" ]]; then
  echo "jessie gcc-4.9 libstdc++.a missing after sysroot install" >&2
  find "$SYSROOT/usr/lib/gcc" -name 'libstdc++.a' 2>/dev/null || true
  exit 1
fi

cxx11_in_archive="$(
  nm "$SYSROOT/usr/lib/gcc/x86_64-linux-gnu/4.9/32/libstdc++.a" 2>/dev/null \
    | grep -c '__cxx11' || true
)"
if [[ "${cxx11_in_archive:-0}" -gt 0 ]]; then
  echo "gcc-4.9 libstdc++.a unexpectedly contains __cxx11 symbols" >&2
  exit 1
fi

cat > "$DEPS_DIR/sysroot-i386.env" <<EOF
export SM_I386_SYSROOT="$SYSROOT"
export SM_LOGIC_CXX_SYSROOT="$SYSROOT"
EOF

date -u > "$MARKER"
echo "==> Logic sysroot ready: $SYSROOT" >&2
ls -la "$SYSROOT/usr/lib/gcc/x86_64-linux-gnu/4.9/32/libstdc++.a" 2>/dev/null \
  || ls -la "$SYSROOT/usr/lib/gcc/i686-linux-gnu/4.9/libstdc++.a" >&2
