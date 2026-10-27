#!/usr/bin/env python3
"""Regression test for fail-closed patchers (Issue #97 / T3.2).

Verifies that builder/patches/apply-sourcemod-v112.sh and
builder/patches/apply-mmsource-v112.sh fail closed (non-zero exit code)
when run against empty or corrupted directories missing expected anchors.
"""

import subprocess
import os
from types import SimpleNamespace
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

SDKHELPERS_STUB = """import os

        # cflags
        for cflag in SdkHelpers.getLists(sdk, 'cflags', cxx):
            cxx.cflags += [cflag]

        # cxxflags
        for cxxflag in SdkHelpers.getLists(sdk, 'cxxflags', cxx):
            cxx.cxxflags += [cxxflag]
"""


class TestPatchFailClosed(unittest.TestCase):

    def test_mm111_generated_versioning_executes_and_is_idempotent(self):
        old = """with open(os.path.join(builder.sourcePath, '.git', 'HEAD')) as fp:
  git_state = fp.read().strip().split(':')[1].strip()

git_head_path = os.path.join(builder.sourcePath, '.git', git_state)
if not os.path.exists(git_head_path):
  git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
"""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "core").mkdir()
            (root / "core/ISmmAPI.h").touch()
            (root / ".git/refs/heads").mkdir(parents=True)
            (root / ".git/HEAD").write_text("a" * 40 + "\n")
            path = root / "support/buildbot/Versioning"
            path.parent.mkdir(parents=True)
            path.write_text(old)
            cmd = ["bash", str(REPO_ROOT / "builder/patches/apply-mmsource-v111.sh"), tmpdir]
            first = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            patched = path.read_text()
            for head, expected in (("a" * 40, ".git/HEAD"),
                                   ("ref: refs/heads/master", ".git/refs/heads/master")):
                with self.subTest(head=head):
                    (root / ".git/HEAD").write_text(head + "\n")
                    (root / ".git/refs/heads/master").write_text("b" * 40 + "\n")
                    context = {"os": os, "builder": SimpleNamespace(sourcePath=tmpdir)}
                    exec(compile(patched, str(path), "exec"), context)
                    self.assertEqual(context["git_head_path"], str(root / expected))
            second = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(path.read_text(), patched)


    def test_apply_sourcemod_v112_missing_manifests(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            (tmppath / "product.version").write_text("1.12.0")
            (tmppath / "extensions" / "mysql").mkdir(parents=True)
            (tmppath / "extensions" / "mysql" / "AMBuilder").write_text("    SM.extensions += [builder.Add(binary)]\n")

            cmd = [
                "bash",
                str(REPO_ROOT / "builder" / "patches" / "apply-sourcemod-v112.sh"),
                tmpdir,
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("hl2sdk-manifests missing", res.stderr)

    def test_apply_sourcemod_v112_corrupted_onmapend(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            (tmppath / "product.version").write_text("1.12.0")
            (tmppath / "extensions" / "mysql").mkdir(parents=True)
            (tmppath / "extensions" / "mysql" / "AMBuilder").write_text("    SM.extensions += [builder.Add(binary)]\n")
            (tmppath / "hl2sdk-manifests" / "manifests").mkdir(parents=True)
            (tmppath / "hl2sdk-manifests" / "manifests" / "episode1.json").write_text("{}")
            (tmppath / "hl2sdk-manifests" / "SdkHelpers.ambuild").write_text(SDKHELPERS_STUB)
            (tmppath / "extensions" / "sdktools").mkdir(parents=True)
            (tmppath / "extensions" / "sdktools" / "output.cpp").write_text("// dummy file without anchor")

            cmd = [
                "bash",
                str(REPO_ROOT / "builder" / "patches" / "apply-sourcemod-v112.sh"),
                tmpdir,
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("FAIL: unrecognized OnMapEnd hook-list layout in output.cpp", res.stderr)

    def test_apply_mmsource_v112_missing_core(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            cmd = [
                "bash",
                str(REPO_ROOT / "builder" / "patches" / "apply-mmsource-v112.sh"),
                tmpdir,
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("Missing Metamod core", res.stderr)

    def test_apply_mmsource_v112_mismatched_versioning(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            (tmppath / "core").mkdir(parents=True)
            (tmppath / "core" / "ISmmAPI.h").write_text("")
            (tmppath / "hl2sdk-manifests").mkdir(parents=True)
            (tmppath / "hl2sdk-manifests" / "SdkHelpers.ambuild").write_text(SDKHELPERS_STUB)
            (tmppath / "support" / "buildbot").mkdir(parents=True)
            (tmppath / "support" / "buildbot" / "Versioning").write_text("// dummy code without detached HEAD pattern")

            cmd = [
                "bash",
                str(REPO_ROOT / "builder" / "patches" / "apply-mmsource-v112.sh"),
                tmpdir,
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("FAIL: MM Versioning detached-HEAD pattern not found", res.stderr)


if __name__ == "__main__":
    unittest.main()
