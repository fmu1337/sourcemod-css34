#!/usr/bin/env python3
"""release-maintenance.yml `delete` mode, run against a fake `gh` on PATH.

The step script is taken from the workflow itself, so this tests the shipped code:
pointer-served, frozen and Latest tags are refused, non-build tags are refused, one
refused tag deletes nothing, and without confirm=DELETE nothing is deleted.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/release-maintenance.yml"

FAKE_GH = r'''#!/usr/bin/env bash
# Fake gh: releases from $FAKE/releases.txt, pointer lines.json from $FAKE/pointer-<tag>.json.
set -euo pipefail
echo "gh $*" >> "$FAKE/calls.log"
case "$1 $2" in
  "api repos/o/r/releases/latest") echo "$(cat "$FAKE/latest.txt")" ;;
  "release download")
    tag="$3"; [[ -f "$FAKE/pointer-${tag}.json" ]] || exit 1; cat "$FAKE/pointer-${tag}.json" ;;
  "release view") grep -qxF -- "$3" "$FAKE/releases.txt" ;;
  "release delete") echo "$3" >> "$FAKE/deleted.txt" ;;
  *)
    if [[ "$1" == api && "$*" == *"releases?per_page=100"* ]]; then
      grep '^line-' "$FAKE/releases.txt" || true
    else
      echo "unexpected gh $*" >&2; exit 2
    fi ;;
esac
'''


def delete_job():
    return WORKFLOW.read_text().split("\n  delete:\n", 1)[1]


def delete_script():
    """The `run: |` block of the delete step (no PyYAML on the CI host)."""
    step = delete_job().split("      - name: Delete releases and their tags\n", 1)[1]
    lines = step.split("        run: |\n", 1)[1].split("\n")
    body = []
    for line in lines:
        if line.strip() and not line.startswith("          "):
            break
        body.append(line)
    return textwrap.dedent("\n".join(body))


class DeleteModeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.fake = self.tmp / "fake"
        self.fake.mkdir()
        bindir = self.tmp / "bin"
        bindir.mkdir()
        (bindir / "gh").write_text(FAKE_GH)
        (bindir / "gh").chmod(0o755)
        self.script = self.tmp / "delete.sh"
        self.script.write_text(delete_script())
        (self.fake / "releases.txt").write_text("\n".join([
            "line-sm13-latest", "line-sm12-latest", "lines-index", "sm11-freeze-inputs",
            "1.13.0.7478-mm1.12.0", "1.13.0.7478-mm1.12.0-r4", "1.13.0.7478-mm1.12.0-r5",
            "1.12.0.7257-mm1.12.0-r3", "1.11.0.6970-mm1.12.0-dual-r3",
        ]) + "\n")
        (self.fake / "latest.txt").write_text("1.13.0.7478-mm1.12.0-r5\n")
        (self.fake / "pointer-line-sm13-latest.json").write_text(
            json.dumps({"sm13-latest": {"tag": "1.13.0.7478-mm1.12.0-r5", "smoke": "pass"}}))
        (self.fake / "pointer-line-sm12-latest.json").write_text(
            json.dumps({"sm12-latest": {"tag": "1.12.0.7257-mm1.12.0-r3", "smoke": "pass"}}))
        self.env = dict(os.environ, PATH="{}:{}".format(bindir, os.environ["PATH"]), FAKE=str(self.fake),
                        GITHUB_REPOSITORY="o/r", RUNNER_TEMP=str(self.tmp),
                        GITHUB_STEP_SUMMARY=str(self.tmp / "summary.md"))

    def run_delete(self, tags, confirm=""):
        env = dict(self.env, TAGS=tags, CONFIRM=confirm)
        return subprocess.run(["bash", "-e", str(self.script)], cwd=ROOT, env=env,
                              capture_output=True, text=True)

    def deleted(self):
        path = self.fake / "deleted.txt"
        return path.read_text().split() if path.exists() else []

    def test_dry_run_deletes_nothing(self):
        res = self.run_delete("1.13.0.7478-mm1.12.0 1.13.0.7478-mm1.12.0-r4")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("dry run: would delete release and tag 1.13.0.7478-mm1.12.0-r4", res.stdout)
        self.assertEqual(self.deleted(), [])

    def test_confirmed_delete(self):
        res = self.run_delete("1.13.0.7478-mm1.12.0 1.13.0.7478-mm1.12.0-r4", confirm="DELETE")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(self.deleted(), ["1.13.0.7478-mm1.12.0", "1.13.0.7478-mm1.12.0-r4"])
        self.assertIn("--cleanup-tag", (self.fake / "calls.log").read_text())

    def test_refused_tags_delete_nothing(self):
        for tag, why in (("1.12.0.7257-mm1.12.0-r3", "served by a line pointer"),   # line-sm12-latest
                         ("1.13.0.7478-mm1.12.0-r5", "served by a line pointer"),   # pointer and Latest
                         ("1.11.0.6970-mm1.12.0-dual-r3", "served by a line pointer"),  # frozen sm11
                         ("line-sm13-latest", "not a build release tag"),
                         ("sm11-freeze-inputs", "not a build release tag"),
                         ("1.13.0.9999-mm1.12.0", "no release for")):
            res = self.run_delete("1.13.0.7478-mm1.12.0 " + tag, confirm="DELETE")
            self.assertNotEqual(res.returncode, 0, tag)
            self.assertIn(why, res.stdout, tag)
            self.assertIn("nothing deleted", res.stdout, tag)
            self.assertEqual(self.deleted(), [], tag)

    def test_pointer_without_lines_json_stops_everything(self):
        (self.fake / "pointer-line-sm12-latest.json").unlink()
        res = self.run_delete("1.13.0.7478-mm1.12.0", confirm="DELETE")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("cannot tell what it serves", res.stdout)
        self.assertEqual(self.deleted(), [])

    def test_needs_tags(self):
        res = self.run_delete(" ", confirm="DELETE")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("delete needs the tags", res.stdout)


class WorkflowTest(unittest.TestCase):
    def test_inputs_reach_shell_only_through_env(self):
        text = WORKFLOW.read_text()
        self.assertIn("options: [republish, mark-known-bad, delete]", text)
        self.assertIn("\n      confirm:\n", text)
        self.assertIn("if: github.event.inputs.mode == 'delete'", delete_job())
        self.assertNotIn("${{", delete_script())
        self.assertIn('CONFIRM" != DELETE', delete_script())


if __name__ == "__main__":
    unittest.main()
