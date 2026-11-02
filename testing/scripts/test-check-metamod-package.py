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


def mm_block(path):
    """The Metamod orchestration of a builder script, as the build runs it."""
    with open(os.path.join(ROOT, path)) as fh:
        source = fh.read()
    if path.endswith("checkout-deps.sh"):
        start = source.index('fetch_and_patch_mms "$MMS_DIRNAME"')
        end = source.index('done <<< "$mm_inputs"', start) + len('done <<< "$mm_inputs"')
        return source[start:end] + "\n"
    start = source.index('mm_extra="$(')
    end = source.index('done <<< "$mm_inputs"', start) + len('done <<< "$mm_inputs"')
    return source[start:end] + "\n"


def mms_env(pin):
    """resolve-version.sh's primary Metamod variables for a pin."""
    return {"MMS_DIRNAME": pin["dirname"], "MMS_MODE": pin["mode"], "MMS_BRANCH": pin["branch"],
            "MMS_COMMIT": pin["commit"], "MMS_GIT_REV": str(pin["rev"])}


class TestCheckMetamodPackage(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp_dir)

    def _create_mock_pkg(self, commit="80e8ff0be3b62386bbd6f937e97b819ef8be6dd2", version="1.10.7-git976",
                         bins=None, legacy_core=b"", legacy_bridge=None):
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
        if legacy_bridge is not None:
            manifest["legacy_bridge"] = legacy_bridge
        with open(os.path.join(mm_dir, "css34-package.json"), "w") as f:
            json.dump(manifest, f)

        for fname in (bins or ["metamod.1.ep1.so"]) + ["server.so", "server_i486.so"]:
            with open(os.path.join(bin_dir, fname), "wb") as f:
                f.write(legacy_core if fname == "metamod.1.ep1.so" else b"")

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

    def test_bridge_reference_drives_checkout_and_builds(self):
        # Point sm13-latest's bridge_metamod at another MM 1.10 pin: checkout and
        # both builders must take it from lines.json, never a hard-coded MM 1.10.
        builder = os.path.join(self.tmp_dir, "builder")
        os.makedirs(builder)
        for name in ("py.sh", "lines.py", "resolve-metamod-pins.py"):
            shutil.copy(os.path.join(ROOT, "builder", name), builder)
        with open(os.path.join(ROOT, "builder", "lines.json")) as fh:
            data = json.load(fh)
        bridge = dict(data["pins"]["MM_110"], commit="1" * 40, rev=977)
        data["pins"]["MM_110_ALT"] = bridge
        data["lines"]["sm13-latest"]["bridge_metamod"] = "MM_110_ALT"
        primary = data["pins"][data["lines"]["sm13-latest"]["metamod"]]
        with open(os.path.join(builder, "lines.json"), "w") as fh:
            json.dump(data, fh)

        # Execute the production orchestration blocks with only the expensive
        # fetch/build functions stubbed; the actual resolver reads the fixture.
        # The primary Metamod comes from resolve-version.sh (MMS_*), the bridge
        # from the resolver.
        for path, function, commit_arg in (
            ("builder/checkout-deps.sh", "fetch_and_patch_mms", 4),
            ("builder/run/linux.sh", "build_and_package_mm", 5),
            ("builder/run/windows.sh", "build_and_package_mm_win", 5),
        ):
            with self.subTest(path=path):
                stub = function + '() { printf "%s\\n" "${' + str(commit_arg) + '}"; }\n'
                env = os.environ.copy()
                env.update(BUILDER_DIR=builder, DEPS_DIR=self.tmp_dir,
                           SOURCEMOD_MAJOR="13", CSS34_LINE="sm13-latest", **mms_env(primary))
                res = subprocess.run(["bash", "-euo", "pipefail", "-c", stub + mm_block(path)],
                                     env=env, capture_output=True, text=True)
                self.assertEqual(res.returncode, 0, res.stderr)
                if path == "builder/checkout-deps.sh":
                    self.assertEqual(res.stdout.splitlines(), [primary["commit"], bridge["commit"]])
                else:
                    # Builders take MM 1.10 first: its legacy core goes into the
                    # MM 1.12 package (legacy-plugin bridge, T2.9).
                    self.assertEqual(res.stdout.splitlines(), [bridge["commit"], primary["commit"]])

    def test_frozen_dual_core_line_is_not_resolved(self):
        # T3.3: master builds one Metamod per line; sm11-oldstable is rebuilt only
        # from its freeze tag, so neither the resolver nor the verifier takes it.
        res = subprocess.run(["python3", RESOLVE_SCRIPT, "sm11-oldstable"], capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("frozen dual-core line", res.stderr)
        self.assertEqual(res.stdout, "")
        self._create_mock_pkg()
        res = self._verify("sm11-oldstable")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("frozen dual-core line", res.stderr)
        self.assertNotIn("Checking", res.stdout)

    def bridge_lines(self):
        with open(os.path.join(ROOT, "builder", "lines.json")) as fh:
            data = json.load(fh)
        return data, data["pins"][data["lines"]["sm13-latest"]["bridge_metamod"]]

    def test_bridge_line_builds_mm110_first_and_does_not_package_it(self):
        data, bridge = self.bridge_lines()
        primary = data["pins"][data["lines"]["sm13-latest"]["metamod"]]
        for path, function, role_arg in (("builder/run/linux.sh", "build_and_package_mm", 6),
                                         ("builder/run/windows.sh", "build_and_package_mm_win", 6)):
            with self.subTest(path=path):
                stub = function + '() { printf "%s %s\\n" "$5" "${' + str(role_arg) + '}"; }\n'
                env = os.environ.copy()
                env.update(BUILDER_DIR=os.path.join(ROOT, "builder"), DEPS_DIR=self.tmp_dir,
                           SOURCEMOD_MAJOR="13", CSS34_LINE="sm13-latest", **mms_env(primary))
                res = subprocess.run(["bash", "-euo", "pipefail", "-c", stub + mm_block(path)],
                                     env=env, capture_output=True, text=True)
                self.assertEqual(res.returncode, 0, res.stderr)
                self.assertEqual(res.stdout.splitlines(),
                                 [bridge["commit"] + " bridge", primary["commit"] + " primary"])
        with open(os.path.join(ROOT, "builder/run/linux.sh")) as fh:
            body = fh.read()
        self.assertIn('if [[ "$mm_role" == bridge ]]; then', body)

    def _sm13_package(self, legacy_core, legacy_bridge=True):
        return self._create_mock_pkg(commit="cb47755826fad1483291e5dc00222aa64303d12f", version="1.12.0-git1228",
                                     bins=["metamod.1.ep1.so", "metamod.2.ep1.so"],
                                     legacy_core=legacy_core, legacy_bridge=legacy_bridge)

    def _verify(self, line):
        env = os.environ.copy()
        env["CHECK_METAMOD_SCRIPT"] = "/bin/true"
        return subprocess.run([VERIFY_SCRIPT, line, self.tmp_dir, os.path.join(ROOT, "builder")],
                              capture_output=True, text=True, cwd=ROOT, env=env)

    def test_bridge_line_needs_the_legacy_core_in_its_mm112_package(self):
        _, bridge = self.bridge_lines()
        good = "1.10.7-dev+{} {}".format(bridge["rev"], bridge["commit"][:7]).encode()
        cases = (
            (dict(legacy_core=good, legacy_bridge=True), 0, "ships the MM 1.10.7"),
            (dict(legacy_core=b"1.10.7-dev+975 0000000", legacy_bridge=True), 1, "was not built from the bridge pin"),
            (dict(legacy_core=good, legacy_bridge=False), 1, "does not set legacy_bridge"),
        )
        for kwargs, rc, message in cases:
            with self.subTest(message=message):
                shutil.rmtree(self.tmp_dir)
                os.makedirs(self.tmp_dir)
                self._sm13_package(**kwargs)
                res = self._verify("sm13-latest")
                self.assertEqual(res.returncode != 0, rc == 1, res.stdout + res.stderr)
                self.assertIn(message, res.stdout + res.stderr)
        shutil.rmtree(self.tmp_dir)
        os.makedirs(self.tmp_dir)
        self._create_mock_pkg(commit="cb47755826fad1483291e5dc00222aa64303d12f", version="1.12.0-git1228",
                              bins=["metamod.2.ep1.so"])
        res = self._verify("sm13-latest")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("has no addons/metamod/bin/metamod.1.ep1.so", res.stderr)

    def test_verify_line_metamod_packages_sm13_latest_passes(self):
        # sm13-latest: one MM 1.12 git1228 package carrying the bridge's MM 1.10 core
        _, bridge = self.bridge_lines()
        self._sm13_package("1.10.7-dev+{} {}".format(bridge["rev"], bridge["commit"][:7]).encode())

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
