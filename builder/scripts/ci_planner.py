#!/usr/bin/env python3
"""CI Planner for GitHub Actions workflows.

Evaluates workflow triggers, path filter outputs, and dispatch parameters against
builder/lines.json to produce GHA matrices, execution flags, and the exact list
of required jobs for the unified gate.

Suites:
  pr      pull requests, master pushes, dispatch suite=pr: smoke on each line's
          `smoke` images, botplay on `botplay_image`, native Windows smoke.
  weekly  schedule, dispatch suite=weekly: smoke on `weekly_smoke` images,
          botplay on `weekly_botplay_image`, native Windows smoke and Wine smoke.
"""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))

from builder.lines import load_manifest, ci_matrix

SUITES = ("pr", "weekly")
# Matrices the workflow consumes, by plan output name.
OUTPUT_MATRICES = ("build", "smoke", "botplay", "windows")


def parse_bool(val):
    if isinstance(val, bool):
        return val
    if isinstance(val, str):
        return val.lower() in ("true", "1", "yes", "y", "on")
    return bool(val)


def filter_matrix_for_line(matrices, css34_line):
    """Keep only the rows of one line in every list matrix."""
    filtered = {}
    for key, val in matrices.items():
        if isinstance(val, list):
            filtered[key] = [
                item for item in val
                if isinstance(item, dict) and item.get("line") == css34_line
            ]
        else:
            filtered[key] = val
    return filtered


def plan_ci(event_name, code_changed, inputs=None, lines_path=None, pins_changed=False):
    if inputs is None:
        inputs = {}
    if lines_path is None:
        lines_path = ROOT / "builder/lines.json"

    lines_data = load_manifest(Path(lines_path))
    matrices = ci_matrix(lines_data)

    code_changed = parse_bool(code_changed)

    requested_suite = (inputs.get("suite") or "pr").strip()
    if requested_suite not in SUITES:
        raise ValueError(f"Unknown suite: '{requested_suite}' (expected one of {', '.join(SUITES)})")

    # Validate css34_line input if provided
    want_line = (inputs.get("css34_line") or "").strip()
    if want_line:
        active_lines = {
            name for name, l in lines_data["lines"].items()
            if l.get("status") == "active"
        }
        if want_line not in active_lines:
            raise ValueError(f"Unknown or inactive CSS34_LINE: '{want_line}'")
        matrices = filter_matrix_for_line(matrices, want_line)

    # Doc-only PRs skip every code job; every other event runs them.
    run_code_jobs = code_changed if event_name == "pull_request" else True

    weekly = event_name == "schedule" or (event_name == "workflow_dispatch" and requested_suite == "weekly")
    suite = "weekly" if weekly else "pr"

    selected = {
        "build": matrices["build"],
        "smoke": matrices["weekly"] if weekly else matrices["debian"],
        "botplay": matrices["weekly_botplay"] if weekly else matrices["botplay"],
        "windows": matrices["windows"],
    }
    if run_code_jobs:
        # An empty matrix makes GitHub fail the job; refuse it here instead.
        for key in ("build", "smoke", "botplay"):
            if not selected[key]:
                raise ValueError(f"{key} matrix is empty for suite {suite}")

    run_windows = run_code_jobs and len(selected["windows"]) > 0
    # Wine runs the same Windows zips as the native smoke: weekly only.
    run_wine = run_windows and weekly

    # README.md pin tables are generated from lines.json: a README-only PR still
    # needs `lines.py check`, even though it skips every build and smoke job.
    run_check_pins = run_code_jobs or parse_bool(pins_changed)

    required_jobs = ["plan"]
    if run_check_pins:
        required_jobs.append("check-pins")
    if run_code_jobs:
        required_jobs.extend([
            "hygiene", "build-linux", "prepare-server", "smoke", "botplay", "host-checks",
        ])
        if run_windows:
            required_jobs.append("build-windows")
        if run_wine:
            required_jobs.append("wine-smoke")

    return {
        "event_name": event_name,
        "code_changed": code_changed,
        "run_code_jobs": run_code_jobs,
        "run_check_pins": run_check_pins,
        "run_windows": run_windows,
        "run_wine": run_wine,
        "suite": suite,
        "default_line": lines_data["default_line"],
        "required_jobs": required_jobs,
        "matrices": selected,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", required=True, help="GitHub event_name")
    parser.add_argument("--code-changed", required=True, help="true/false from dorny/paths-filter")
    parser.add_argument("--pins-changed", default="false", help="true/false: README.md pin tables changed")
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
    if inputs is None:
        inputs = {}

    try:
        plan = plan_ci(args.event_name, args.code_changed, inputs, args.lines_json, args.pins_changed)
    except ValueError as err:
        print(f"FAIL: {err}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(plan, indent=2))

    if args.gha or not args.json:
        for key in OUTPUT_MATRICES:
            print(f"{key}<<EOF")
            print(json.dumps(plan["matrices"][key], separators=(",", ":")))
            print("EOF")

        for flag in ("run_code_jobs", "run_check_pins", "run_windows", "run_wine"):
            print(f"{flag}={'true' if plan[flag] else 'false'}")
        print(f"suite={plan['suite']}")
        print(f"default_line={plan['default_line']}")
        print("required_jobs<<EOF")
        print(json.dumps(plan["required_jobs"]))
        print("EOF")

    return 0


if __name__ == "__main__":
    sys.exit(main())
