#!/usr/bin/env python3
"""T4.4: builder/scripts/upstream-bump.py and .github/workflows/upstream-bump.yml.

Local git repositories stand in for alliedmodders/sourcemod and metamod-source
(CSS34_UPSTREAM_* overrides); nothing here touches the network.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUMP = ROOT / "builder/scripts/upstream-bump.py"
WORKFLOW = ROOT / ".github/workflows/upstream-bump.yml"
TAG_WORKFLOW = ROOT / ".github/workflows/release-tag.yml"
GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True,
                          text=True, env=GIT_ENV).stdout.strip()


def commit(repo, files, message):
    for name, text in files.items():
        path = Path(repo) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", message)
    return git(repo, "rev-parse", "HEAD")


class UpstreamBumpTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.root = self.tmp / "repo"
        for rel in ("builder/lines.py", "builder/lines.json"):
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / rel, self.root / rel)
        shutil.copytree(ROOT / "builder/patches/series", self.root / "builder/patches/series")
        # Fake upstreams: sourcemod (1.12-dev, master) and metamod-source (1.12-dev).
        self.sm = self.tmp / "sourcemod"
        self.mm = self.tmp / "metamod-source"
        for repo in (self.sm, self.mm):
            repo.mkdir()
            git(repo, "init", "-q", "-b", "master")
        base = commit(self.sm, {"README": "sm\n"}, "base")
        git(self.sm, "branch", "1.12-dev")
        self.sm13 = commit(self.sm, {"core/x.cpp": "1\n"}, "13")
        git(self.sm, "checkout", "-q", "1.12-dev")
        self.sm12 = commit(self.sm, {"core/y.cpp": "1\n"}, "12")
        git(self.sm, "checkout", "-q", "master")
        commit(self.mm, {"README": "mm\n"}, "base")
        git(self.mm, "branch", "1.12-dev")
        self.mm12 = git(self.mm, "rev-parse", "1.12-dev")
        self.assertTrue(base)
        self.set_pins({"SM_LATEST": self.sm12, "SM_LATEST_13": self.sm13, "MM_112": self.mm12})
        self.env = dict(GIT_ENV, CSS34_UPSTREAM_SOURCEMOD="file://" + str(self.sm),
                        CSS34_UPSTREAM_METAMOD_SOURCE="file://" + str(self.mm))

    def set_pins(self, pins):
        path = self.root / "builder/lines.json"
        data = json.loads(path.read_text())
        for name, sha in pins.items():
            data["pins"][name]["commit"] = sha
        path.write_text(json.dumps(data, indent=2) + "\n")

    def bump(self, *args, check=True):
        res = subprocess.run([sys.executable, str(BUMP), "--root", str(self.root), *args],
                             capture_output=True, text=True, env=self.env)
        if check:
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return res

    def plan(self):
        return json.loads(self.bump("plan", "--cache", str(self.tmp / "cache")).stdout)

    def test_plan_lists_only_lagging_targets(self):
        self.assertEqual(self.plan(), [])
        new = commit(self.sm, {"gamedata/sdktools.games/common.games.txt": "x\n"}, "gd")
        plan = self.plan()
        self.assertEqual([p["target"] for p in plan], ["sm13-latest"])
        self.assertEqual(plan[0]["new_commit"], new)
        self.assertEqual(plan[0]["new_rev"], 3)
        self.assertEqual(plan[0]["old_commit"], self.sm13)
        self.assertTrue(plan[0]["fast_forward"])
        self.assertEqual(plan[0]["series"], ["sm13-latest"])
        # Re-running against the same upstream gives the same plan (no duplicate work).
        self.assertEqual(self.plan(), plan)

    def test_plan_flags_a_rewritten_upstream_branch(self):
        git(self.mm, "checkout", "-q", "--orphan", "other")
        commit(self.mm, {"other": "1\n"}, "unrelated")
        git(self.mm, "branch", "-f", "1.12-dev", "other")
        plan = self.plan()
        self.assertEqual([p["target"] for p in plan], ["MM_112"])
        self.assertFalse(plan[0]["fast_forward"])

    def test_body_lists_log_risky_paths_and_tags(self):
        patched = sorted(re.findall(r"^diff --git a/(\S+) b/", (
            ROOT / "builder/patches/series/sm13-latest/sourcemod/0001-build-episode1-toolchain.patch"
        ).read_text(), re.M))[0]
        new = commit(self.sm, {"gamedata/core.games/common.games.txt": "x\n", patched: "changed\n",
                               "docs/unrelated.md": "x\n"}, "upstream change")
        self.set_pins({"SM_LATEST_13": new})
        text = self.bump("body", "sm13-latest", self.sm13, new, "--cache", str(self.tmp / "cache")).stdout
        self.assertIn("**sm13-latest**: `SM_LATEST_13` {} → {}".format(self.sm13[:8], new[:8]), text)
        self.assertIn("upstream change", text)
        self.assertIn("- `gamedata/core.games/common.games.txt`", text)
        self.assertIn("- **P** `{}`".format(patched), text)
        self.assertNotIn("docs/unrelated.md", text.split("<details>")[0])
        self.assertIn("`sm13-latest` → `1.13.0.", text)

    def test_apply_refuses_bad_input_before_touching_anything(self):
        before = (self.root / "builder/lines.json").read_text()
        res = self.bump("apply", "sm13-latest", "notasha", "7", check=False)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("bad commit/rev", res.stderr)
        self.assertEqual((self.root / "builder/lines.json").read_text(), before)
        (self.root / "builder/lines.json").write_text(json.dumps(json.loads(before)) + "\n")
        res = self.bump("apply", "sm13-latest", "a" * 40, "7", check=False)
        self.assertIn("canonical format", res.stderr)

    def release_tags(self, old, new, existing):
        files = {}
        for name, data in (("old", old), ("new", new)):
            files[name] = self.tmp / (name + ".json")
            files[name].write_text(json.dumps(data))
        (self.tmp / "tags.txt").write_text("\n".join(existing) + "\n")
        return self.bump("release-tags", str(files["old"]), str(files["new"]),
                         "--existing", str(self.tmp / "tags.txt")).stdout.split()

    def test_release_tags_follow_moved_pins_only(self):
        data = json.loads((ROOT / "builder/lines.json").read_text())
        self.assertEqual(self.release_tags(data, data, []), [])
        sm13 = json.loads(json.dumps(data))
        sm13["pins"]["SM_LATEST_13"].update(commit="e" * 40, rev=7999)
        self.assertEqual(self.release_tags(data, sm13, []), ["1.13.0.7999-mm1.12.0"])
        # An MM-only bump keeps both base tags: the next free -rN of each.
        mm = json.loads(json.dumps(data))
        mm["pins"]["MM_112"].update(commit="f" * 40, rev=1300)
        sm12_tag = "1.12.0.{}-mm1.12.0".format(data["pins"]["SM_LATEST"]["rev"])
        sm13_tag = "1.13.0.{}-mm1.12.0".format(data["pins"]["SM_LATEST_13"]["rev"])
        tags = self.release_tags(data, mm, [sm12_tag, sm13_tag, sm13_tag + "-r2", sm13_tag + "-r10"])
        self.assertEqual(sorted(tags), sorted([sm12_tag + "-r2", sm13_tag + "-r11"]))
        # Frozen and archived lines never get a tag, whatever moved.
        khook = json.loads(json.dumps(data))
        khook["pins"]["SM_KHOOK"]["commit"] = "1" * 40
        old_sm = json.loads(json.dumps(data))
        old_sm["pins"]["SM_OLDSTABLE"]["commit"] = "2" * 40
        self.assertEqual(self.release_tags(data, khook, []), [])
        self.assertEqual(self.release_tags(data, old_sm, []), [])

    def next_tag(self, data, line, existing, check=True):
        (self.tmp / "next.json").write_text(json.dumps(data))
        (self.tmp / "tags.txt").write_text("\n".join(existing) + "\n")
        return self.bump("next-tag", line, "--lines", str(self.tmp / "next.json"),
                         "--existing", str(self.tmp / "tags.txt"), check=check)

    def test_next_tag_of_a_releasable_line(self):
        data = json.loads((ROOT / "builder/lines.json").read_text())
        sm13_tag = "1.13.0.{}-mm1.12.0".format(data["pins"]["SM_LATEST_13"]["rev"])
        self.assertEqual(self.next_tag(data, "sm13-latest", []).stdout.split(), [sm13_tag])
        self.assertEqual(self.next_tag(data, "sm13-latest", [sm13_tag]).stdout.split(), [sm13_tag + "-r2"])
        taken = [sm13_tag, sm13_tag + "-r4", sm13_tag + "-r10", sm13_tag + "-rc1", "x" + sm13_tag + "-r99"]
        self.assertEqual(self.next_tag(data, "sm13-latest", taken).stdout.split(), [sm13_tag + "-r11"])

    def test_next_tag_refuses_lines_that_cannot_release(self):
        data = json.loads((ROOT / "builder/lines.json").read_text())
        for line, reason in (("sm11-oldstable", "not a releasable pointer line"),
                             ("sm13-mm20-khook", "not a releasable pointer line"),
                             ("no-such-line", "unknown line")):
            res = self.next_tag(data, line, [], check=False)
            self.assertNotEqual(res.returncode, 0, line)
            self.assertIn(reason, res.stderr)
        bad = json.loads(json.dumps(data))
        sm13_tag = "1.13.0.{}-mm1.12.0".format(data["pins"]["SM_LATEST_13"]["rev"])
        bad["known_bad"][sm13_tag] = "test"
        res = self.next_tag(bad, "sm13-latest", [], check=False)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("known-bad", res.stderr)


class TagWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.text = TAG_WORKFLOW.read_text()

    def test_dispatch_only_and_inputs_through_env(self):
        self.assertRegex(self.text, r"\non:\n  workflow_dispatch:\n    inputs:\n")
        self.assertNotIn("push:", self.text)
        for name in ("line", "sha", "expected_tag"):
            self.assertIn("      {}:\n".format(name), self.text)
        # Inputs reach shell code only through env, never interpolated into run: blocks.
        for block in self.text.split("run: |")[1:]:
            self.assertNotIn("${{", block.split("\n      - name:", 1)[0])

    def test_tag_is_computed_on_master_and_pushed_with_the_app(self):
        self.assertIn("git merge-base --is-ancestor", self.text)
        self.assertIn('git show "${commit}:builder/lines.json"', self.text)
        self.assertIn("upstream-bump.py next-tag", self.text)
        self.assertIn("git tag --points-at", self.text)
        self.assertIn("persist-credentials: false", self.text)
        self.assertIn("actions/create-github-app-token@v3", self.text)
        self.assertIn("vars.BUMP_APP_ID", self.text)
        self.assertIn("x-access-token:${TOKEN}", self.text)
        self.assertNotIn("secrets.GITHUB_TOKEN", self.text)
        self.assertIn("cancel-in-progress: false", self.text)


class WorkflowTest(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()

    def test_triggers(self):
        self.assertIn("schedule:", self.text)
        self.assertIn("workflow_dispatch:", self.text)
        self.assertRegex(self.text, r"push:\n    branches: \[master\]\n    paths:\n      - 'builder/lines.json'")

    def test_app_token_for_everything_that_must_trigger_workflows(self):
        bump = self.text.split("\n  bump:\n", 1)[1].split("\n  release:\n", 1)[0]
        release = self.text.split("\n  release:\n", 1)[1]
        for block in (bump, release):
            self.assertIn("actions/create-github-app-token@v3", block)
            self.assertIn("vars.BUMP_APP_ID", block)
        self.assertIn("token: ${{ steps.app.outputs.token }}", bump)
        self.assertIn("GH_TOKEN: ${{ steps.app.outputs.token }}", bump)
        self.assertNotIn("secrets.GITHUB_TOKEN", self.text)
        self.assertIn("x-access-token:${TOKEN}", release)

    def test_no_duplicates(self):
        self.assertIn("already at ${NEW} on top of master; nothing to do", self.text)
        self.assertIn('gh pr list --head "$BRANCH" --state open', self.text)
        self.assertIn("gh pr edit", self.text)
        self.assertIn("python3 builder/lines.py check", self.text)
        self.assertIn("upstream-bump.py apply", self.text)
        self.assertIn("check-css34-gamedata.py builder/assets/gamedata --source", self.text)


if __name__ == "__main__":
    unittest.main()
