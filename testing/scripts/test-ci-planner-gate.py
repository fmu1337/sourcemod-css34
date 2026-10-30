#!/usr/bin/env python3
"""Regression tests for CI Planner and Gate logic.

Verifies:
- All required jobs success -> gate OK
- Failure/cancelled of any required job -> gate FAIL
- Unexpectedly skipped required job -> gate FAIL
- Failed/cancelled plan job -> gate FAIL
- Expected skips (doc-only PR) -> gate OK
- Doc-only PR -> planner outputs code_changed=False, run_code_jobs=False, required_jobs=['plan']
- Empty applicable matrix / line matrix updates on temporary lines.json
- Windows eligibility and weekly/event selection
- Single-line dispatch (sm11, sm12, sm13) matrix and required_jobs handling (host smoke, windows, release_botplay, botplay_extra)
- Incompatible single-line + run_botplay_bisect rejection
"""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))


def load_module_from_path(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ci_planner_mod = load_module_from_path("ci_planner", ROOT / "builder/scripts/ci_planner.py")
plan_ci = ci_planner_mod.plan_ci

ci_gate_mod = load_module_from_path("ci_gate", ROOT / "builder/scripts/ci_gate.py")
evaluate_gate = ci_gate_mod.evaluate_gate


def simulate_paths_filter(changed_files):
    """Simulates dorny/paths-filter with predicate-quantifier: every:
    code: ['!docs/**', '!**/*.md', '!.github/workflows/cleanup-artifacts.yml']
    """
    for path in changed_files:
        p = Path(path)
        parts = p.parts
        # Check if EVERY negative rule passes for this file
        is_doc = parts[0] == "docs"
        is_md = p.suffix == ".md"
        is_cleanup = str(p) == ".github/workflows/cleanup-artifacts.yml"

        # If any file is NOT a doc/md/cleanup file, code_changed becomes True
        if not (is_doc or is_md or is_cleanup):
            return True
    return False


class TestCIPlannerGate(unittest.TestCase):

    def test_plapi_runtime_is_required_for_code_and_selected_line(self):
        for event, inputs in (("pull_request", {}),
                              ("workflow_dispatch", {"css34_line": "sm11-oldstable"})):
            plan = plan_ci(event, True, inputs)
            self.assertIn("plapi-runtime", plan["required_jobs"])
            for result in ("failure", "skipped", "cancelled"):
                needs = {name: {"result": "success"} for name in plan["required_jobs"]}
                needs["plapi-runtime"]["result"] = result
                self.assertFalse(evaluate_gate(needs, plan)[0])
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("bash testing/scripts/check-core-plapi.sh", workflow)
        self.assertIn("      - plapi-runtime", workflow)


    def test_gate_rejects_missing_or_malformed_required_jobs(self):
        needs = {"plan": {"result": "success"}, "hygiene": {"result": "skipped"}}
        for bad in (None, {}, [], "", "[]", {"required_jobs": []},
                    ["hygiene"], ["plan", None], ["plan", ""], {"required_jobs": "plan"}):
            with self.subTest(plan=bad):
                ok, errors = evaluate_gate(needs, bad)
                self.assertFalse(ok)
                self.assertTrue(errors)

    def test_gate_requires_migrated_regressions(self):
        plan = plan_ci(event_name="pull_request", code_changed="true")
        for job in ("hygiene", "check-pins"):
            needs = {name: {"result": "success"} for name in plan["required_jobs"]}
            needs[job]["result"] = "skipped"
            self.assertFalse(evaluate_gate(needs, plan)[0])
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        hygiene = workflow.split("\n  hygiene:", 1)[1].split("\n  build-linux:", 1)[0]
        for script in ("test-release-build-entrypoints.py", "test-patch-fail-closed.py",
                       "test-sm11-dhooks-builder.py"):
            self.assertIn("python3 testing/scripts/" + script, hygiene)
        # Every regression script must run somewhere in ci.yml: a step lost while
        # moving jobs between workflows must fail here, not pass silently.
        for script in sorted((ROOT / "testing/scripts").glob("test-*.py")):
            self.assertIn("testing/scripts/" + script.name, workflow, script.name)
        pins = workflow.split("\n  check-pins:", 1)[1].split("\n  hygiene:", 1)[0]
        self.assertIn("python3 testing/scripts/test-lines.py", pins)


    def test_doc_only_path_filter_simulation(self):
        """Simulates path filter with predicate-quantifier: every for doc-only, code-only, and mixed PRs."""
        self.assertFalse(simulate_paths_filter(["docs/README.md", "README.md"]))
        self.assertFalse(simulate_paths_filter(["docs/guide.md"]))
        self.assertFalse(simulate_paths_filter(["docs/ROADMAP.md", ".github/workflows/cleanup-artifacts.yml"]))
        self.assertTrue(simulate_paths_filter(["builder/lines.py"]))
        self.assertTrue(simulate_paths_filter(["README.md", "builder/lines.py"]))

    def test_doc_only_pr_planner_and_gate(self):
        """Doc-only PR must set run_code_jobs=False, required_jobs=['plan'] and pass gate when code jobs are skipped."""
        plan = plan_ci(event_name="pull_request", code_changed="false")
        self.assertFalse(plan["code_changed"])
        self.assertFalse(plan["run_code_jobs"])
        self.assertFalse(plan["run_pr_smoke"])
        self.assertFalse(plan["run_weekly_smoke"])
        self.assertEqual(plan["required_jobs"], ["plan"])

        needs = {
            "plan": {"result": "success"},
            "check-pins": {"result": "skipped"},
            "hygiene": {"result": "skipped"},
            "build-linux": {"result": "skipped"},
            "build-windows": {"result": "skipped"},
            "wine-smoke": {"result": "skipped"},
            "test-built-debian": {"result": "skipped"},
            "test-built-smoke": {"result": "skipped"},
        }
        ok, errors = evaluate_gate(needs, plan)
        self.assertTrue(ok, f"Gate failed for doc-only PR: {errors}")

    def test_code_pr_planner_and_gate_success(self):
        """Code PR must require build, smoke, and botplay jobs, and gate passes when all succeed."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        self.assertTrue(plan["code_changed"])
        self.assertTrue(plan["run_code_jobs"])
        self.assertTrue(plan["run_pr_smoke"])
        self.assertIn("build-linux", plan["required_jobs"])
        self.assertIn("build-windows", plan["required_jobs"])
        self.assertIn("wine-smoke", plan["required_jobs"])
        self.assertIn("test-built-debian", plan["required_jobs"])
        self.assertIn("test-built-botplay-matrix", plan["required_jobs"])

        needs = {job: {"result": "success"} for job in plan["required_jobs"]}
        ok, errors = evaluate_gate(needs, plan)
        self.assertTrue(ok, f"Gate failed when all required jobs succeeded: {errors}")

    def test_gate_fails_on_required_job_failure(self):
        """Gate must fail if any required job fails or is cancelled."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        needs = {job: {"result": "success"} for job in plan["required_jobs"]}
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
        needs = {job: {"result": "success"} for job in plan["required_jobs"]}
        needs["test-built-debian"]["result"] = "skipped"

        ok, errors = evaluate_gate(needs, plan)
        self.assertFalse(ok)
        self.assertTrue(any("test-built-debian" in err for err in errors))

    def test_gate_fails_on_failed_plan(self):
        """Gate must fail if plan job itself failed or was cancelled."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        needs = {job: {"result": "skipped"} for job in plan["required_jobs"]}
        needs["plan"]["result"] = "failure"

        ok, errors = evaluate_gate(needs, plan)
        self.assertFalse(ok)
        self.assertTrue(any("plan" in err for err in errors))

    def test_weekly_schedule_event_selection(self):
        """Schedule event must trigger weekly smoke suite."""
        plan = plan_ci(event_name="schedule", code_changed="false")
        self.assertTrue(plan["run_code_jobs"])
        self.assertTrue(plan["run_weekly_smoke"])
        self.assertFalse(plan["run_pr_smoke"])
        self.assertIn("test-built-weekly", plan["required_jobs"])
        self.assertIn("test-built-weekly-botplay", plan["required_jobs"])

    def test_workflow_dispatch_suite_selection(self):
        """Workflow dispatch must honor suite parameter and optional flags."""
        plan_pr = plan_ci(
            event_name="workflow_dispatch",
            code_changed="false",
            inputs={"suite": "pr", "run_full_botplay_matrix": "true"},
        )
        self.assertTrue(plan_pr["run_pr_smoke"])
        self.assertIn("test-built-botplay-matrix", plan_pr["required_jobs"])

        plan_weekly = plan_ci(
            event_name="workflow_dispatch",
            code_changed="false",
            inputs={"suite": "weekly"},
        )
        self.assertTrue(plan_weekly["run_weekly_smoke"])
        self.assertIn("test-built-weekly", plan_weekly["required_jobs"])

        plan_ref = plan_ci(
            event_name="workflow_dispatch",
            code_changed="true",
            inputs={"run_reference_botplay": "true", "botplay_extra_distros": "true", "run_botplay_bisect": "true"},
        )
        self.assertIn("test-rom4s-botplay", plan_ref["required_jobs"])
        self.assertIn("test-release-botplay", plan_ref["required_jobs"])
        self.assertIn("test-rom4s-botplay-extra", plan_ref["required_jobs"])
        self.assertIn("test-built-botplay-extra", plan_ref["required_jobs"])
        self.assertIn("test-botplay-bisect", plan_ref["required_jobs"])

    def test_windows_eligibility_and_matrices(self):
        """Windows matrix in planner must only contain lines with windows: true."""
        plan = plan_ci(event_name="pull_request", code_changed="true")
        win_matrix = plan["matrices"]["windows"]
        win_lines = {entry["line"] for entry in win_matrix}
        self.assertEqual(win_lines, {"sm12-latest", "sm13-latest"})
        self.assertNotIn("sm11-oldstable", win_lines)

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
            plan = plan_ci(event_name="pull_request", code_changed="true", lines_path=tmp_path)
            self.assertEqual(plan["matrices"]["windows"], [])
            self.assertFalse(plan["run_windows"])
            self.assertNotIn("build-windows", plan["required_jobs"])
            self.assertNotIn("wine-smoke", plan["required_jobs"])

            needs = {job: {"result": "success"} for job in plan["required_jobs"]}
            needs["build-windows"] = {"result": "skipped"}
            needs["wine-smoke"] = {"result": "skipped"}

            ok, errors = evaluate_gate(needs, plan)
            self.assertTrue(ok, f"Gate failed for empty windows matrix: {errors}")
        finally:
            Path(tmp_path).unlink(missing_ok=True)

    def test_css34_line_filtering_sm11_no_windows_and_run_reference_botplay(self):
        """Single-line dispatch for sm11-oldstable with run_reference_botplay=true must omit host and windows, but run reference botplay."""
        plan = plan_ci(
            event_name="workflow_dispatch",
            code_changed="true",
            inputs={"css34_line": "sm11-oldstable", "run_reference_botplay": "true"},
        )
        self.assertEqual(len(plan["matrices"]["build"]), 1)
        self.assertEqual(plan["matrices"]["build"][0]["line"], "sm11-oldstable")
        self.assertEqual(plan["matrices"]["windows"], [])
        self.assertFalse(plan["run_windows"])
        self.assertFalse(plan["run_host"])
        self.assertTrue(plan["run_release_botplay"])
        self.assertNotIn("build-windows", plan["required_jobs"])
        self.assertNotIn("wine-smoke", plan["required_jobs"])
        self.assertNotIn("test-built-smoke", plan["required_jobs"])
        self.assertIn("test-rom4s-botplay", plan["required_jobs"])
        self.assertIn("test-release-botplay", plan["required_jobs"])
        self.assertEqual(len(plan["matrices"]["release_botplay"]), 2)

        needs = {job: {"result": "success"} for job in plan["required_jobs"]}
        needs["build-windows"] = {"result": "skipped"}
        needs["wine-smoke"] = {"result": "skipped"}
        needs["test-built-smoke"] = {"result": "skipped"}

        ok, errors = evaluate_gate(needs, plan)
        self.assertTrue(ok, f"Gate failed for sm11-oldstable dispatch: {errors}")

    def test_css34_line_filtering_sm12_with_windows_and_extra_images(self):
        """Single-line dispatch for sm12-latest with botplay_extra_distros=true must include windows and preserve extra image rows."""
        plan = plan_ci(
            event_name="workflow_dispatch",
            code_changed="true",
            inputs={"css34_line": "sm12-latest", "botplay_extra_distros": "true"},
        )
        self.assertEqual(len(plan["matrices"]["build"]), 1)
        self.assertEqual(plan["matrices"]["build"][0]["line"], "sm12-latest")
        self.assertEqual(len(plan["matrices"]["windows"]), 1)
        self.assertTrue(plan["run_windows"])
        self.assertFalse(plan["run_host"])
        self.assertIn("build-windows", plan["required_jobs"])
        self.assertIn("wine-smoke", plan["required_jobs"])
        self.assertIn("test-rom4s-botplay-extra", plan["required_jobs"])
        # sm12 has no built botplay_extra rows: an empty `line` vector must not run.
        self.assertEqual(plan["matrices"]["botplay_extra"]["line"], [])
        self.assertFalse(plan["run_built_botplay_extra"])
        self.assertNotIn("test-built-botplay-extra", plan["required_jobs"])
        self.assertEqual(len(plan["matrices"]["botplay_extra_images"]), 3)

    def test_botplay_extra_runs_built_matrix_only_with_lines(self):
        for line, expected in (("sm13-latest", True), ("sm11-oldstable", False), ("", True)):
            with self.subTest(line=line):
                inputs = {"botplay_extra_distros": "true"}
                if line:
                    inputs["css34_line"] = line
                plan = plan_ci(event_name="workflow_dispatch", code_changed="true", inputs=inputs)
                self.assertEqual(plan["run_built_botplay_extra"], expected)
                self.assertEqual("test-built-botplay-extra" in plan["required_jobs"], expected)
                self.assertEqual(bool(plan["matrices"]["botplay_extra"].get("line")), expected)

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
        """Invalid or inactive css34_line input or incompatible bisect input must raise ValueError."""
        with self.assertRaises(ValueError):
            plan_ci(
                event_name="workflow_dispatch",
                code_changed="true",
                inputs={"css34_line": "invalid-line"},
            )

        with self.assertRaises(ValueError):
            plan_ci(
                event_name="workflow_dispatch",
                code_changed="true",
                inputs={"css34_line": "sm13-dev"},
            )

        with self.assertRaises(ValueError):
            plan_ci(
                event_name="workflow_dispatch",
                code_changed="true",
                inputs={"css34_line": "sm11-oldstable", "run_botplay_bisect": "true"},
            )

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
            build_lines = {entry["line"] for entry in plan["matrices"]["build"]}
            win_lines = {entry["line"] for entry in plan["matrices"]["windows"]}

            self.assertIn("sm14-test", build_lines)
            self.assertIn("sm14-test", win_lines)
        finally:
            Path(tmp_path).unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
