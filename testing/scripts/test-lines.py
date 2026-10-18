#!/usr/bin/env python3
"""Exercise pin generation and drift failures in an isolated repository copy."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LinesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("builder/lines.py", "builder/lines.json", "builder/versions.env",
                     "builder/generated/ci-matrix.json", "builder/generated/tag-map.sh",
                     "README.md",
                     "builder/checkout-deps.sh", "builder/write-build-stamps.sh",
                     "testing/scripts/check-version-copies.sh", "testing/versions/matrix.json",
                     ".github/workflows/build.yml", ".github/workflows/test-server.yml",
                     ".github/workflows/release.yml"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def run_command(self, command, success=True):
        result = subprocess.run([sys.executable, str(self.root / "builder/lines.py"), command],
                                cwd=self.temp.name, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_generation_is_repeatable(self):
        target = self.root / "builder/versions.env"
        original = target.read_bytes()
        target.unlink()
        self.run_command("gen")
        self.assertEqual(target.read_bytes(), original)
        self.run_command("gen")
        self.assertEqual(target.read_bytes(), original)
        self.run_command("check")

    def test_manual_edit_is_rejected_without_rewriting(self):
        target = self.root / "builder/versions.env"
        changed = target.read_text() + "\nSM_LATEST_REV=1\n"
        target.write_text(changed)
        self.assertIn("stale builder/versions.env", self.run_command("check", False).stderr)
        self.assertEqual(target.read_text(), changed)

    def test_pin_change_requires_generation_and_consumer_updates(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["pins"]["SM_LATEST"]["rev"] += 1
        target.write_text(json.dumps(data))
        self.assertIn("stale", self.run_command("check", False).stderr)
        self.run_command("gen")
        self.run_command("check")

    def test_malformed_sha_does_not_overwrite_generated_file(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["pins"]["MM_112"]["commit"] = "not-a-sha"
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("full SHA", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
