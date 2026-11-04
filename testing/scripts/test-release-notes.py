#!/usr/bin/env python3
"""T4.3: generated release notes and the prerelease → smoke → promote flow."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
NOTES = ROOT / "builder/scripts/release-notes.py"
WORKFLOW = ROOT / ".github/workflows/release.yml"


def lines_module():
    spec = importlib.util.spec_from_file_location("css34_lines_t43", ROOT / "builder/lines.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, mod.load_manifest(ROOT / "builder/lines.json")


def notes(tag, root=ROOT, commit="a" * 40):
    return subprocess.run([sys.executable, str(NOTES), tag, "--commit", commit, "--root", str(root)],
                          capture_output=True, text=True)


class ReleaseNotes(unittest.TestCase):
    def setUp(self):
        self.mod, self.data = lines_module()
        self.parts = [self.mod.line_parts(self.data, name) for name, line in self.data["lines"].items()
                      if line["status"] == "active" and line.get("releasable", True)]
        self.assertTrue(self.parts)

    def test_every_releasable_tag_renders_its_pins(self):
        for part in self.parts:
            for tag in (part["tag"], part["tag"] + "-r2"):
                with self.subTest(tag=tag):
                    res = notes(tag)
                    self.assertEqual(res.returncode, 0, res.stderr)
                    text = res.stdout
                    self.assertIn("line `{}`".format(part["line"]), text)
                    self.assertIn("| SourceMod | {} |".format(part["sm_expect"]), text)
                    self.assertIn(part["sm_commit"], text)
                    self.assertIn(part["mm_commit"], text)
                    self.assertIn("git{}".format(part["mm_rev"]), text)
                    self.assertIn("glibc 2.17", text)
                    self.assertIn("manylinux2014_i686@sha256:", text)
                    self.assertIn("**prerelease**", text)
                    self.assertIn("MSVC x86 toolset", text)
                    self.assertIn("`{}`".format(part["line"]), text)
                    if "bridge_mm_commit" in part:
                        self.assertIn(part["bridge_mm_commit"], text)
                    for bad in self.data["known_bad"]:
                        self.assertIn("`{}`".format(bad), text)
                    first = text.splitlines()[0]
                    self.assertEqual(first.count("default"), 1 if part["default"] else 0, first)
                    # Consumers: fixed asset names, VERSIONS.txt, nothing is deleted.
                    self.assertIn("`sourcemod-css34-linux.tar.gz`", text)
                    self.assertIn("`VERSIONS.txt`", text)
                    self.assertIn("never deleted", text)
                    self.assertIn("docs/EXTENSIONS.md", text)
                    if int(part["sm_expect"].split(".")[1]) >= 13:
                        self.assertIn("**Extensions built for SourceMod 1.12 or older do not load.**", text)
                    else:
                        self.assertIn("extension API 8 and older", text)

    def test_tag_not_matching_the_pins_fails(self):
        for tag in ("1.13.0.9999-mm1.12.0", "1.12.0.7257-mm1.10.7", "line-sm13-latest", ""):
            with self.subTest(tag=tag):
                res = notes(tag)
                self.assertNotEqual(res.returncode, 0)
                if tag:
                    self.assertIn("matches no line pin", res.stderr)

    def test_known_bad_tag_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel in ("builder/lines.py", "builder/lines.json", "builder/docker/build.sh",
                        "builder/windows-toolchain.env"):
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / rel, root / rel)
            shutil.copytree(ROOT / "builder/patches/series", root / "builder/patches/series")
            tag = self.parts[0]["tag"]
            self.assertEqual(notes(tag, root).returncode, 0)
            data = json.loads((root / "builder/lines.json").read_text())
            data["known_bad"][tag] = "test: broken"
            (root / "builder/lines.json").write_text(json.dumps(data))
            res = notes(tag + "-r3", root)
            self.assertNotEqual(res.returncode, 0)
            # lines.py itself refuses a known-bad tag pinned on a line.
            self.assertIn("FAIL: builder/lines.json: known-bad tag " + tag, res.stderr)
            self.assertNotIn("Traceback", res.stderr)


def workflow_jobs():
    """release.yml job blocks by name (plain text; no YAML dependency)."""
    text = WORKFLOW.read_text().split("\njobs:\n", 1)[1]
    parts = re.split(r"^  ([a-z][a-z0-9-]*):\n", text, flags=re.M)
    return dict(zip(parts[1::2], parts[2::2]))


def needs(block):
    return set(re.search(r"^    needs: \[([^\]]*)\]", block, re.M).group(1).replace(" ", "").split(","))


def condition(block):
    match = re.search(r"^    if: (?:>-\n)?(.*?)\n    [a-z-]+:", block, re.M | re.S)
    return " ".join(match.group(1).split())


class PromoteFlow(unittest.TestCase):
    def setUp(self):
        self.jobs = workflow_jobs()

    def test_releases_are_created_as_prereleases_with_generated_notes(self):
        for job in ("linux", "windows"):
            with self.subTest(job=job):
                block = self.jobs[job]
                self.assertIn("builder/scripts/release-notes.py", block)
                self.assertIn("--prerelease --latest=false", block)
                self.assertNotIn('--notes "${notes}"', block)
                self.assertNotIn("--prerelease=false", block)

    def test_promote_waits_for_both_public_url_gates(self):
        block = self.jobs["promote"]
        self.assertEqual(needs(block), {"resolve-line", "linux", "smoke-release", "botplay-release"})
        cond = condition(block)
        for need in ("needs.smoke-release.result == 'success'", "needs.botplay-release.result == 'success'",
                     "needs.resolve-line.outputs.known_bad != '1'"):
            self.assertIn(need, cond)
        self.assertIn("--prerelease=false", block)
        self.assertIn('--latest="${LATEST}"', block)
        latest = block.split("LATEST: >-", 1)[1].split("run: |", 1)[0]
        self.assertIn("needs.resolve-line.outputs.default_line", latest)
        self.assertIn("needs.resolve-line.outputs.repoint != '1'", latest)

    def test_pointer_switches_only_after_promotion(self):
        block = self.jobs["line-pointer"]
        self.assertIn("promote", needs(block))
        smoke = re.search(r"SMOKE: (.*)", block).group(1)
        self.assertIn("needs.promote.result == 'success'", smoke)

    def test_checksums_are_last(self):
        block = self.jobs["checksums"]
        self.assertEqual(needs(block), {"resolve-line", "linux", "windows", "promote"})
        self.assertTrue(condition(block).startswith("always()"))

    def test_resolve_line_exports_known_bad_and_default_line(self):
        outputs = self.jobs["resolve-line"].split("    outputs:\n", 1)[1].split("    steps:", 1)[0]
        self.assertIn("known_bad:", outputs)
        self.assertIn("default_line:", outputs)


if __name__ == "__main__":
    unittest.main()
