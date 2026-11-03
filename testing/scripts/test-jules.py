#!/usr/bin/env python3
"""builder/scripts/jules.py and its use in upstream-bump.yml, against a fake Jules API."""
import http.server
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
JULES = ROOT / "builder/scripts/jules.py"
WORKFLOW = ROOT / ".github/workflows/upstream-bump.yml"
OLD, NEW = "b" * 40, "e" * 40


class FakeJules(http.server.BaseHTTPRequestHandler):
    """sessions: create, list, get (COMPLETED on the second get), activities."""
    requests = []
    sessions = []
    gets = {}

    def log_message(self, *args):
        pass

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def record(self, body=None):
        FakeJules.requests.append({"method": self.command, "path": self.path,
                                   "key": self.headers.get("X-Goog-Api-Key"), "body": body})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.record(body)
        if self.headers.get("X-Goog-Api-Key") != "k3y":
            return self.reply(403, {"error": "bad key"})
        sid = str(len(FakeJules.sessions) + 1)
        session = dict(body, name="sessions/" + sid, id=sid, url="https://jules.example/s/" + sid,
                       state="QUEUED")
        FakeJules.sessions.append(session)
        self.reply(200, session)

    def do_GET(self):
        self.record()
        path = self.path.split("?")[0]
        if path == "/sessions":
            return self.reply(200, {"sessions": [{"name": s["name"], "title": s["title"], "url": s["url"]}
                                                 for s in FakeJules.sessions]})
        match = re.fullmatch(r"/sessions/(\d+)(/activities)?", path)
        session = FakeJules.sessions[int(match.group(1)) - 1]
        if match.group(2):
            return self.reply(200, {"activities": [
                {"agentMessaged": {"agentMessage": "first thoughts"}},
                {"progressUpdated": {"title": "reading"}},
                {"agentMessaged": {"agentMessage": "## What changed\nnothing to change"}}]})
        FakeJules.gets[session["name"]] = FakeJules.gets.get(session["name"], 0) + 1
        if FakeJules.gets[session["name"]] >= 2:
            session["state"] = "COMPLETED"
            if session.get("automationMode") == "AUTO_CREATE_PR":
                session["outputs"] = [{"pullRequest": {"url": "https://github.com/x/y/pull/9"}}]
        self.reply(200, session)


class JulesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeJules)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = "http://127.0.0.1:{}".format(cls.server.server_address[1])

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        FakeJules.requests, FakeJules.sessions, FakeJules.gets = [], [], {}
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.env = dict(os.environ, JULES_API_KEY="k3y", JULES_API_URL=self.url,
                        GITHUB_REPOSITORY="fmu1337/sourcemod-css34")

    def run_jules(self, *args, env=None, check=True):
        res = subprocess.run([sys.executable, str(JULES), *args], capture_output=True, text=True,
                             env=env or self.env, timeout=60)
        if check:
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return res

    def prompt(self, kind, context=None):
        args = ["prompt", kind, "--target", "sm13-latest", "--old", OLD, "--new", NEW, "--rev", "7484"]
        if context:
            args += ["--context", str(context)]
        return self.run_jules(*args).stdout

    def test_review_prompt_is_read_only_and_names_the_bump(self):
        text = self.prompt("review")
        self.assertIn("read-only review", text)
        self.assertIn("Do NOT modify any file and do NOT create commits or pull requests", text)
        self.assertIn("`SM_LATEST_13` moves from alliedmodders/sourcemod {} to {}".format(OLD, NEW), text)
        self.assertIn("builder/patches/series/sm13-latest/", text)
        self.assertIn("Never change .github/, testing/, builder/scripts/", text)

    def test_fix_prompt_limits_the_files_and_carries_the_log(self):
        log = self.tmp / "apply.log"
        log.write_text("FAIL: 0003-cstrike-episode1.patch does not apply\n")
        text = self.prompt("fix", log)
        self.assertIn("pins.SM_LATEST_13.commit = " + NEW, text)
        self.assertIn("patch-series.sh refresh <series> for sm13-latest", text)
        self.assertIn("Only builder/lines.json, builder/patches/series/**", text)
        self.assertIn("0003-cstrike-episode1.patch does not apply", text)
        self.assertIn("never weaken, skip or delete a check", text)

    def start(self, title, *extra):
        prompt = self.tmp / "p.md"
        prompt.write_text("do it")
        return json.loads(self.run_jules("start", "--title", title, "--prompt-file", str(prompt),
                                         "--branch", "bump/sm13-latest", *extra).stdout)

    def test_review_session_never_asks_for_a_pr(self):
        session = self.start("review x")
        self.assertEqual(session, {"name": "sessions/1", "url": "https://jules.example/s/1", "existing": False})
        post = [r for r in FakeJules.requests if r["method"] == "POST"][0]
        self.assertEqual(post["key"], "k3y")
        self.assertEqual(post["path"], "/sessions")
        self.assertEqual(post["body"]["sourceContext"], {
            "source": "sources/github/fmu1337/sourcemod-css34",
            "githubRepoContext": {"startingBranch": "bump/sm13-latest"}})
        self.assertNotIn("automationMode", post["body"])

    def test_fix_session_opens_its_own_pr_and_is_not_started_twice(self):
        self.start("fix y", "--auto-pr", "--skip-if-exists")
        self.assertEqual(FakeJules.sessions[0]["automationMode"], "AUTO_CREATE_PR")
        again = self.start("fix y", "--auto-pr", "--skip-if-exists")
        self.assertTrue(again["existing"])
        self.assertEqual(len(FakeJules.sessions), 1)

    def test_wait_reports_the_last_message_and_the_pr(self):
        self.start("fix z", "--auto-pr")
        out = self.tmp / "report.md"
        res = self.run_jules("wait", "sessions/1", "--interval", "0.01", "--timeout", "5", "--out", str(out))
        self.assertIn("state=COMPLETED", res.stderr)
        text = out.read_text()
        self.assertIn("state `COMPLETED`", text)
        self.assertIn("[session](https://jules.example/s/1)", text)
        self.assertIn("https://github.com/x/y/pull/9", text)
        self.assertIn("nothing to change", text)
        self.assertNotIn("first thoughts", text)

    def test_wait_timeout_still_writes_a_report(self):
        self.start("review t")
        res = self.run_jules("wait", "sessions/1", "--interval", "0.01", "--timeout", "0")
        self.assertIn("still running when the workflow stopped waiting", res.stdout)

    def test_missing_or_rejected_key_fails_cleanly(self):
        env = dict(self.env)
        env.pop("JULES_API_KEY")
        prompt = self.tmp / "p.md"
        prompt.write_text("x")
        res = self.run_jules("start", "--title", "t", "--prompt-file", str(prompt), "--branch", "master",
                             env=env, check=False)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("JULES_API_KEY is not set", res.stderr)
        res = self.run_jules("start", "--title", "t", "--prompt-file", str(prompt), "--branch", "master",
                             env=dict(self.env, JULES_API_KEY="wrong"), check=False)
        self.assertIn("HTTP 403", res.stderr)
        self.assertNotIn("Traceback", res.stderr)


class WorkflowTest(unittest.TestCase):
    def setUp(self):
        text = WORKFLOW.read_text()
        self.bump = text.split("\n  bump:\n", 1)[1].split("\n  release:\n", 1)[0]

    def step(self, name):
        return self.bump.split("      - name: " + name, 1)[1].split("\n      - name: ", 1)[0]

    def test_review_is_optional_read_only_and_cannot_fail_the_bump(self):
        step = self.step("Jules review of the bump (read-only)")
        self.assertIn("continue-on-error: true", step)
        self.assertIn("steps.jules.outputs.has == 'true'", step)
        self.assertIn('--branch "$BRANCH"', step)
        self.assertNotIn("--auto-pr", step)
        self.assertIn("--skip-if-exists", step)
        self.assertIn("gh pr comment", step)

    def test_fix_opens_its_own_pr_from_master_only_after_a_failed_apply(self):
        step = self.step("Ask Jules for a minimal fix (own PR)")
        self.assertIn("failure() && steps.apply.outcome == 'failure'", step)
        self.assertIn("continue-on-error: true", step)
        self.assertIn("--auto-pr", step)
        self.assertIn("--branch master", step)
        self.assertIn("--skip-if-exists", step)
        self.assertNotIn("GH_TOKEN", step)

    def test_the_key_reaches_only_the_jules_steps(self):
        steps = self.bump.split("\n      - name: ")
        with_key = [s.split("\n", 1)[0] for s in steps if "secrets.JULES_API_KEY }}" in s]
        self.assertEqual(sorted(with_key), ["Ask Jules for a minimal fix (own PR)",
                                            "Jules review of the bump (read-only)"])
        self.assertNotIn("JULES_API_KEY: ${{ secrets.JULES_API_KEY }}",
                         self.bump.split("    steps:\n", 1)[0])


if __name__ == "__main__":
    unittest.main()
