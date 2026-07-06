#!/usr/bin/env bash
set -euo pipefail

DEPS_DIR="${1:?deps directory required}"
CLANG_DIR="$DEPS_DIR/clang-9"
LIBTINFO_DIR="$DEPS_DIR/libtinfo5"
WRAPPER_DIR="$DEPS_DIR/clang9-wrappers"
CLANG_ARCHIVE="${CLANG_ARCHIVE:-clang-9-ubuntu-14.04-m.tar.xz}"
CLANG_URL="${CLANG_URL:-https://bitbucket.org/rom4s/other.get/downloads/$CLANG_ARCHIVE}"
LIBTINFO_DEB_URL="${LIBTINFO_DEB_URL:-http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.2-0ubuntu2_amd64.deb}"
ENV_FILE="$DEPS_DIR/clang9.env"
CONF_FILE="$DEPS_DIR/clang9.conf"

mkdir -p "$DEPS_DIR" "$WRAPPER_DIR"

if [ ! -x "$CLANG_DIR/usrbin/clang-9" ]; then
  echo "==> Installing rom4s clang-9 toolchain" >&2
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/$CLANG_ARCHIVE" "$CLANG_URL"
  rm -rf "$CLANG_DIR"
  tar -xJf "$tmp/$CLANG_ARCHIVE" -C "$DEPS_DIR"
  rm -rf "$tmp"
fi

if [ ! -f "$LIBTINFO_DIR/lib/x86_64-linux-gnu/libtinfo.so.5" ]; then
  echo "==> Installing libtinfo.so.5 for clang-9" >&2
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/libtinfo5.deb" "$LIBTINFO_DEB_URL"
  rm -rf "$LIBTINFO_DIR"
  mkdir -p "$LIBTINFO_DIR"
  dpkg-deb -x "$tmp/libtinfo5.deb" "$LIBTINFO_DIR"
  rm -rf "$tmp"
fi

detect_cpp32_isystem() {
  local dir
  for dir in \
    /usr/include/x86_64-linux-gnu/c++/9/32 \
    /usr/include/i386-linux-gnu/c++/9/i686-linux-gnu \
    /usr/include/i386-linux-gnu/c++/9; do
    if [ -f "$dir/bits/c++config.h" ]; then
      echo "$dir"
      return 0
    fi
  done
  return 1
}

CPP32_ISYSTEM="$(detect_cpp32_isystem || true)"
if [ -z "$CPP32_ISYSTEM" ]; then
  echo "Could not locate gcc-9 32-bit libstdc++ headers." >&2
  exit 1
fi

GCC_INSTALL_DIR="/usr/lib/gcc/x86_64-linux-gnu/9"
if [ ! -d "$GCC_INSTALL_DIR" ]; then
  echo "Could not locate gcc-9 install dir at $GCC_INSTALL_DIR." >&2
  exit 1
fi

cat > "$CONF_FILE" <<EOF
CPP32_ISYSTEM="$CPP32_ISYSTEM"
GCC_INSTALL_DIR="$GCC_INSTALL_DIR"
EOF

cat > "$WRAPPER_DIR/clang-9" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REAL="$(cd "$(dirname "$0")/../clang-9/usrbin" && pwd)/clang-9"
exec "$REAL" "$@"
EOF

cat > "$WRAPPER_DIR/clang++-9" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REAL="$(cd "$(dirname "$0")/../clang-9/usrbin" && pwd)/clang++-9"
CONF="$(cd "$(dirname "$0")/.." && pwd)/clang9.conf"
# shellcheck source=/dev/null
source "$CONF"

use_m32=0
compile_only=0
for arg in "$@"; do
  if [ "$arg" = "-m32" ]; then
    use_m32=1
  elif [ "$arg" = "-c" ]; then
    compile_only=1
  fi
done

extra=()
if [ "$use_m32" -eq 1 ]; then
  extra+=(
    -stdlib=libstdc++
  )
  if [ "$compile_only" -eq 1 ]; then
    extra+=(
      -isystem /usr/include/c++/9
      -isystem "$CPP32_ISYSTEM"
    )
  else
    extra+=(-L"$GCC_INSTALL_DIR/32")
  fi
elif [ "$compile_only" -eq 0 ]; then
  extra+=(-L"$GCC_INSTALL_DIR")
fi

exec "$REAL" "${extra[@]}" "$@"
EOF

chmod +x "$WRAPPER_DIR/clang-9" "$WRAPPER_DIR/clang++-9"

cat > "$ENV_FILE" <<EOF
export PATH="$WRAPPER_DIR:$CLANG_DIR/usrbin:\$PATH"
export LD_LIBRARY_PATH="$LIBTINFO_DIR/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH:-}"
EOF

# shellcheck source=/dev/null
source "$ENV_FILE"

if ! clang-9 --version >/dev/null 2>&1; then
  echo "clang-9 failed to start after installation." >&2
  exit 1
fi

if ! clang++-9 -x c++ - <<<'int main(){return 0;}' -o /dev/null 2>/dev/null; then
  echo "clang++-9 failed to link a test C++ binary." >&2
  exit 1
fi

if ! echo '#include <cstdlib>' | clang++-9 -m32 -x c++ - -c -o /dev/null 2>/dev/null; then
  echo "clang++-9 failed to compile a 32-bit C++ test translation unit." >&2
  exit 1
fi

echo "==> clang-9 ready: $(clang-9 --version | head -1)" >&2
echo "==> Using 32-bit libstdc++ headers: $CPP32_ISYSTEM" >&2
