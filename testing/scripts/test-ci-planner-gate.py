#!/usr/bin/env python3
"""Regression tests for CI Planner and Gate logic.

Verifies:
- All required jobs success -> gate OK
- Failure/cancelled of any required job -> gate FAIL
- Unexpectedly skipped required job -> gate FAIL
- Failed/cancelled plan job -> gate FAIL
- Expected skips (doc-only PR) -> gate OK
- Doc-only PR -> planner outputs code_changed=False, run_code_jobs=False, required_jobs=['plan']
- Suite selection: pr (PR / push / dispatch) vs weekly (schedule / dispatch), and the
  matrices each suite feeds to smoke / botplay; Wine smoke only in weekly
- Single-line dispatch filters every matrix to that line
- Empty Windows matrix, lines.json additions
- ci.yml wiring: every job the planner can require exists and is a gate need, the
  host regression runner discovers every testing/scripts/test-* script
"""

import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))
WORKFLOW = ROOT / ".github/workflows/ci.yml"


def load_module_from_path(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ci_planner_mod = load_module_from_path("ci_planner", ROOT / "builder/scripts/ci_planner.py")
plan_ci = ci_planner_mod.plan_ci

ci_gate_mod = load_module_from_path("ci_gate", ROOT / "builder/scripts/ci_gate.py")
evaluate_gate = ci_gate_mod.evaluate_gate

lines_mod = load_module_from_path("lines", ROOT / "builder/lines.py")
MATRIX = lines_mod.ci_matrix(lines_mod.load_manifest(ROOT / "builder/lines.json"))

PR_JOBS = ["plan", "check-pins", "hygiene", "build-linux", "prepare-server", "smoke",
           "botplay", "host-checks", "build-windows"]


def simulate_paths_filter(changed_files):
    """Simulates dorny/paths-filter with predicate-quantifier: every:
    code: ['!docs/**', '!**/*.md']
    """
    for path in changed_files:
        p = Path(path)
        is_doc = p.parts[0] == "docs"
        is_md = p.suffix == ".md"
        # If any file is NOT a doc/md file, code_changed becomes True
        if not (is_doc or is_md):
            return True
    return False


def workflow_jobs():
    """ci.yml job ids -> job text (plain text; no YAML dependency)."""
    text = WORKFLOW.read_text()
    body = text.split("\njobs:\n", 1)[1]
    parts = re.split(r"(?m)^  ([a-z0-9-]+):\n", body)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


def all_success(plan):
    return {job: {"result": "success"} for job in plan["required_jobs"]}


class TestCIPlannerGate(unittest.TestCase):

    def test_frozen_sm11_is_out_of_ci(self):
        for event in ("pull_request", "schedule"):
            plan = plan_ci(event_name=event, code_changed="true")
            for key, rows in plan["matrices"].items():
                self.assertNotIn("sm11-oldstable", {row["line"] for row in rows}, key)
        with self.assertRaisesRegex(ValueError, "inactive CSS34_LINE: 'sm11-oldstable'"):
            plan_ci(event_name="workflow_dispatch", code_changed="true", inputs={"css34_line": "sm11-oldstable"})

    def test_pr_suite_requires_every_gate_job(self):
        for event in ("pull_request", "push", "workflow_dispatch"):
            with self.subTest(event=event):
                plan = plan_ci(event_name=event, code_changed="true")
                self.assertEqual(plan["suite"], "pr")
                self.assertEqual(plan["required_jobs"], PR_JOBS)
                self.assertFalse(plan["run_wine"])
                self.assertEqual(plan["matrices"]["smoke"], MATRIX["debian"])
                self.assertEqual(plan["matrices"]["botplay"], MATRIX["botplay"])
                self.assertEqual(plan["matrices"]["build"], MATRIX["build"])
                ok, errors = evaluate_gate(all_success(plan), plan)
                self.assertTrue(ok, errors)

    def test_weekly_suite_uses_old_os_matrices_and_wine(self):
        for event, inputs in (("schedule", {}), ("workflow_dispatch", {"suite": "weekly"})):
            with self.subTest(event=event):
                plan = plan_ci(event_name=event, code_changed="false", inputs=inputs)
                self.assertTrue(plan["run_code_jobs"])
                self.assertEqual(plan["suite"], "weekly")
                self.assertEqual(plan["matrices"]["smoke"], MATRIX["weekly"])
                self.assertEqual(plan["matrices"]["botplay"], MATRIX["weekly_botplay"])
                self.assertTrue(plan["run_wine"])
                self.assertEqual(plan["required_jobs"], PR_JOBS + ["wine-smoke"])

    def test_unknown_suite_is_refused(self):
        with self.assertRaisesRegex(ValueError, "Unknown suite"):
            plan_ci(event_name="workflow_dispatch", code_changed="true", inputs={"suite": "nightly"})

    def test_removed_dispatch_inputs_are_ignored(self):
        # Old dispatch inputs (reference botplay, bisect, extra distros) no longer exist.
        plan = plan_ci(event_name="workflow_dispatch", code_changed="true",
                       inputs={"run_reference_botplay": "true", "run_botplay_bisect": "true",
                               "botplay_extra_distros": "true", "record_secs": "90"})
        self.assertEqual(plan["required_jobs"], PR_JOBS)

    def test_null_inputs_on_push(self):
        # toJSON(github.event.inputs) is "null" outside workflow_dispatch.
        plan = plan_ci(event_name="push", code_changed="true", inputs=None)
        self.assertEqual(plan["suite"], "pr")

    def test_host_checks_are_required_for_code_and_selected_line(self):
        for event, inputs in (("pull_request", {}),
                              ("workflow_dispatch", {"css34_line": "sm12-latest"})):
            plan = plan_ci(event, True, inputs)
            self.assertIn("host-checks", plan["required_jobs"])
            for result in ("failure", "skipped", "cancelled"):
                needs = all_success(plan)
                needs["host-checks"]["result"] = result
                self.assertFalse(evaluate_gate(needs, plan)[0])
        host = workflow_jobs()["host-checks"]
        self.assertIn("bash testing/scripts/check-core-plapi.sh", host)
        self.assertIn("testing/scripts/smoke-test.sh", host)
        self.assertIn("fromJSON(needs.plan.outputs.build)", host)

    def test_gate_rejects_missing_or_malformed_required_jobs(self):
        needs = {"plan": {"result": "success"}, "hygiene": {"result": "skipped"}}
        for bad in (None, {}, [], "", "[]", {"required_jobs": []},
                    ["hygiene"], ["plan", None], ["plan", ""], {"required_jobs": "plan"}):
            with self.subTest(plan=bad):
                ok, errors = evaluate_gate(needs, bad)
                self.assertFalse(ok)
                self.assertTrue(errors)

    def test_gate_requires_regressions(self):
        plan = plan_ci(event_name="pull_request", code_changed="true")
        for job in ("hygiene", "check-pins"):
            needs = all_success(plan)
            needs[job]["result"] = "skipped"
            self.assertFalse(evaluate_gate(needs, plan)[0])
        jobs = workflow_jobs()
        self.assertIn("bash testing/scripts/run-host-tests.sh", jobs["hygiene"])
        self.assertIn("python3 testing/scripts/test-lines.py", jobs["check-pins"])
        self.assertIn("bash builder/scripts/check-tag-map.sh", jobs["check-pins"])
        # The runner discovers tests by name: every regression script must match
        # its pattern, so none is silently left out of CI.
        runner = (ROOT / "testing/scripts/run-host-tests.sh").read_text()
        self.assertIn("-name 'test-*.py' -o -name 'test-*.sh'", runner)
        scripts = sorted((ROOT / "testing/scripts").glob("test-*"))
        self.assertIn(ROOT / "testing/scripts/test-package-paths.sh", scripts)
        self.assertIn(ROOT / "testing/scripts/test-upstream-probe-check.sh", scripts)
        self.assertTrue(all(p.suffix in (".py", ".sh") for p in scripts), scripts)

    def test_every_plannable_job_exists_and_is_a_gate_need(self):
        jobs = workflow_jobs()
        gate_needs = re.findall(r"(?m)^      - ([a-z0-9-]+)$", jobs["gate"].split("    runs-on:", 1)[0])
        plannable = set(PR_JOBS + ["wine-smoke"])
        self.assertEqual(set(gate_needs), plannable)
        self.assertEqual(set(jobs) - {"gate"}, plannable)
        # Each job is conditioned on a plan output.
        for name in plannable - {"plan"}:
            self.assertIn("needs.plan.outputs.", jobs[name], name)
        self.assertIn("needs.plan.outputs.run_wine == 'true'", jobs["wine-smoke"])
        self.assertIn("needs.plan.outputs.run_windows == 'true'", jobs["build-windows"])
        # Every matrix the jobs read is a plan output the planner emits.
        used = set(re.findall(r"fromJSON\(needs\.plan\.outputs\.([a-z_]+)\)", WORKFLOW.read_text()))
        self.assertEqual(used, set(ci_planner_mod.OUTPUT_MATRICES))

    def test_no_dead_skip_steps_or_chmod(self):
        text = WORKFLOW.read_text()
        self.assertNotIn("Maybe skip", text)
        self.assertNotIn("steps.select.outputs.skip", text)
        self.assertNotIn("chmod +x", text)
        self.assertNotIn("cursor/**", text)

    def test_doc_only_path_filter_simulation(self):
        """Simulates path filter with predicate-quantifier: every for doc-only, code-only, and mixed PRs."""
        self.assertFalse(simulate_paths_filter(["docs/README.md", "README.md"]))
        self.assertFalse(simulate_paths_filter(["docs/guide.md"]))
        self.assertTrue(simulate_paths_filter(["builder/lines.py"]))
        self.assertTrue(simulate_paths_filter(["README.md", "builder/lines.py"]))
        self.assertTrue(simulate_paths_filter([".github/workflows/ci.yml"]))
        text = WORKFLOW.read_text()
        self.assertIn("- '!docs/**'", text)
        self.assertIn("- '!**/*.md'", text)

    def test_doc_only_pr_planner_and_gate(self):
        """Doc-only PR must set run_code_jobs=False, required_jobs=['plan'] and pass gate when code jobs are skipped."""
        plan = plan_ci(event_name="pull_request", code_changed="false")
        self.assertFalse(plan["code_changed"])
        self.assertFalse(plan["run_code_jobs"])
        self.assertFalse(plan["run_windows"])
        self.assertFalse(plan["run_wine"])
        self.assertEqual(plan["required_jobs"], ["plan"])

        needs = {"plan": {"result": "success"}}
        for job in PR_JOBS[1:] + ["wine-smoke"]:
            needs[job] = {"result": "skipped"}
        ok, errors = evaluate_gate(needs, plan)
        self.assertTrue(ok, f"Gate failed for doc-only PR: {errors}")

    def test_gate_fails_on_required_job_failure(self):
        """Gate must fail if any required job fails or is cancelled."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        needs = all_success(plan)
        needs["build-linux"]["result"] = "failure"

        ok, errors = evaluate_gate(needs, plan)
        self.assertFalse(ok)
        self.assertTrue(any("build-linux" in err for err in errors))

        needs["build-linux"]["result"] = "cancelled"
        ok, errors = evaluate_gate(needs, plan)
        self.assertFalse(ok)

    def test_gate_fails_on_unexpected_skip(self):
        """Gate must fail if a required job is unexpectedly skipped."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        for job in ("smoke", "botplay"):
            needs = all_success(plan)
            needs[job]["result"] = "skipped"
            ok, errors = evaluate_gate(needs, plan)
            self.assertFalse(ok)
            self.assertTrue(any(job in err for err in errors))

    def test_gate_fails_on_unrequired_failure(self):
        """A job outside required_jobs that fails (e.g. wine-smoke on a PR) still fails the gate."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        needs = all_success(plan)
        needs["wine-smoke"] = {"result": "failure"}
        self.assertFalse(evaluate_gate(needs, plan)[0])
        needs["wine-smoke"] = {"result": "skipped"}
        self.assertTrue(evaluate_gate(needs, plan)[0])

    def test_gate_fails_on_failed_plan(self):
        """Gate must fail if plan job itself failed or was cancelled."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        needs = {job: {"result": "skipped"} for job in plan["required_jobs"]}
        needs["plan"]["result"] = "failure"

        ok, errors = evaluate_gate(needs, plan)
        self.assertFalse(ok)
        self.assertTrue(any("plan" in err for err in errors))

    def test_windows_eligibility_and_matrices(self):
        """Windows matrix in planner must only contain active lines with windows: true."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        data = json.loads((ROOT / "builder/lines.json").read_text(encoding="utf-8"))
        want = {name for name, line in data["lines"].items()
                if line.get("windows") and line["status"] == "active"}
        # One Windows build (native smoke) per line, on the line's MM 1.12 zip.
        rows = plan["matrices"]["windows"]
        self.assertEqual(sorted(entry["line"] for entry in rows), sorted(want))
        for row in rows:
            self.assertEqual((row["expect_core"], row["dhooks_expect"]), ("2.ep1", "1"))
            self.assertTrue(row["mm_package"].startswith("mmsource-1.12.0-"), row)
            self.assertTrue(row["mm_package"].endswith("-css34-windows.zip"), row)
            # T2.9: lines with bridge_metamod run the PLAPI 11 probe on Windows.
            bridged = "bridge_metamod" in data["lines"][row["line"]]
            self.assertEqual(row["legacy_bridge"], "1" if bridged else "0", row)
        build_windows = workflow_jobs()["build-windows"]
        self.assertIn("LEGACY_PROBE", build_windows)
        self.assertIn("matrix.legacy_bridge", build_windows)

    def test_empty_windows_matrix_support(self):
        """When no lines are windows-eligible, windows matrix is [] and build-windows/wine-smoke are skipped."""
        with open(ROOT / "builder/lines.json", "r", encoding="utf-8") as f:
            data = json.load(f)

        for line in data["lines"].values():
            line["windows"] = False

        with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as tmp:
            json.dump(data, tmp)
            tmp_path = tmp.name

        try:
            for event in ("pull_request", "schedule"):
                plan = plan_ci(event_name=event, code_changed="true", lines_path=tmp_path)
                self.assertEqual(plan["matrices"]["windows"], [])
                self.assertFalse(plan["run_windows"])
                self.assertFalse(plan["run_wine"])
                self.assertNotIn("build-windows", plan["required_jobs"])
                self.assertNotIn("wine-smoke", plan["required_jobs"])

                needs = all_success(plan)
                needs["build-windows"] = {"result": "skipped"}
                needs["wine-smoke"] = {"result": "skipped"}
                ok, errors = evaluate_gate(needs, plan)
                self.assertTrue(ok, f"Gate failed for empty windows matrix: {errors}")
        finally:
            Path(tmp_path).unlink(missing_ok=True)

    def test_css34_line_filters_every_matrix(self):
        """Single-line dispatch keeps only that line's rows, in both suites."""
        for line in ("sm12-latest", "sm13-latest"):
            for suite in ("pr", "weekly"):
                with self.subTest(line=line, suite=suite):
                    plan = plan_ci(event_name="workflow_dispatch", code_changed="true",
                                   inputs={"css34_line": line, "suite": suite})
                    for key, rows in plan["matrices"].items():
                        self.assertTrue(rows, key)
                        self.assertEqual({row["line"] for row in rows}, {line}, key)
                    ok, errors = evaluate_gate(all_success(plan), plan)
                    self.assertTrue(ok, errors)

    def test_readme_only_pr_still_checks_generated_pin_tables(self):
        plan = plan_ci(event_name="pull_request", code_changed="false", pins_changed="true")
        self.assertFalse(plan["run_code_jobs"])
        self.assertTrue(plan["run_check_pins"])
        self.assertEqual(plan["required_jobs"], ["plan", "check-pins"])
        needs = {"plan": {"result": "success"}, "check-pins": {"result": "failure"},
                 "hygiene": {"result": "skipped"}, "build-linux": {"result": "skipped"}}
        ok, _ = evaluate_gate(needs, plan)
        self.assertFalse(ok)
        needs["check-pins"] = {"result": "success"}
        ok, errors = evaluate_gate(needs, plan)
        self.assertTrue(ok, errors)

    def test_css34_line_invalid_raises_error(self):
        """Invalid or inactive css34_line input must raise ValueError."""
        for line in ("invalid-line", "sm13-dev", "sm13-mm20"):
            with self.subTest(line=line):
                with self.assertRaises(ValueError):
                    plan_ci(event_name="workflow_dispatch", code_changed="true",
                            inputs={"css34_line": line})

    def test_lines_json_addition_reflected_in_matrices(self):
        """Adding a line in lines.json must immediately reflect in planner matrices."""
        with open(ROOT / "builder/lines.json", "r", encoding="utf-8") as f:
            data = json.load(f)

        data["lines"]["sm14-test"] = {
            "sourcemod": "SM_DEV",
            "metamod": "MM_112",
            "status": "active",
            "pointer": False,
            "releasable": True,
            "role": "Test line",
            "smoke": [{"image": "ubuntu:24.04"}],
            "windows": True,
        }

        with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as tmp:
            json.dump(data, tmp)
            tmp_path = tmp.name

        try:
            plan = plan_ci(event_name="pull_request", code_changed="true", lines_path=tmp_path)
            for key in ("build", "smoke", "botplay", "windows"):
                self.assertIn("sm14-test", {entry["line"] for entry in plan["matrices"][key]}, key)
            weekly = plan_ci(event_name="schedule", code_changed="true", lines_path=tmp_path)
            self.assertIn("sm14-test", {entry["line"] for entry in weekly["matrices"]["smoke"]})
        finally:
            Path(tmp_path).unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
