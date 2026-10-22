#!/usr/bin/env python3
"""Drop hl2sdk-manifest compiler flags the build compiler does not accept.

Upstream manifests (ebd6e10, "Silent few s1 warnings on linux") add flags such
as -Wno-deprecated-volatile that GCC 10 rejects. SdkHelpers.ambuild applies
every manifest cflag/cxxflag under -Werror, so one unknown flag fails the
build. Each flag is probed with:

    $CXX -Werror <flag> -fsyntax-only -x c++ /dev/null

GCC still exits 0 for an unknown -Wno-* on that empty input, and only reports
the flag once another diagnostic is emitted. Flags of the form -Wno-* are
therefore also probed as -W*. Unsupported flags are omitted and a note is
printed. Any other probe failure aborts the build.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

MARKER = "css34: drop compiler flags this compiler rejects"

# The two loops in hl2sdk-manifests SdkHelpers.configureCxx (8-space indent).
_OLD_LOOPS = """        # cflags
        for cflag in SdkHelpers.getLists(sdk, 'cflags', cxx):
            cxx.cflags += [cflag]

        # cxxflags
        for cxxflag in SdkHelpers.getLists(sdk, 'cxxflags', cxx):
            cxx.cxxflags += [cxxflag]
"""

_NEW_LOOPS = """        # cflags
        # css34: drop compiler flags this compiler rejects
        for cflag in css34_supported_flags(cxx, SdkHelpers.getLists(sdk, 'cflags', cxx)):
            cxx.cflags += [cflag]

        # cxxflags
        for cxxflag in css34_supported_flags(cxx, SdkHelpers.getLists(sdk, 'cxxflags', cxx)):
            cxx.cxxflags += [cxxflag]
"""

_HELPER = '''
def css34_probe_flag(compiler, flag):
    import subprocess
    proc = subprocess.run(
        compiler + ['-Werror', flag, '-fsyntax-only', '-x', 'c++', '/dev/null'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    err = proc.stderr.decode('utf-8', 'replace')
    if proc.returncode == 0:
        return True, err
    low = err.lower()
    unsupported = (
        'unrecognized command' in low
        or 'unknown warning option' in low
        or 'unknown argument' in low
    )
    if unsupported:
        return False, err
    raise SystemExit(
        'css34: compiler flag probe failed for %s (not an unsupported-flag result):\\n%s'
        % (flag, err)
    )

def css34_supported_flags(cxx, flags):
    # css34: drop compiler flags this compiler rejects
    import os
    compiler = os.environ.get('CXX', '').split()
    if not compiler:
        argv = getattr(cxx, 'cxx_argv', None) or ['g++']
        compiler = [argv[0]]
    kept = []
    for flag in flags:
        ok, err = css34_probe_flag(compiler, flag)
        # GCC accepts an unknown -Wno-* on an empty file and only reports it
        # once some other diagnostic is emitted. Probe the positive -W form,
        # which fails immediately, so ebd6e10 flags are dropped on GCC 10.
        if ok and flag.startswith('-Wno-'):
            positive = '-W' + flag[len('-Wno-'):]
            ok, err = css34_probe_flag(compiler, positive)
        if ok:
            kept.append(flag)
            continue
        lines = [line for line in err.splitlines() if line.strip()]
        tail = lines[-1] if lines else 'unsupported'
        print('==> css34: dropping unsupported compiler flag %s (%s)' % (flag, tail))
    return kept
'''


def _probe_flag(compiler: list[str], flag: str) -> tuple[bool, str]:
    proc = subprocess.run(
        compiler + ["-Werror", flag, "-fsyntax-only", "-x", "c++", "/dev/null"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    err = proc.stderr.decode("utf-8", "replace")
    if proc.returncode == 0:
        return True, err
    low = err.lower()
    unsupported = (
        "unrecognized command" in low
        or "unknown warning option" in low
        or "unknown argument" in low
    )
    if unsupported:
        return False, err
    raise SystemExit(
        "css34: compiler flag probe failed for %s (not an unsupported-flag result):\n%s"
        % (flag, err)
    )


def css34_filter_flags(compiler: list[str], flags: list[str]) -> list[str]:
    """Probe flags with an explicit compiler argv. Used by the unit test.

    The copy injected into SdkHelpers (css34_supported_flags) keeps the same
    accept/drop/abort rules, including the positive -W probe for -Wno-*.
    """
    kept: list[str] = []
    for flag in flags:
        ok, err = _probe_flag(compiler, flag)
        if ok and flag.startswith("-Wno-"):
            positive = "-W" + flag[len("-Wno-") :]
            ok, err = _probe_flag(compiler, positive)
        if ok:
            kept.append(flag)
            continue
        lines = [line for line in err.splitlines() if line.strip()]
        tail = lines[-1] if lines else "unsupported"
        print("==> css34: dropping unsupported compiler flag %s (%s)" % (flag, tail))
    return kept


def patch_sdkhelpers(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if MARKER in text and "def css34_supported_flags" in text:
        print(f"==> manifest flag guard already present in {path}")
        return
    if _OLD_LOOPS not in text:
        raise SystemExit(f"FAIL: SdkHelpers cflags loop not found in {path}")
    if "import os\n" not in text:
        raise SystemExit(f"FAIL: SdkHelpers import os anchor not found in {path}")
    text = text.replace("import os\n", "import os\n" + _HELPER, 1)
    text = text.replace(_OLD_LOOPS, _NEW_LOOPS, 1)
    path.write_text(text, encoding="utf-8")
    print(f"==> Installed manifest compiler-flag guard in {path}")


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} SdkHelpers.ambuild", file=sys.stderr)
        return 2
    patch_sdkhelpers(Path(argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
