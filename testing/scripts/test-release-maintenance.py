#!/usr/bin/env python3
"""Release retention: published releases are never deleted, older ones are marked superseded.

Covers builder/scripts/supersede-releases.py (the plan, and the CLI against a fake `gh`
on PATH) and the shape of release-maintenance.yml / release.yml: no delete mode, inputs
reach the shell only through env, release.yml marks the old releases after a pointer move.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/release-maintenance.yml"
RELEASE = ROOT / ".github/workflows/release.yml"
SCRIPT = ROOT / "builder/scripts/supersede-releases.py"

spec = importlib.util.spec_from_file_location("supersede", SCRIPT)
sup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sup)


def rel(i, tag, created, body="notes", draft=False):
    return {"id": i, "tag_name": tag, "created_at": created, "draft": draft, "body": body}


RELEASES = [
    rel(1, "1.13.0.7404-mm1.12.0", "2026-09-01T00:00:00Z"),
    rel(2, "1.13.0.7478-mm1.12.0-r4", "2026-11-01T00:00:00Z"),
    rel(3, "1.13.0.7478-mm1.12.0-r5", "2026-11-03T18:08:34Z"),
    rel(4, "1.13.0.7478-mm1.12.0-r6", "2026-11-05T00:00:00Z"),   # newer candidate, not served
    rel(5, "1.12.0.7257-mm1.12.0-r4", "2026-11-03T18:30:03Z"),   # other line
    rel(6, "1.13.0.7404-mm2.0.0-r2", "2026-10-13T04:35:03Z"),    # archived MM 2.0 line
    rel(7, "line-sm13-latest", "2026-10-13T04:23:20Z"),
    rel(8, "1.13.0.7400-mm1.12.0", "2026-08-01T00:00:00Z", draft=True),
]


class FamilyTest(unittest.TestCase):
    def test_family(self):
        self.assertEqual(sup.family("1.13.0.7478-mm1.12.0-r5"), "1.13-mm1.12.0")
        self.assertEqual(sup.family("1.13.0.7478-mm1.12.0"), "1.13-mm1.12.0")
        self.assertEqual(sup.family("1.13.0.7565-mm2.0.0-khook-dhooks-r2"), "1.13-mm2.0.0-khook-dhooks")
        self.assertEqual(sup.family("1.11.0.6970-mm1.12.0-dual-r3"), "1.11-mm1.12.0-dual")
        for tag in ("line-sm13-latest", "lines-index", "sm11-freeze-inputs", "deps-geolite2-20261019", ""):
            self.assertIsNone(sup.family(tag), tag)


class PlanTest(unittest.TestCase):
    def plan(self, releases=RELEASES, served="1.13.0.7478-mm1.12.0-r5"):
        return {tag: body for _, tag, body in sup.plan(releases, "sm13-latest", served, "o/r")}

    def test_marks_only_older_releases_of_the_family(self):
        changes = self.plan()
        self.assertEqual(sorted(changes), ["1.13.0.7404-mm1.12.0", "1.13.0.7478-mm1.12.0-r4"])
        body = changes["1.13.0.7478-mm1.12.0-r4"]
        self.assertTrue(body.startswith(sup.MARKER))
        self.assertIn("**Superseded** by [`1.13.0.7478-mm1.12.0-r5`]"
                      "(https://github.com/o/r/releases/tag/1.13.0.7478-mm1.12.0-r5) (2026-11-03)", body)
        self.assertIn("`line-sm13-latest`", body)
        self.assertTrue(body.endswith("notes"), "the old notes stay under the banner")

    def test_idempotent(self):
        first = sup.plan(RELEASES, "sm13-latest", "1.13.0.7478-mm1.12.0-r5", "o/r")
        applied = [dict(r) for r in RELEASES]
        for rel_id, _, body in first:
            next(r for r in applied if r["id"] == rel_id)["body"] = body
        self.assertEqual(sup.plan(applied, "sm13-latest", "1.13.0.7478-mm1.12.0-r5", "o/r"), [])

    def test_banner_follows_the_newest_successor(self):
        old = sup.banner("1.13.0.7478-mm1.12.0-r4", "sm13-latest", "o/r", "2026-11-01")
        releases = [dict(r) for r in RELEASES]
        releases[0]["body"] = old + "notes"
        body = self.plan(releases)["1.13.0.7404-mm1.12.0"]
        self.assertEqual(body.count(sup.MARKER), 1)
        self.assertIn("1.13.0.7478-mm1.12.0-r5", body)
        self.assertNotIn("Superseded** by [`1.13.0.7478-mm1.12.0-r4`", body)

    def test_rollback_unmarks_the_served_release(self):
        releases = [dict(r) for r in RELEASES]
        releases[1]["body"] = sup.banner("1.13.0.7478-mm1.12.0-r5", "sm13-latest", "o/r", "x") + "r4 notes"
        changes = self.plan(releases, served="1.13.0.7478-mm1.12.0-r4")
        self.assertEqual(changes["1.13.0.7478-mm1.12.0-r4"], "r4 notes")
        self.assertIn("1.13.0.7404-mm1.12.0", changes)
        self.assertNotIn("1.13.0.7478-mm1.12.0-r5", changes, "a newer release is never marked by an older one")

    def test_known_bad_banner_is_kept(self):
        releases = [dict(r) for r in RELEASES]
        releases[0]["body"] = "<!-- css34-known-bad -->\n> [!WARNING]\n> bad\n\nnotes"
        body = self.plan(releases)["1.13.0.7404-mm1.12.0"]
        self.assertIn("<!-- css34-known-bad -->", body)
        self.assertLess(body.index(sup.MARKER), body.index("css34-known-bad"))

    def test_refuses_a_non_build_or_unknown_served_tag(self):
        for served in ("line-sm13-latest", "1.13.0.9999-mm1.12.0"):
            with self.assertRaises(SystemExit):
                sup.plan(RELEASES, "sm13-latest", served, "o/r")


FAKE_GH = r'''#!/usr/bin/env bash
set -euo pipefail
echo "gh $*" >> "$FAKE/calls.log"
if [[ "$1" == api && "$2" == --paginate ]]; then
  python3 -c 'import json,sys; [print(json.dumps(r)) for r in json.load(open(sys.argv[1]))]' "$FAKE/releases.json"
elif [[ "$1 $2 $3" == "api -X PATCH" ]]; then
  echo "$4" >> "$FAKE/patched.txt"
else
  echo "unexpected gh $*" >&2; exit 2
fi
'''


class CliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        bindir = self.tmp / "bin"
        bindir.mkdir()
        (bindir / "gh").write_text(FAKE_GH)
        (bindir / "gh").chmod(0o755)
        (self.tmp / "releases.json").write_text(json.dumps(RELEASES))
        self.env = dict(os.environ, PATH="{}:{}".format(bindir, os.environ["PATH"]), FAKE=str(self.tmp))

    def run_cli(self, *extra):
        return subprocess.run(["python3", str(SCRIPT), "--repo", "o/r", "--line", "sm13-latest",
                               "--served", "1.13.0.7478-mm1.12.0-r5", *extra],
                              env=self.env, capture_output=True, text=True)

    def patched(self):
        path = self.tmp / "patched.txt"
        return path.read_text().split() if path.exists() else []

    def test_dry_run_patches_nothing(self):
        res = self.run_cli("--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("dry run: 1.13.0.7478-mm1.12.0-r4 would be superseded by 1.13.0.7478-mm1.12.0-r5",
                      res.stdout)
        self.assertEqual(self.patched(), [])

    def test_patches_release_notes_only(self):
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(sorted(self.patched()), ["repos/o/r/releases/1", "repos/o/r/releases/2"])
        calls = (self.tmp / "calls.log").read_text()
        self.assertNotIn("delete", calls.lower())
        self.assertNotIn("prerelease", calls)


class WorkflowTest(unittest.TestCase):
    def test_no_delete_mode(self):
        text = WORKFLOW.read_text()
        self.assertIn("options: [republish, mark-known-bad, supersede]", text)
        self.assertNotIn("release delete", text)
        self.assertNotIn("--cleanup-tag", text)
        self.assertNotIn("DELETE", text)
        self.assertNotIn("releases/assets", text)

    def test_supersede_inputs_reach_shell_only_through_env(self):
        job = WORKFLOW.read_text().split("\n  supersede:\n", 1)[1]
        self.assertIn("if: github.event.inputs.mode == 'supersede'", job)
        run = job.split("        run: |\n", 1)[1]
        self.assertNotIn("${{", run)
        self.assertIn("builder/scripts/supersede-releases.py", run)

    def test_release_marks_superseded_after_pointer_move(self):
        text = RELEASE.read_text()
        job = text.split("\n  line-pointer:\n", 1)[1].split("\n  smoke-pointer:\n", 1)[0]
        self.assertIn("builder/scripts/supersede-releases.py", job)
        self.assertNotIn("release delete", text)


if __name__ == "__main__":
    unittest.main()
