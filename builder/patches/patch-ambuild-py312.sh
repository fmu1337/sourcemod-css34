#!/usr/bin/env bash
# AMBuild 2.2 still imports removed `imp` on Python 3.12+.
set -euo pipefail
AMBULD_DIR="${1:?ambuild directory}"
ctx="$AMBULD_DIR/ambuild2/context.py"
if [ ! -f "$ctx" ]; then
  exit 0
fi
if grep -q 'except ImportError:  # Python 3.12' "$ctx"; then
  exit 0
fi
if grep -q 'import os, sys, imp' "$ctx"; then
  sed -i 's/import os, sys, imp/import os, sys\ntry:\n    import imp\nexcept ImportError:  # Python 3.12+\n    imp = None/' "$ctx"
  echo "==> Patched ambuild for Python 3.12 (imp)"
fi
