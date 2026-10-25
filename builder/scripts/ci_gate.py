#!/usr/bin/env python3
"""CI Unified Gate Evaluator.

Evaluates GitHub Actions job results from needs context against the planner's
required jobs list. Ensures required jobs succeeded and no job failed or was
cancelled. Catches unexpected skips, failed/cancelled plan, or failed downstream jobs.
"""

import argparse
import json
import sys


def evaluate_gate(needs_data, plan_data):
    errors = []

    # Check plan job first
    plan_job = needs_data.get("plan")
    if not plan_job:
        errors.append("plan job missing from needs context")
    elif plan_job.get("result") != "success":
        errors.append(f"plan job did not succeed (result={plan_job.get('result')})")

    # Extract required_jobs list
    if isinstance(plan_data, dict):
        required_jobs = plan_data.get("required_jobs") or []
    elif isinstance(plan_data, list):
        required_jobs = plan_data
    else:
        try:
            required_jobs = json.loads(plan_data)
        except Exception:
            required_jobs = []

    # Check all required jobs
    for job_name in required_jobs:
        job_info = needs_data.get(job_name)
        if not job_info:
            errors.append(f"required job '{job_name}' was not found in needs context")
            continue

        result = job_info.get("result")
        if result != "success":
            errors.append(
                f"required job '{job_name}' did not succeed (result={result})"
            )

    # Check for any job in needs that failed or was cancelled
    for job_name, job_info in needs_data.items():
        if isinstance(job_info, dict):
            result = job_info.get("result")
            if result in ("failure", "cancelled"):
                if job_name not in required_jobs:
                    errors.append(
                        f"job '{job_name}' failed or was cancelled (result={result})"
                    )

    return len(errors) == 0, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--needs-json",
        required=True,
        help="JSON string of GitHub Actions needs object",
    )
    parser.add_argument(
        "--plan-json",
        required=True,
        help="JSON string of plan job outputs (or required_jobs array)",
    )

    args = parser.parse_args()

    try:
        needs_data = json.loads(args.needs_json)
    except json.JSONDecodeError as err:
        print(f"FAIL: invalid needs-json: {err}", file=sys.stderr)
        return 1

    try:
        plan_data = json.loads(args.plan_json)
    except json.JSONDecodeError as err:
        print(f"FAIL: invalid plan-json: {err}", file=sys.stderr)
        return 1

    success, errors = evaluate_gate(needs_data, plan_data)

    if success:
        print("OK: Gate checks passed")
        return 0
    else:
        print("FAIL: Gate checks failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
