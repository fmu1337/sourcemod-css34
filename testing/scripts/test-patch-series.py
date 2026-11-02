#!/usr/bin/env python3
"""T3.4: builder/patches/apply-series.sh applies a line's patch series fail-closed.

Small real git repositories stand in for SourceMod and one submodule; the
series' patches, base commit and expected trees are generated here.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
APPLY = ROOT / "builder/patches/apply-series.sh"
GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True,
                          text=True, env=GIT_ENV).stdout.strip()


def make_repo(path, files):
    path.mkdir(parents=True)
    git(path, "init", "-q")
    for name, data in files.items():
        (path / name).write_bytes(data)
    git(path, "add", "-A")
    git(path, "commit", "-q", "-m", "base")
    return git(path, "rev-parse", "HEAD")


class PatchSeriesTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.sm = self.tmp / "sm"
        self.commit = make_repo(self.sm, {"AMBuildScript": b"a = 1\n", "crlf.cpp": b"int x;\r\nint y;\r\n"})
        make_repo(self.sm / "sub", {"build.py": b"flags = []\n"})
        self.series = self.tmp / "series"
        # Patches made the way patch-series.sh makes them: edit, diff, reset.
        self.write_patch("sourcemod", "0001-flags.patch", self.sm,
                         {"AMBuildScript": b"a = 2\n", "crlf.cpp": b"int x;\r\nint z;\r\n", "new.c": b"void f(void){}\n"})
        self.write_patch("sub", "0001-sub.patch", self.sm / "sub", {"build.py": b"flags = ['-x']\n"})
        self.trees = {"sourcemod": self.tree_after("sourcemod", self.sm),
                      "sub": self.tree_after("sub", self.sm / "sub")}
        self.write_manifest(self.commit, self.trees)

    def write_patch(self, repo, name, target, files):
        for path, data in files.items():
            (target / path).write_bytes(data)
        git(target, "add", "--", *files)  # never the nested submodule repository
        # Bytes: text mode would turn the CRLF lines of the diff into LF.
        diff = subprocess.run(["git", "-C", str(target), "diff", "--cached", "--full-index", "--no-color"],
                              check=True, capture_output=True, env=GIT_ENV).stdout
        git(target, "reset", "-q", "--hard")
        git(target, "clean", "-fdxq")
        out = self.series / repo / name
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(b"css34: " + name.encode() + b"\n\n" + diff)

    def tree_after(self, repo, target):
        for patch in sorted((self.series / repo).glob("*.patch")):
            git(target, "apply", "--index", str(patch))
        tree = git(target, "write-tree")
        git(target, "reset", "-q", "--hard")
        git(target, "clean", "-fdxq")
        return tree

    def write_manifest(self, commit, trees):
        (self.series / "series.json").write_text(json.dumps({"line": "x", "commit": commit, "trees": trees}))

    def apply(self):
        return subprocess.run(["bash", str(APPLY), str(self.series), str(self.sm)],
                              capture_output=True, text=True, env=GIT_ENV)

    def test_applies_submodule_first_and_checks_trees(self):
        res = self.apply()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertLess(res.stdout.index("sub: applied"), res.stdout.index("sourcemod: applied"))
        self.assertIn("sourcemod: tree " + self.trees["sourcemod"] + " matches", res.stdout)
        self.assertEqual((self.sm / "crlf.cpp").read_bytes(), b"int x;\r\nint z;\r\n")
        self.assertTrue((self.sm / "new.c").is_file())
        self.assertEqual((self.sm / "sub/build.py").read_text(), "flags = ['-x']\n")

    def test_wrong_base_commit_fails_before_patching(self):
        self.write_manifest("0" * 40, self.trees)
        res = self.apply()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("is made for sourcemod " + "0" * 40, res.stderr)
        self.assertEqual((self.sm / "AMBuildScript").read_text(), "a = 1\n")

    def test_tree_mismatch_fails(self):
        self.write_manifest(self.commit, dict(self.trees, sourcemod="1" * 40))
        res = self.apply()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("sourcemod tree", res.stderr)

    def test_drifted_upstream_fails(self):
        (self.sm / "AMBuildScript").write_text("a = 7\n")
        git(self.sm, "commit", "-qam", "drift")
        self.write_manifest(git(self.sm, "rev-parse", "HEAD"), self.trees)
        res = self.apply()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("0001-flags.patch does not apply", res.stderr)

    def test_missing_submodule_and_series_parts_fail(self):
        shutil.rmtree(self.sm / "sub")
        res = self.apply()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("is not a git checkout", res.stderr)
        shutil.rmtree(self.series / "sourcemod")
        self.assertNotEqual(self.apply().returncode, 0)

    def test_lines_check_rejects_a_series_for_another_pin(self):
        root = self.tmp / "repo"
        for name in ("builder/lines.py", "builder/lines.json"):
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / name, root / name)
        series = root / "builder/patches/series/sm13-latest"
        shutil.copytree(ROOT / "builder/patches/series/sm13-latest", series)
        sys.path.insert(0, str(root / "builder"))
        try:
            import importlib
            lines = importlib.import_module("lines")
            importlib.reload(lines)
            lines.load_manifest(root / "builder/lines.json")
            data = json.loads((series / "series.json").read_text())
            (series / "series.json").write_text(json.dumps(dict(data, commit="0" * 40)))
            with self.assertRaisesRegex(ValueError, "patch-series.sh refresh sm13-latest"):
                lines.load_manifest(root / "builder/lines.json")
        finally:
            sys.path.remove(str(root / "builder"))

    def test_lines_check_rejects_an_mm_series_for_another_pin(self):
        root = self.tmp / "repo"
        for name in ("builder/lines.py", "builder/lines.json"):
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / name, root / name)
        series = root / "builder/patches/series/MM_112"
        shutil.copytree(ROOT / "builder/patches/series/MM_112", series)
        sys.path.insert(0, str(root / "builder"))
        try:
            import importlib
            lines = importlib.import_module("lines")
            importlib.reload(lines)
            lines.load_manifest(root / "builder/lines.json")
            data = json.loads((series / "series.json").read_text())
            (series / "series.json").write_text(json.dumps(dict(data, commit="0" * 40)))
            with self.assertRaisesRegex(ValueError, "patch-series.sh refresh MM_112"):
                lines.load_manifest(root / "builder/lines.json")
        finally:
            sys.path.remove(str(root / "builder"))

    def test_metamod_root_series(self):
        mm = self.tmp / "mm"
        commit = make_repo(mm, {"AMBuildScript": b"m = 1\n"})
        series = self.tmp / "mmseries"
        self.series = series
        self.write_patch("metamod", "0001-m.patch", mm, {"AMBuildScript": b"m = 2\n"})
        tree = self.tree_after("metamod", mm)
        (series / "series.json").write_text(json.dumps(
            {"pin": "MM_X", "root": "metamod", "commit": commit, "trees": {"metamod": tree}}))
        res = subprocess.run(["bash", str(APPLY), str(series), str(mm)], capture_output=True, text=True, env=GIT_ENV)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("metamod: tree " + tree + " matches", res.stdout)
        self.assertEqual((mm / "AMBuildScript").read_text(), "m = 2\n")
        shutil.rmtree(series / "metamod")
        git(mm, "reset", "-q", "--hard")
        res = subprocess.run(["bash", str(APPLY), str(series), str(mm)], capture_output=True, text=True, env=GIT_ENV)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("has no metamod/ patches", res.stderr)


class RouterTest(unittest.TestCase):
    """apply-sourcemod.sh: a line's series or nothing (T3.4: no scripted fallback)."""

    def route(self, version, line):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "product.version").write_text(version + "\n")
            env = dict(GIT_ENV)
            env.pop("CSS34_LINE", None)
            if line is not None:
                env["CSS34_LINE"] = line
            return subprocess.run(["bash", str(ROOT / "builder/patches/apply-sourcemod.sh"), tmp],
                                  capture_output=True, text=True, env=env)

    def test_frozen_sourcemod_refused(self):
        res = self.route("1.11.0", "sm11-oldstable")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("master builds SourceMod 1.12+ only", res.stderr)

    def test_line_without_series_refused(self):
        res = self.route("1.13.0", "sm14-latest")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("sm14-latest has no patch series", res.stderr)
        res = self.route("1.13.0", None)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("CSS34_LINE is required", res.stderr)

    def test_series_on_the_wrong_checkout_fails_closed(self):
        res = self.route("1.13.0", "sm13-latest")
        self.assertNotEqual(res.returncode, 0)
        self.assertNotIn("applied", res.stdout)

    def test_no_scripted_patcher_left(self):
        for name in ("apply-sourcemod-v112.sh", "apply-mmsource-v112.sh"):
            self.assertFalse((ROOT / "builder/patches" / name).exists(), name)


if __name__ == "__main__":
    unittest.main()
