#!/usr/bin/env python3
"""Unit tests for check-metamod-package.sh and verify-line-metamod-packages.sh."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
CHECK_SCRIPT = os.path.join(ROOT, "testing", "scripts", "check-metamod-package.sh")
VERIFY_SCRIPT = os.path.join(ROOT, "testing", "scripts", "verify-line-metamod-packages.sh")


class TestCheckMetamodPackage(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp_dir)

    def _create_mock_pkg(self, commit="80e8ff0be3b62386bbd6f937e97b819ef8be6dd2", version="1.10.7-git976"):
        pkg_staging = os.path.join(self.tmp_dir, "pkg_" + version)
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

        rev = version.split("-git")[-1] if "-git" in version else "976"
        ver_base = "1.10.7" if "1.10" in version else "1.12.0"
        pkg_filename = f"mmsource-{ver_base}-git{rev}-css34-linux.tar.gz"
        tar_path = os.path.join(self.tmp_dir, pkg_filename)
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

    def test_verify_line_metamod_packages_missing_secondary_fails(self):
        # Create valid tar.gz for primary MM 1.10 package, omitting secondary
        self._create_mock_pkg(commit="80e8ff0be3b62386bbd6f937e97b819ef8be6dd2", version="1.10.7-git976")

        mock_check_path = os.path.join(self.tmp_dir, "mock-check.sh")
        with open(mock_check_path, "w") as f:
            f.write("#!/usr/bin/env bash\nexit 0\n")
        os.chmod(mock_check_path, 0o755)

        env = os.environ.copy()
        env["CHECK_METAMOD_SCRIPT"] = mock_check_path

        res = subprocess.run(
            [VERIFY_SCRIPT, "sm11-oldstable", self.tmp_dir, os.path.join(ROOT, "builder")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=ROOT,
            env=env,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("FAIL: expected secondary Metamod package", res.stderr)

    def test_verify_line_metamod_packages_both_present_passes(self):
        # Create valid tar.gz for primary MM 1.10 and secondary MM 1.12 frozen
        self._create_mock_pkg(commit="80e8ff0be3b62386bbd6f937e97b819ef8be6dd2", version="1.10.7-git976")
        self._create_mock_pkg(commit="75dd7b26fe92e535a11f0318ead73c3e05130d0b", version="1.12.0-git1227")

        mock_check_path = os.path.join(self.tmp_dir, "mock-check.sh")
        with open(mock_check_path, "w") as f:
            f.write("#!/usr/bin/env bash\nexit 0\n")
        os.chmod(mock_check_path, 0o755)

        env = os.environ.copy()
        env["CHECK_METAMOD_SCRIPT"] = mock_check_path

        res = subprocess.run(
            [VERIFY_SCRIPT, "sm11-oldstable", self.tmp_dir, os.path.join(ROOT, "builder")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=ROOT,
            env=env,
        )
        self.assertEqual(res.returncode, 0, msg=f"Stderr: {res.stderr}\nStdout: {res.stdout}")
        self.assertIn("OK: All expected Metamod packages for line sm11-oldstable verified successfully", res.stdout)

    def test_verify_line_metamod_packages_sm13_latest_passes(self):
        # Create primary MM 1.12 git1228 package for sm13-latest
        self._create_mock_pkg(commit="cb47755826fad1483291e5dc00222aa64303d12f", version="1.12.0-git1228")

        mock_check_path = os.path.join(self.tmp_dir, "mock-check.sh")
        with open(mock_check_path, "w") as f:
            f.write("#!/usr/bin/env bash\nexit 0\n")
        os.chmod(mock_check_path, 0o755)

        env = os.environ.copy()
        env["CHECK_METAMOD_SCRIPT"] = mock_check_path

        res = subprocess.run(
            [VERIFY_SCRIPT, "sm13-latest", self.tmp_dir, os.path.join(ROOT, "builder")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=ROOT,
            env=env,
        )
        self.assertEqual(res.returncode, 0, msg=f"Stderr: {res.stderr}\nStdout: {res.stdout}")
        self.assertIn("OK: All expected Metamod packages for line sm13-latest verified successfully", res.stdout)


if __name__ == "__main__":
    unittest.main()
