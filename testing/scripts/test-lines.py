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
                     "testing/scripts/check-version-copies.sh",
                     ".github/workflows/ci.yml",
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

    def test_pin_change_requires_generation_then_matches(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["pins"]["SM_LATEST"]["rev"] += 1
        target.write_text(json.dumps(data))
        self.assertIn("stale", self.run_command("check", False).stderr)
        self.run_command("gen")
        self.run_command("check")
        matrix = json.loads((self.root / "builder/generated/ci-matrix.json").read_text())
        sm12 = next(row for row in matrix["build"] if row["line"] == "sm12-latest")
        self.assertTrue(sm12["sm_expect"].endswith("." + str(data["pins"]["SM_LATEST"]["rev"])))
        readme = (self.root / "README.md").read_text()
        self.assertIn(sm12["sm_expect"], readme)
        tag_map = (self.root / "builder/generated/tag-map.sh").read_text()
        self.assertIn(sm12["sm_expect"] + "-mm1.12.0", tag_map)

    def test_debian_matrix_requires_new_os_and_drops_latest(self):
        matrix = json.loads((self.root / "builder/generated/ci-matrix.json").read_text())
        lines = ("sm11-oldstable", "sm12-latest", "sm13-latest")
        per_pr = ("centos:7", "ubuntu:24.04", "debian:13")
        weekly = ("debian:8", "debian:9", "debian:10", "debian:11",
                  "ubuntu:14.04", "ubuntu:16.04", "ubuntu:18.04", "rockylinux:9")
        pairs = [(row["line"], row["image_name"]) for row in matrix["debian"]]
        self.assertNotIn(("sm13-latest", "debian:latest"), pairs)
        self.assertNotIn(("sm13-latest", "debian:11"), pairs)
        for line in lines:
            for image in per_pr:
                self.assertIn((line, image), pairs)
            for image in weekly:
                self.assertNotIn((line, image), pairs)
        self.assertTrue(all("allow_failure" not in row for row in matrix["debian"]))
        self.assertTrue(all(row["image"] == matrix["images"][row["image_name"]] for row in matrix["debian"]))
        weekly_pairs = [(row["line"], row["image_name"]) for row in matrix["weekly"]]
        for line in lines:
            for image in weekly:
                self.assertIn((line, image), weekly_pairs)
        self.assertEqual([row["image_name"] for row in matrix["botplay"]], ["debian:11"] * 3)
        self.assertEqual([row["image_name"] for row in matrix["weekly_botplay"]], ["centos:7"] * 3)
        self.assertEqual([row["line"] for row in matrix["botplay"]], list(lines))
        self.assertTrue(all("@sha256:" in row["image"] for row in matrix["weekly"] + matrix["botplay"]))
        self.assertEqual([row["line"] for row in matrix["host"]], ["sm13-latest"])
        self.assertNotIn("rhel", matrix)
        for name in (".github/workflows/ci.yml", ".github/workflows/release.yml"):
            self.assertNotIn("sha256:", (self.root / name).read_text(), name)

    def test_duplicate_image_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["lines"]["sm12-latest"]["smoke"].append({"image": "ubuntu:24.04"})
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("lists image ubuntu:24.04 twice", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

    def test_known_bad_pointer_pin_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["pins"]["SM_LATEST"]["rev"] = 7245
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("known-bad tag", self.run_command("check", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

    def test_allow_failure_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["lines"]["sm13-latest"]["smoke"][0]["allow_failure"] = True
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("invalid smoke entry", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

    def test_unpinned_weekly_image_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["weekly_smoke"].append("debian:7")
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("not pinned", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

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
