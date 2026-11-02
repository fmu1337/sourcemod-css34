#!/usr/bin/env python3
"""Tests for builder/scripts/check-patch-drift.sh (patch series, T3.4)."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIFT_SCRIPT = ROOT / "builder/scripts/check-patch-drift.sh"
GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")


def drift(*args, timeout=None):
    return subprocess.run([str(DRIFT_SCRIPT), *args], capture_output=True, text=True,
                          timeout=timeout, env=GIT_ENV)


class CheckPatchDriftTest(unittest.TestCase):
    def test_help_option(self):
        result = drift("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Dry-run a css34 patch series to detect upstream drift", result.stdout)

    def test_unknown_mode_series_and_invalid_range_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            for args in (["--dir", tmp, "--mode", "sm13"], ["--range", "7477"],
                         ["--dir", tmp, "--series", "no-such-line"], ["--bogus"]):
                with self.subTest(args=args):
                    self.assertNotEqual(drift(*args).returncode, 0)

    def test_directory_drift_names_the_patch_and_leaves_the_target_alone(self):
        # A Metamod-shaped checkout whose AMBuildScript is not the pinned one:
        # the MM_112 series' first patch cannot apply (no blob for --3way either).
        with tempfile.TemporaryDirectory() as tmp:
            mm = Path(tmp) / "metamod"
            (mm / "core").mkdir(parents=True)
            (mm / "core/ISmmAPI.h").write_text("// api\n")
            (mm / "AMBuildScript").write_text("# drifted upstream build script\n")
            (mm / "hl2sdk-manifests").mkdir()
            for repo in (mm / "hl2sdk-manifests", mm):
                subprocess.run(["git", "init", "-q", str(repo)], check=True, env=GIT_ENV)
            (mm / "hl2sdk-manifests/SdkHelpers.ambuild").write_text("# helpers\n")
            subprocess.run(["git", "-C", str(mm / "hl2sdk-manifests"), "add", "-A"], check=True, env=GIT_ENV)
            subprocess.run(["git", "-C", str(mm / "hl2sdk-manifests"), "commit", "-qm", "base"],
                           check=True, env=GIT_ENV)
            subprocess.run(["git", "-C", str(mm), "add", "AMBuildScript", "core"], check=True, env=GIT_ENV)
            subprocess.run(["git", "-C", str(mm), "commit", "-qm", "base"], check=True, env=GIT_ENV)
            result = drift("--dir", str(mm))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("FAIL: Patch drift detected", result.stderr)
            self.assertIn("Series: MM_112  Patch: hl2sdk-manifests/0001-episode1-defines.patch",
                          result.stderr)
            self.assertEqual((mm / "AMBuildScript").read_text(), "# drifted upstream build script\n")


@unittest.skipIf(os.environ.get("SKIP_NETWORK_TESTS") == "1", "SKIP_NETWORK_TESTS is set")
class CheckPatchDriftNetworkTest(unittest.TestCase):
    def test_sm13_range_applies(self):
        result = drift("--range", "7472..7477", "--line", "sm13-latest", timeout=900)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("[OK] No patch drift detected"), 2)

    def test_sm12_before_the_onmapend_change_is_drift(self):
        # 7253 predates the OnMapEnd List<omg_hooks *> fix the 7257 series carries.
        result = drift("--sm-commit", "7253", "--line", "sm12-latest", timeout=900)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Patch: sourcemod/0007-sdktools-onmapend-list.patch", result.stderr)


if __name__ == "__main__":
    unittest.main()
