#!/usr/bin/env bash
# AMBuild 2.x uses cxx_argv for linking and ignores compiler.linker_argv.
# css34 logic compiles with clang++-10 but must link with g++-9 + static libstdc++.a.
set -euo pipefail

ambuild_dir="${1:?ambuild directory required}"

patch_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if grep -q 'css34: honor compiler.linker_argv when set' "$file"; then
    return 0
  fi
  python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = """        if self.used_cxx_:
            self.linker_argv_ = self.compiler.cxx_argv
        else:
            self.linker_argv_ = self.compiler.cc_argv"""
new = """        # css34: honor compiler.linker_argv when set (logic: clang++ compile, g++ link)
        _linker = getattr(self.compiler, 'linker_argv', None)
        if self.used_cxx_:
            self.linker_argv_ = _linker if _linker else self.compiler.cxx_argv
        else:
            self.linker_argv_ = _linker if _linker else self.compiler.cc_argv"""
if old not in text:
    print(f'==> Skipping {path} (no linker_argv anchor)')
    sys.exit(0)
path.write_text(text.replace(old, new, 1))
print(f'==> Patched {path}')
PY
}

for ver in v2_0 v2_1 v2_2; do
  patch_file "$ambuild_dir/ambuild2/frontend/$ver/cpp/builders.py"
done
