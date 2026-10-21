#!/usr/bin/env python3
"""Fail the manifest flag guard on a deliberately unsupported flag."""

from __future__ import annotations

import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import manifest_flag_guard as guard  # noqa: E402


# GCC accepts an unknown -Wno-* on an empty translation unit and reports the
# positive -W form immediately. Clang reports the -Wno- form immediately.
FAKE_CXX = """#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    -Wdeprecated-volatile|-Wsync-alignment|-Wno-clang-only)
      echo "g++: error: unrecognized command line option '$arg'" >&2
      exit 1
      ;;
    -ffail-other)
      echo "g++: error: internal compiler error" >&2
      exit 1
      ;;
  esac
done
exit 0
"""


class FlagGuardTest(unittest.TestCase):
    def test_drops_unsupported_and_keeps_known(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            compiler = Path(tmp) / "cxx"
            compiler.write_text(FAKE_CXX, encoding="utf-8")
            compiler.chmod(compiler.stat().st_mode | stat.S_IEXEC)
            kept = guard.css34_filter_flags(
                [str(compiler)],
                [
                    "-fPIC",
                    "-Wno-deprecated-volatile",
                    "-Wno-sync-alignment",
                    "-Wno-clang-only",
                    "-Wno-unused-variable",
                    "-fno-strict-aliasing",
                ],
            )
        self.assertEqual(
            kept,
            ["-fPIC", "-Wno-unused-variable", "-fno-strict-aliasing"],
        )

    def test_probe_failure_that_is_not_an_unknown_flag_aborts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            compiler = Path(tmp) / "cxx"
            compiler.write_text(FAKE_CXX, encoding="utf-8")
            compiler.chmod(compiler.stat().st_mode | stat.S_IEXEC)
            with self.assertRaises(SystemExit) as raised:
                guard.css34_filter_flags([str(compiler)], ["-ffail-other"])
        self.assertIn("not an unsupported-flag result", str(raised.exception))

    def test_patch_installs_guard_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "SdkHelpers.ambuild"
            # Match the real file's 8-space indent. dedent above used extra
            # indent so the loops survive; rewrite them to the real anchor.
            path.write_text(
                "import json\nimport os\n\n" + guard._OLD_LOOPS,
                encoding="utf-8",
            )
            guard.patch_sdkhelpers(path)
            text = path.read_text(encoding="utf-8")
            self.assertIn("def css34_supported_flags", text)
            self.assertIn(guard.MARKER, text)
            self.assertNotIn(guard._OLD_LOOPS, text)
            guard.patch_sdkhelpers(path)
            self.assertEqual(text, path.read_text(encoding="utf-8"))

    def test_real_compiler_drops_clang_only_flag_when_present(self) -> None:
        cxx = None
        for candidate in ("g++", "clang++"):
            found = subprocess.run(
                ["bash", "-lc", f"command -v {candidate}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
                text=True,
            )
            if found.returncode == 0 and found.stdout.strip():
                cxx = found.stdout.strip().splitlines()[-1]
                break
        if cxx is None:
            self.skipTest("no host C++ compiler")
        flag = "-Wno-deprecated-volatile"
        positive = subprocess.run(
            [cxx, "-Werror", "-Wdeprecated-volatile", "-fsyntax-only", "-x", "c++", "/dev/null"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        negative = subprocess.run(
            [cxx, "-Werror", flag, "-fsyntax-only", "-x", "c++", "/dev/null"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        kept = guard.css34_filter_flags([cxx], ["-fPIC", flag])
        self.assertIn("-fPIC", kept)
        # GCC reports -Wno-deprecated-volatile only via the positive spelling.
        if positive.returncode != 0 or negative.returncode != 0:
            self.assertNotIn(flag, kept)
        else:
            self.assertIn(flag, kept)


if __name__ == "__main__":
    unittest.main()
