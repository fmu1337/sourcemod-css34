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
use_m32=0
for arg in "$@"; do
  if [ "$arg" = "-m32" ]; then
    use_m32=1
    break
  fi
done
if [ "$use_m32" -eq 1 ]; then
  exec "$REAL" -L/usr/lib/gcc/x86_64-linux-gnu/9/32 "$@"
else
  exec "$REAL" -L/usr/lib/gcc/x86_64-linux-gnu/9 "$@"
fi
EOF

chmod +x "$WRAPPER_DIR/clang-9" "$WRAPPER_DIR/clang++-9"

cat > "$ENV_FILE" <<EOF
export PATH="$WRAPPER_DIR:$CLANG_DIR/usrbin:\$PATH"
export LD_LIBRARY_PATH="$LIBTINFO_DIR/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH"
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

echo "==> clang-9 ready: $(clang-9 --version | head -1)" >&2
