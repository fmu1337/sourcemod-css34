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
RESOLVE_SCRIPT = os.path.join(ROOT, "builder", "resolve-metamod-pins.py")


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

    def test_check_metamod_package_revision_prefix_is_not_a_match(self):
        pkg_path = self._create_mock_pkg(version="1.10.7-git9760")
        env = os.environ.copy()
        env.update(MM_PACKAGE=pkg_path, EXPECTED_MM_REV="976")
        res = subprocess.run([CHECK_SCRIPT], env=env, capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("does not have exact revision git976", res.stderr)

    def test_verify_unknown_line_rejected_before_checking_packages(self):
        self._create_mock_pkg()
        env = os.environ.copy()
        env["CHECK_METAMOD_SCRIPT"] = "/bin/true"
        res = subprocess.run([VERIFY_SCRIPT, "sm11-oldstabl", self.tmp_dir],
                             env=env, cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("unknown build line", res.stderr)
        self.assertNotIn("Checking primary", res.stdout)

    def test_secondary_reference_drives_checkout_builds_and_verifier(self):
        # Change to a different valid pin: consumers must stop selecting frozen.
        builder = os.path.join(self.tmp_dir, "builder")
        os.makedirs(builder)
        for name in ("py.sh", "lines.py", "resolve-metamod-pins.py"):
            shutil.copy(os.path.join(ROOT, "builder", name), builder)
        with open(os.path.join(ROOT, "builder", "lines.json")) as fh:
            data = json.load(fh)
        data["lines"]["sm11-oldstable"]["secondary_metamod"] = "MM_112"
        selected = data["pins"]["MM_112"]
        with open(os.path.join(builder, "lines.json"), "w") as fh:
            json.dump(data, fh)

        # The SM 1.11 build fails closed unless both resolved checkouts exist.
        os.makedirs(os.path.join(self.tmp_dir, data["pins"]["MM_110"]["dirname"], "core-css34legacy"))
        os.makedirs(os.path.join(self.tmp_dir, selected["dirname"], "core"), exist_ok=True)

        # Execute the production orchestration blocks with only the expensive
        # fetch/build functions stubbed; the actual resolver reads the fixture.
        for path, function, commit_arg in (
            ("builder/checkout-deps.sh", "fetch_and_patch_mms", 4),
            ("builder/run/linux.sh", "build_and_package_mm", 5),
            ("builder/run/windows.sh", "build_and_package_mm_win", 5),
        ):
            with self.subTest(path=path):
                with open(os.path.join(ROOT, path)) as fh:
                    source = fh.read()
                start = source.index('if [[ "${SOURCEMOD_MAJOR:-11}" -eq 11')
                block = source[start:source.index("\nelse\n", start)] + "\nfi\n"
                stub = function + '() { printf "%s\\n" "${' + str(commit_arg) + '}"; }\n'
                env = os.environ.copy()
                env.update(BUILDER_DIR=builder, DEPS_DIR=self.tmp_dir,
                           SOURCEMOD_MAJOR="11", CSS34_LINE="sm11-oldstable")
                res = subprocess.run(["bash", "-euo", "pipefail", "-c", stub + block],
                                     env=env, capture_output=True, text=True)
                self.assertEqual(res.returncode, 0, res.stderr)
                self.assertEqual(res.stdout.splitlines(),
                                 [data["pins"]["MM_110"]["commit"], selected["commit"]])

        # linux.sh must hand the resolved MM 1.12 checkout to configure, never MM 1.10.
        with open(os.path.join(ROOT, "builder/run/linux.sh")) as fh:
            source = fh.read()
        start = source.index('if [[ "${SOURCEMOD_MAJOR:-11}" -eq 11')
        block = source[start:source.index("\nelse\n", start)] + "\nfi\n"
        stub = "build_and_package_mm() { :; }\n"
        report = 'printf "%s|%s\\n" "$MM_MODERN_DIR" "$CSS34_MMS_LEGACY_CORE"\n'
        env = os.environ.copy()
        env.update(BUILDER_DIR=builder, DEPS_DIR=self.tmp_dir,
                   SOURCEMOD_MAJOR="11", CSS34_LINE="sm11-oldstable")
        res = subprocess.run(["bash", "-euo", "pipefail", "-c", stub + block + report],
                             env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "|".join([
            os.path.join(self.tmp_dir, selected["dirname"]),
            os.path.join(self.tmp_dir, data["pins"]["MM_110"]["dirname"], "core-css34legacy")]))
        shutil.rmtree(os.path.join(self.tmp_dir, selected["dirname"]))
        res = subprocess.run(["bash", "-euo", "pipefail", "-c", stub + block + report],
                             env=env, capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("FAIL: missing", res.stderr)

        self._create_mock_pkg()
        self._create_mock_pkg(commit=selected["commit"],
                              version="1.12.0-git" + str(selected["rev"]))
        env = os.environ.copy()
        env["CHECK_METAMOD_SCRIPT"] = "/bin/true"
        res = subprocess.run([VERIFY_SCRIPT, "sm11-oldstable", self.tmp_dir, builder],
                             env=env, cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("git1228-css34-linux.tar.gz", res.stdout)
        self.assertNotIn("git1227", res.stdout)

    def test_invalid_secondary_pin_is_rejected(self):
        with open(os.path.join(ROOT, "builder", "lines.json")) as fh:
            data = json.load(fh)
        data["lines"]["sm11-oldstable"]["secondary_metamod"] = "MM_MISSING"
        manifest = os.path.join(self.tmp_dir, "lines.json")
        with open(manifest, "w") as fh:
            json.dump(data, fh)
        res = subprocess.run(["python3", RESOLVE_SCRIPT, "sm11-oldstable",
                              "--manifest", manifest], capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("invalid secondary_metamod", res.stderr)
        self.assertEqual(res.stdout, "")

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
