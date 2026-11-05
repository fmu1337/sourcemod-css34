#!/usr/bin/env python3
"""builder/scripts/check-tag-map.sh passes on the tree and rejects tag-map drift."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

FILES = (
    "builder/scripts/check-tag-map.sh",
    "builder/scripts/release-notes.py",
    "builder/lines.py",
    "builder/lines.json",
    "builder/generated/tag-map.sh",
    "builder/docker/build.sh",
    "builder/windows-toolchain.env",
)
TREES = ("builder/patches/series",)



def load_lines():
    spec = importlib.util.spec_from_file_location("lines", str(ROOT / "builder/lines.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, mod.load_manifest(ROOT / "builder/lines.json")


# Take the tags from lines.json, so a pin bump needs no edit here.
_lines, _data = load_lines()
_active = [name for name, line in _data["lines"].items()
           if line["status"] == "active" and line.get("pointer")]
LINE, OTHER_LINE = _active[0], _active[1]
RELEASABLE_TAG = _lines.line_parts(_data, LINE)["tag"]
KNOWN_BAD_TAG = sorted(_data["known_bad"])[0]


class CheckTagMapTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in FILES:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        for name in TREES:
            shutil.copytree(ROOT / name, self.root / name)

    def run_script(self, *args):
        env = dict(os.environ, GITHUB_SHA="0" * 40)
        return subprocess.run(["bash", str(self.root / "builder/scripts/check-tag-map.sh"), *args],
                              cwd=self.temp.name, capture_output=True, text=True, env=env)

    def edit_tag_map(self, old, new):
        target = self.root / "builder/generated/tag-map.sh"
        text = target.read_text()
        self.assertIn(old, text)
        target.write_text(text.replace(old, new, 1))

    def test_current_tree_passes(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("release notes OK: {}-r2".format(RELEASABLE_TAG), result.stdout)
        self.assertNotIn("Release notes", result.stdout)

    def test_wrong_line_for_releasable_tag_fails(self):
        self.edit_tag_map("{}) printf '%s\\n' {}".format(RELEASABLE_TAG, LINE),
                          "{}) printf '%s\\n' {}".format(RELEASABLE_TAG, OTHER_LINE))
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("resolved to {}, expected {}".format(OTHER_LINE, LINE), result.stderr)

    def test_known_bad_tag_on_pointer_line_fails(self):
        self.edit_tag_map("    {}) printf '%s\\n' {}".format(RELEASABLE_TAG, LINE),
                          "    {}|{}) printf '%s\\n' {}".format(RELEASABLE_TAG, KNOWN_BAD_TAG, LINE))
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("known-bad tag {} maps to pointer line {}".format(KNOWN_BAD_TAG, LINE),
                      result.stderr)

    def test_known_bad_missing_from_tag_map_fails(self):
        self.edit_tag_map(KNOWN_BAD_TAG + "|", "")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("known_bad missing from tag map: {}".format(KNOWN_BAD_TAG), result.stderr)


if __name__ == "__main__":
    unittest.main()
