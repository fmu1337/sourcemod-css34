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


class TestCIPlannerGate(unittest.TestCase):

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
