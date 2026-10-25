#!/usr/bin/env python3
"""CI Planner for GitHub Actions workflows.

Evaluates workflow triggers, path filter outputs, and dispatch parameters against
builder/lines.json to produce GHA matrices, execution flags, and the exact list
of required jobs for the unified gate.
"""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))

from builder.lines import load_manifest, ci_matrix


def parse_bool(val):
    if isinstance(val, bool):
        return val
    if isinstance(val, str):
        return val.lower() in ("true", "1", "yes", "y", "on")
    return bool(val)


def plan_ci(event_name, code_changed, inputs=None, lines_path=None):
    if inputs is None:
        inputs = {}
    if lines_path is None:
        lines_path = ROOT / "builder/lines.json"

    lines_data = load_manifest(Path(lines_path))
    matrices = ci_matrix(lines_data)

    code_changed = parse_bool(code_changed)

    # Dispatch options
    suite = inputs.get("suite") or "pr"
    run_full_botplay = parse_bool(inputs.get("run_full_botplay_matrix", True))
    run_ref_botplay = parse_bool(inputs.get("run_reference_botplay", False))
    botplay_extra = parse_bool(inputs.get("botplay_extra_distros", False))
    run_bisect = parse_bool(inputs.get("run_botplay_bisect", False))

    # Code jobs execution flag
    if event_name == "pull_request":
        run_code_jobs = code_changed
    else:
        run_code_jobs = True

    # PR smoke vs Weekly smoke flags
    if run_code_jobs:
        if event_name == "schedule" or (event_name == "workflow_dispatch" and suite == "weekly"):
            run_weekly_smoke = True
            run_pr_smoke = False
        else:
            run_weekly_smoke = False
            run_pr_smoke = True
    else:
        run_pr_smoke = False
        run_weekly_smoke = False

    # Required jobs determination
    required_jobs = ["plan"]

    if run_code_jobs:
        required_jobs.extend(["check-pins", "hygiene"])

        if run_pr_smoke:
            required_jobs.extend([
                "build-linux",
                "build-windows",
                "wine-smoke",
                "prepare-server",
                "test-built-debian",
                "test-built-smoke",
            ])
            if run_full_botplay:
                required_jobs.append("test-built-botplay-matrix")

        if run_weekly_smoke:
            required_jobs.extend([
                "build-linux",
                "build-windows",
                "wine-smoke",
                "prepare-server",
                "test-built-weekly",
                "test-built-weekly-botplay",
            ])

        # Workflow dispatch optional jobs
        if event_name == "workflow_dispatch":
            if run_ref_botplay:
                required_jobs.extend(["test-rom4s-botplay", "test-release-botplay"])
            if botplay_extra:
                required_jobs.extend(["test-rom4s-botplay-extra", "test-built-botplay-extra"])
            if run_bisect:
                required_jobs.append("test-botplay-bisect")

    plan_output = {
        "event_name": event_name,
        "code_changed": code_changed,
        "run_code_jobs": run_code_jobs,
        "run_pr_smoke": run_pr_smoke,
        "run_weekly_smoke": run_weekly_smoke,
        "run_windows": run_code_jobs,
        "required_jobs": required_jobs,
        "default_line": lines_data["default_line"],
        "matrices": matrices,
    }
    return plan_output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", required=True, help="GitHub event_name")
    parser.add_argument("--code-changed", required=True, help="true/false from dorny/paths-filter")
    parser.add_argument("--inputs-json", default="{}", help="JSON string of workflow inputs")
    parser.add_argument("--lines-json", default=None, help="Path to builder/lines.json")
    parser.add_argument("--gha", action="store_true", help="Emit GitHub Actions step outputs format")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")

    args = parser.parse_args()

    try:
        inputs = json.loads(args.inputs_json) if args.inputs_json else {}
    except json.JSONDecodeError as err:
        print(f"FAIL: invalid inputs-json: {err}", file=sys.stderr)
        return 1

    plan = plan_ci(args.event_name, args.code_changed, inputs, args.lines_json)

    if args.json:
        print(json.dumps(plan, indent=2))

    if args.gha or not args.json:
        for key, val in plan["matrices"].items():
            print(f"{key}<<EOF")
            print(json.dumps(val, separators=(",", ":")))
            print("EOF")

        print(f"code_changed={'true' if plan['code_changed'] else 'false'}")
        print(f"run_code_jobs={'true' if plan['run_code_jobs'] else 'false'}")
        print(f"run_pr_smoke={'true' if plan['run_pr_smoke'] else 'false'}")
        print(f"run_weekly_smoke={'true' if plan['run_weekly_smoke'] else 'false'}")
        print(f"run_windows={'true' if plan['run_windows'] else 'false'}")
        print(f"default_line={plan['default_line']}")
        print(f"required_jobs<<EOF")
        print(json.dumps(plan["required_jobs"]))
        print("EOF")

    return 0


if __name__ == "__main__":
    sys.exit(main())
