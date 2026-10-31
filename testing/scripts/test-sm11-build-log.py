#!/usr/bin/env python3
"""Run check-sm11-build-log.sh on synthetic SM 1.11 build logs."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "testing/scripts/check-sm11-build-log.sh"

GOOD = """==> Building Metamod:Source (css34 episode1, 1.10) in /workspace/deps/mmsource-1.10
WARNING: Running pip as the 'root' user can result in broken permissions
==> Using Metamod core-css34legacy include path for ep1: /workspace/deps/mmsource-1.10/core-css34legacy
==> Using Metamod core include path for episode1: /workspace/deps/mmsource-1.12-frozen/core
==> Using Metamod core-css34legacy include path for ep1: /workspace/deps/mmsource-1.10/core-css34legacy
==> Using Metamod core include path for episode1: /workspace/deps/mmsource-1.12-frozen/core
"""


class BuildLogTest(unittest.TestCase):
    def run_check(self, text):
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as fh:
            fh.write(text)
        self.addCleanup(Path(fh.name).unlink)
        return subprocess.run(["bash", str(SCRIPT), fh.name, "sm11-oldstable"],
                              capture_output=True, text=True)

    def test_pinned_layout_passes_and_ignores_pip_warning(self):
        res = self.run_check(GOOD)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("0 WARN lines", res.stdout)

    def test_patcher_warn_fails(self):
        res = self.run_check(GOOD + "==> WARN: MM Versioning detached-HEAD pattern not found (continuing)\n")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("WARN line(s)", res.stderr)

    def test_missing_or_wrong_include_root_fails(self):
        for text, needle in (
            (GOOD.replace("core-css34legacy include path for ep1", "core include path for ep1"),
             "ep1 includes"),
            (GOOD.replace("mmsource-1.12-frozen/core", "mmsource-1.10/core"), "episode1 includes"),
            (GOOD + "==> Using Metamod core include path for episode1: /workspace/deps/mmsource-1.10/core\n",
             "another Metamod root"),
        ):
            with self.subTest(needle=needle):
                res = self.run_check(text)
                self.assertNotEqual(res.returncode, 0)
                self.assertIn(needle, res.stderr)

    def test_missing_log_fails(self):
        res = subprocess.run(["bash", str(SCRIPT), "/nonexistent/build.log"], capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0)


if __name__ == "__main__":
    unittest.main()
