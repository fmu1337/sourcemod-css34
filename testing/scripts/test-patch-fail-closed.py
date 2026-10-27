#!/usr/bin/env python3
"""Regression test for fail-closed patchers (Issue #97 / T3.2).

Verifies that builder/patches/apply-sourcemod-v112.sh and
builder/patches/apply-mmsource-v112.sh fail closed (non-zero exit code)
when run against empty or corrupted directories missing expected anchors.
"""

import subprocess
import os
import json
import re
import shutil
import sys
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



SM_PATCH = REPO_ROOT / "builder/patches/apply-sourcemod-v112.sh"
MM_PATCH = REPO_ROOT / "builder/patches/apply-mmsource-v112.sh"
FIXTURES = REPO_ROOT / "builder/patches/test-fixtures/fail-closed.json"


def heredoc(path, name):
    source = path.read_text()
    return source.split("<<'" + name + "'\n", 1)[1].split("\n" + name + "\n", 1)[0]


def sm_section(start, end):
    source = heredoc(SM_PATCH, "PY")
    return ("from pathlib import Path\nimport os\n"
            "sm = Path(os.environ['SOURCEMOD_DIR'])\n"
            + source[source.index(start):source.index(end)])


class TestPatchAnchors(unittest.TestCase):
    """Run the production patch sections on positive and corrupted fixtures.

    Sections avoid unrelated checkout/build prerequisites. Full patch ordering
    and real dependency trees are also exercised by the package-build CI jobs.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def run_patch(self, code, error=None):
        env = dict(os.environ, SOURCEMOD_DIR=str(self.root), MMS_DIR=str(self.root))
        result = subprocess.run([sys.executable, "-c", code], env=env,
                                capture_output=True, text=True)
        if error is None:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn(error, result.stderr)
            self.assertNotIn("SyntaxError", result.stderr)
        return result

    def assert_idempotent(self, code, paths):
        self.run_patch(code)
        first = [path.read_text() for path in paths]
        self.run_patch(code)
        self.assertEqual([path.read_text() for path in paths], first)
        return first

    def fixture(self, name):
        return json.loads(FIXTURES.read_text())[name]["content"]

    def test_all_python_heredocs_compile(self):
        for path in (SM_PATCH, MM_PATCH):
            source = path.read_text()
            blocks = re.findall(r"<<'(PY\w*)'\n(.*?)\n\1(?:\n|$)", source, re.S)
            self.assertGreater(len(blocks), 5)
            for name, code in blocks:
                with self.subTest(path=path.name, block=name):
                    compile(code, str(path) + ":" + name, "exec")
            result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def cstrike(self):
        code = sm_section("# cstrike: build", "# cstrike GetPlayerVarAddressOrError")
        files = [
            self.write("extensions/cstrike/AMBuilder", "for sdk_name in ['css', 'csgo']:\n  pass\n"),
            self.write("extensions/cstrike/forwards.cpp", "#if SOURCE_ENGINE == SE_CSS\n#endif\n"),
            self.write("extensions/cstrike/natives.cpp", "#if SOURCE_ENGINE == SE_CSS\n#endif\n"),
        ]
        return code, files

    def test_cstrike_reapplication_does_not_duplicate_guards(self):
        code, files = self.cstrike()
        result = self.assert_idempotent(code, files)
        self.assertIn("['episode1', 'css', 'csgo']", result[0])
        for text in result[1:]:
            self.assertEqual(text.count(" || SOURCE_ENGINE == SE_EPISODEONE"), 1)

    def test_cstrike_missing_files_and_drift_fail(self):
        code, files = self.cstrike()
        for path in files:
            with self.subTest(path=path):
                original = path.read_text()
                path.unlink()
                self.run_patch(code, str(path))
                path.write_text(original)
                path.write_text("// unsupported upstream layout\n")
                self.run_patch(code, "FAIL:")
                path.write_text(original)
        files[0].write_text("for sdk_name in ['css', 'csgo']:\n  pass\n" * 2)
        self.run_patch(code, "cstrike SDK loop missing or ambiguous")

    def test_curl_requires_complete_anchor_or_patch(self):
        code = sm_section("# bundled curl", "# shell.cpp sign-compare")
        path = self.write("extensions/curl/curl-src/lib/AMBuilder",
                          "if True:\n    binary.compiler.defines += ['_GNU_SOURCE']\n")
        patched, = self.assert_idempotent(code, [path])
        self.assertIn("-Wno-error=stringop-truncation", patched)
        compile(patched, str(path), "exec")
        for bad in ("pass\n", "# stringop-truncation\n",
                    "binary.compiler.defines += ['_GNU_SOURCE']\n# stringop-truncation\n"):
            path.write_text(bad)
            self.run_patch(code, "bundled libcurl")
        path.unlink()
        self.run_patch(code, str(path))

    def test_shell_accepts_both_pinned_upstream_forms(self):
        source = heredoc(SM_PATCH, "PY")
        code = ("from pathlib import Path\nimport os\nsm = Path(os.environ['SOURCEMOD_DIR'])\n"
                + source[source.index("# shell.cpp sign-compare"):])
        path = self.write("sourcepawn/vm/shell/shell.cpp", "")
        for original in ("if (index > params[0])",
                         "if (static_cast<cell_t>(index) > params[0])"):
            path.write_text(original + "\n")
            self.assert_idempotent(code, [path])
        path.write_text("if (unknown > params[0])\n")
        self.run_patch(code, "shell.cpp sign-compare anchor")
        path.unlink()
        self.run_patch(code, str(path))

    def test_sourcepawn_pinned_layouts_and_reapplication(self):
        code = sm_section("# SourcePawn builds", "# sourcemod.logic.so")
        for minor in (12, 13):
            with self.subTest(minor=minor):
                path = self.write("sourcepawn/AMBuildScript", self.fixture("sp" + str(minor)))
                patched, = self.assert_idempotent(code, [path])
                compile(patched, str(path), "exec")
                self.assertIn("'-lgcc', '-lgcc_s', '-Wl,--end-group'", patched)
                self.assertIn("'-Wno-sign-compare'", patched)

    def test_sourcepawn_missing_file_and_each_required_anchor(self):
        code = sm_section("# SourcePawn builds", "# sourcemod.logic.so")
        self.run_patch(code, "sourcepawn/AMBuildScript missing")
        for minor in (12, 13):
            original = self.fixture("sp" + str(minor))
            cases = [
                ("'-Werror',", "'-Wall',", "-Werror anchor"),
                ("cxx.postlink += ['-lpthread', '-lrt']", "cxx.postlink += []", "Configure pthread/rt anchor"),
                ("'-Wl,--end-group'", "'-Wl,--drifted-group'", "AddStaticLibraries anchor"),
                ("self.SetupBinForArch(binary, builder)", "self.NewSetup(binary, builder)", "CoreLib pattern"),
            ]
            for old, new, error in cases:
                with self.subTest(minor=minor, anchor=old):
                    self.assertIn(old, original)
                    self.write("sourcepawn/AMBuildScript", original.replace(old, new))
                    self.run_patch(code, error)

    def test_sourcepawn_one_valid_core_does_not_hide_the_other_drifting(self):
        code = sm_section("# SourcePawn builds", "# sourcemod.logic.so")
        original = self.fixture("sp12")
        self.write("sourcepawn/AMBuildScript", original.replace(
            "def BuildStaticCoreLib(self, builder):", "def BuildStaticCoreLib(self, context):"))
        self.run_patch(code, "BuildStaticCoreLib pattern not found")
        path = self.write("sourcepawn/AMBuildScript", original)
        self.run_patch(code)
        path.write_text(path.read_text().replace(
            "for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s'):",
            "for flag in ('-lpthread',):", 1))
        self.run_patch(code, "incomplete BuildStaticCoreLib pthread/rt patch")

    def test_logic_pinned_layouts_and_static_sp_tail_drift(self):
        code = sm_section("# sourcemod.logic.so", "# cstrike: build")
        self.run_patch(code, "core/logic/AMBuilder missing")
        for minor in (12, 13):
            with self.subTest(minor=minor):
                self.write("product.version", "1.%d.0\n" % minor)
                original = self.fixture("logic" + str(minor))
                path = self.write("core/logic/AMBuilder", original)
                patched, = self.assert_idempotent(code, [path])
                compile(patched, str(path), "exec")
                self.assertIn("--exclude-libs,ALL", patched)
                if minor == 13:
                    self.assertIn("skip duplicate logic static SP on linux", patched)
                    path.write_text(original.replace("SP.zlib[target],", "SP.other[target],"))
                    self.run_patch(code, "logic duplicate static SP anchor")

    def test_safe_iface_missing_file_or_load_anchor(self):
        code = heredoc(SM_PATCH, "PYIFACE")
        self.run_patch(code, "core/sourcemm_api.cpp missing")
        path = self.write("core/sourcemm_api.cpp", "// drift\n")
        self.run_patch(code, "SourceMod_Core::Load anchor")
        path.write_text("bool SourceMod_Core::Load(int x) {}\n")
        patched, = self.assert_idempotent(code, [path])
        self.assertIn("CSS34_SAFE_GET_V_IFACE", patched)

    def test_required_native_and_gameconfig_files(self):
        for start, end, rel in (
            ("# cstrike GetPlayerVarAddressOrError", "# css34: CacheGameBinaryInfo", "extensions/cstrike/natives.cpp"),
            ("# css34: CacheGameBinaryInfo", "# bundled curl", "core/logic/GameConfigs.cpp"),
        ):
            with self.subTest(path=rel):
                code = sm_section(start, end)
                self.run_patch(code, rel + " missing")
                path = self.write(rel, "// drift\n")
                self.run_patch(code, "FAIL:")
                path.unlink()

    def test_mm_versioning_does_not_accept_partial_markers(self):
        code = heredoc(MM_PATCH, "PYVER")
        rel = "support/buildbot/Versioning"
        self.run_patch(code, rel + " missing")
        for bad in ("# css34: detached HEAD\n", "head_contents = fp.read().strip()\n", "# drift\n"):
            self.write(rel, bad)
            self.run_patch(code, "MM Versioning detached-HEAD pattern not found")
        old = ("with open(os.path.join(builder.sourcePath, '.git', 'HEAD')) as fp:\n"
               " git_state = fp.read().strip().split(':')[1].strip()\n\n"
               "git_head_path = os.path.join(builder.sourcePath, '.git', git_state)\n"
               "if not os.path.exists(git_head_path):\n"
               "  git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')\n")
        path = self.write(rel, old)
        patched, = self.assert_idempotent(code, [path])
        self.check_git_heads(patched)

    def check_git_heads(self, code):
        self.write(".git/refs/heads/master", "b" * 40 + "\n")
        for head, expected in (("a" * 40, ".git/HEAD"),
                               ("ref: refs/heads/master", ".git/refs/heads/master"),
                               ("ref: refs/heads/packed", ".git/HEAD")):
            with self.subTest(head=head):
                self.write(".git/HEAD", head + "\n")
                context = {"os": os, "re": re, "builder": SimpleNamespace(sourcePath=str(self.root))}
                exec(compile(code, "Versioning", "exec"), context)
                self.assertEqual(context["git_head_path"], str(self.root / expected))

    def test_sm_versioning_requires_full_patch_and_resolves_gitdir(self):
        code = heredoc(SM_PATCH, "PYSMGIT")
        rel = "tools/buildbot/Versioning"
        self.run_patch(code, rel)
        for bad in ("# _resolve_git_head_path\n", "# drift\n"):
            self.write(rel, bad)
            self.run_patch(code, "SM Versioning submodule gitdir anchor")
        original = """with open(os.path.join(builder.sourcePath, '.git', 'HEAD')) as fp:
  head_contents = fp.read().strip()
  if re.search('^[a-fA-F0-9]{40}$', head_contents):
    git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
  else:
    git_state = head_contents.split(':')[1].strip()
    git_head_path = os.path.join(builder.sourcePath, '.git', git_state)
    if not os.path.exists(git_head_path):
      git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
"""
        # The pinned MM 1.12 implementation has this same full detached-HEAD block.
        mm_path = self.write("support/buildbot/Versioning", original)
        self.assert_idempotent(heredoc(MM_PATCH, "PYVER"), [mm_path])
        path = self.write(rel, original)
        patched, = self.assert_idempotent(code, [path])
        self.check_git_heads(patched)
        shutil.rmtree(self.root / ".git")
        self.write(".git", "gitdir: git-meta\n")
        self.write("git-meta/HEAD", "a" * 40 + "\n")
        context = {"os": os, "re": re, "builder": SimpleNamespace(sourcePath=str(self.root))}
        exec(compile(patched, "Versioning", "exec"), context)
        self.assertEqual(context["git_head_path"], str(self.root / "git-meta/HEAD"))


if __name__ == "__main__":
    unittest.main()
