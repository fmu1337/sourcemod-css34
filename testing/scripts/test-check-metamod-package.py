#!/usr/bin/env python3
"""Unit tests for check-metamod-package.sh validation and failure cases."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
CHECK_SCRIPT = os.path.join(ROOT, "testing", "scripts", "check-metamod-package.sh")


class TestCheckMetamodPackage(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp_dir)

    def _create_mock_pkg(self, commit="80e8ff0be3b62386bbd6f937e97b819ef8be6dd2", version="1.10.7-git976"):
        pkg_staging = os.path.join(self.tmp_dir, "pkg")
        mm_dir = os.path.join(pkg_staging, "addons", "metamod")
        bin_dir = os.path.join(mm_dir, "bin")
        os.makedirs(bin_dir)

        with open(os.path.join(pkg_staging, "addons", "metamod.vdf"), "w") as f:
            f.write('"Plugin"\n{\n  "file" "addons/metamod/bin/server"\n}\n')

        manifest = {
            "metamod_binary": "metamod.1.ep1",
            "mm_version": version,
            "mm_commit": commit,
        }
        with open(os.path.join(mm_dir, "css34-package.json"), "w") as f:
            json.dump(manifest, f)

        for fname in ["metamod.1.ep1.so", "server.so", "server_i486.so"]:
            open(os.path.join(bin_dir, fname), "w").close()

        tar_path = os.path.join(self.tmp_dir, "mmsource-test.tar.gz")
        subprocess.run(
            ["tar", "-czf", tar_path, "-C", pkg_staging, "addons"],
            check=True,
        )
        return tar_path

    def test_check_metamod_package_mismatched_commit_fails(self):
        pkg_path = self._create_mock_pkg(commit="80e8ff0be3b62386bbd6f937e97b819ef8be6dd2")
        env = os.environ.copy()
        env["MM_PACKAGE"] = pkg_path
        env["EXPECTED_MM_COMMIT"] = "badcommit123456789012345678901234567890"

        res = subprocess.run(
            [CHECK_SCRIPT],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("FAIL: manifest mm_commit", res.stderr)

    def test_check_metamod_package_mismatched_rev_fails(self):
        pkg_path = self._create_mock_pkg(version="1.10.7-git976")
        env = os.environ.copy()
        env["MM_PACKAGE"] = pkg_path
        env["EXPECTED_MM_REV"] = "9999"

        res = subprocess.run(
            [CHECK_SCRIPT],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("FAIL: manifest mm_version", res.stderr)


if __name__ == "__main__":
    unittest.main()
