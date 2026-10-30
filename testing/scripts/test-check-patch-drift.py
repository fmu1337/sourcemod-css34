#!/usr/bin/env python3
"""Tests for builder/scripts/check-patch-drift.sh."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIFT_SCRIPT = ROOT / "builder/scripts/check-patch-drift.sh"


class CheckPatchDriftTest(unittest.TestCase):
    def test_sm12_acceptance_range(self):
        if os.environ.get("SKIP_NETWORK_TESTS") == "1":
            self.skipTest("SKIP_NETWORK_TESTS is set")
        result = subprocess.run([str(DRIFT_SCRIPT), "--range", "7253..7255", "--line", "sm12-latest"],
                                capture_output=True, text=True, timeout=900)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unknown_mode_and_invalid_range_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            for args in (["--dir", tmp, "--mode", "unknown"], ["--range", "7477"]):
                result = subprocess.run([str(DRIFT_SCRIPT)] + args, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)


    def test_help_option(self) -> None:
        result = subprocess.run(
            [str(DRIFT_SCRIPT), "--help"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("Dry-run css34 patch layer to detect patch anchor drift", result.stdout)

    def test_range_check_passes_on_valid_bump(self) -> None:
        if os.environ.get("SKIP_NETWORK_TESTS") == "1":
            self.skipTest("SKIP_NETWORK_TESTS is set")

        result = subprocess.run(
            [str(DRIFT_SCRIPT), "--range", "7472..7477", "--line", "sm13-latest"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("[OK] No patch drift detected", result.stdout)

    def test_artificially_broken_anchor_reports_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a mock SourceMod directory structure with a missing anchor
            sm_dir = Path(tmpdir) / "sourcemod"
            sm_dir.mkdir()
            manifests_dir = sm_dir / "hl2sdk-manifests/manifests"
            manifests_dir.mkdir(parents=True)
            (manifests_dir / "episode1.json").write_text('{"linux": {}}', encoding="utf-8")
            (sm_dir / "hl2sdk-manifests/SdkHelpers.ambuild").write_text("# empty ambuild\n", encoding="utf-8")

            # Create output.cpp with corrupted OnMapEnd anchor
            sdktools_dir = sm_dir / "extensions/sdktools"
            sdktools_dir.mkdir(parents=True)
            (sdktools_dir / "output.cpp").write_text(
                "void CorruptedFunction()\n{\n\t// missing OnMapEnd anchor\n}\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [str(DRIFT_SCRIPT), "--dir", str(sm_dir), "--mode", "sm13"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("FAIL: Patch drift detected", result.stderr)
            self.assertIn("apply-sourcemod-v112.sh", result.stderr)


if __name__ == "__main__":
    unittest.main()
