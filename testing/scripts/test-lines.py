#!/usr/bin/env python3
"""Exercise pin generation and drift failures in an isolated repository copy."""

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


class LinesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("builder/lines.py", "builder/lines.json", "builder/versions.env",
                     "builder/generated/ci-matrix.json", "builder/generated/tag-map.sh",
                     "README.md",
                     "builder/checkout-deps.sh", "builder/write-build-stamps.sh",
                     "testing/scripts/check-version-copies.sh",
                     ".github/workflows/ci.yml",
                     ".github/workflows/release.yml"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def run_command(self, command, success=True):
        result = subprocess.run([sys.executable, str(self.root / "builder/lines.py"), command],
                                cwd=self.temp.name, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_generation_is_repeatable(self):
        target = self.root / "builder/versions.env"
        original = target.read_bytes()
        target.unlink()
        self.run_command("gen")
        self.assertEqual(target.read_bytes(), original)
        self.run_command("gen")
        self.assertEqual(target.read_bytes(), original)
        self.run_command("check")

    def test_manual_edit_is_rejected_without_rewriting(self):
        target = self.root / "builder/versions.env"
        changed = target.read_text() + "\nSM_LATEST_REV=1\n"
        target.write_text(changed)
        self.assertIn("stale builder/versions.env", self.run_command("check", False).stderr)
        self.assertEqual(target.read_text(), changed)

    def test_pin_change_requires_generation_then_matches(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["pins"]["SM_LATEST"]["rev"] += 1
        target.write_text(json.dumps(data))
        self.assertIn("stale", self.run_command("check", False).stderr)
        self.run_command("gen")
        self.run_command("check")
        matrix = json.loads((self.root / "builder/generated/ci-matrix.json").read_text())
        sm12 = next(row for row in matrix["build"] if row["line"] == "sm12-latest")
        self.assertTrue(sm12["sm_expect"].endswith("." + str(data["pins"]["SM_LATEST"]["rev"])))
        readme = (self.root / "README.md").read_text()
        self.assertIn(sm12["sm_expect"], readme)
        tag_map = (self.root / "builder/generated/tag-map.sh").read_text()
        self.assertIn(sm12["sm_expect"] + "-mm1.12.0", tag_map)

    def test_debian_matrix_requires_new_os_and_drops_latest(self):
        matrix = json.loads((self.root / "builder/generated/ci-matrix.json").read_text())
        lines = ("sm11-oldstable", "sm12-latest", "sm13-latest")
        per_pr = ("centos:7", "ubuntu:24.04", "debian:13")
        weekly = ("debian:8", "debian:9", "debian:10", "debian:11",
                  "ubuntu:14.04", "ubuntu:16.04", "ubuntu:18.04", "rockylinux:9")
        pairs = [(row["line"], row["image_name"]) for row in matrix["debian"]]
        self.assertNotIn(("sm13-latest", "debian:latest"), pairs)
        self.assertNotIn(("sm13-latest", "debian:11"), pairs)
        for line in lines:
            for image in per_pr:
                self.assertIn((line, image), pairs)
            for image in weekly:
                self.assertNotIn((line, image), pairs)
        self.assertTrue(all("allow_failure" not in row for row in matrix["debian"]))
        self.assertTrue(all(row["image"] == matrix["images"][row["image_name"]] for row in matrix["debian"]))
        weekly_pairs = [(row["line"], row["image_name"]) for row in matrix["weekly"]]
        for line in lines:
            for image in weekly:
                self.assertIn((line, image), weekly_pairs)
        self.assertEqual([row["image_name"] for row in matrix["botplay"]], ["debian:11"] * 3)
        self.assertEqual([row["image_name"] for row in matrix["weekly_botplay"]], ["centos:7"] * 3)
        self.assertEqual([row["line"] for row in matrix["botplay"]], list(lines))
        self.assertTrue(all("@sha256:" in row["image"] for row in matrix["weekly"] + matrix["botplay"]))
        self.assertEqual([row["line"] for row in matrix["host"]], ["sm13-latest"])
        self.assertNotIn("rhel", matrix)
        for name in (".github/workflows/ci.yml", ".github/workflows/release.yml"):
            self.assertNotIn("sha256:", (self.root / name).read_text(), name)

    def test_duplicate_image_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["lines"]["sm12-latest"]["smoke"].append({"image": "ubuntu:24.04"})
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("lists image ubuntu:24.04 twice", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

    def test_known_bad_pointer_pin_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["pins"]["SM_LATEST"]["rev"] = 7245
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("known-bad tag", self.run_command("check", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

    def test_allow_failure_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["lines"]["sm13-latest"]["smoke"][0]["allow_failure"] = True
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("invalid smoke entry", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

    def test_unpinned_weekly_image_is_rejected(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["weekly_smoke"].append("debian:7")
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("not pinned", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)

    def test_malformed_sha_does_not_overwrite_generated_file(self):
        target = self.root / "builder/lines.json"
        data = json.loads(target.read_text())
        data["pins"]["MM_112"]["commit"] = "not-a-sha"
        target.write_text(json.dumps(data))
        original = (self.root / "builder/versions.env").read_bytes()
        self.assertIn("full SHA", self.run_command("gen", False).stderr)
        self.assertEqual((self.root / "builder/versions.env").read_bytes(), original)


class RepointResolverTest(unittest.TestCase):
    def test_linux_smoke_uses_already_published_checksums(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Smoke public release URLs in", 1)[1].split("      - name:", 1)[0]
        self.assertIn("SUMS_ASSET: ${{ needs.resolve-line.outputs.repoint == '1' && 'SHA256SUMS' || 'SHA256SUMS.linux' }}", step)
        upload = workflow.split("      - name: Attach Linux packages", 1)[1].split("\n  windows:", 1)[0]
        self.assertIn("SHA256SUMS.linux", upload)


    @classmethod
    def setUpClass(cls):
        # Dynamically extract decision code from builder/scripts/update-line-pointer.sh
        script_content = (ROOT / "builder/scripts/update-line-pointer.sh").read_text(encoding="utf-8")
        match_decision = re.search(r"python3 - \"\$line_json\".*?<<'PY'\n(.*?)\nPY", script_content, re.DOTALL)
        if not match_decision:
            raise RuntimeError("Failed to extract decision python script from update-line-pointer.sh")
        cls.pointer_decision_code = match_decision.group(1)

        # Dynamically extract smoke-pointer verification code from .github/workflows/release.yml
        workflow_content = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        match_smoke = re.search(r"curl -fsSL \"\$\{BASE_URL\}/lines\.json\" \| .*? python3 -c '(.*?)'\n", workflow_content, re.DOTALL)
        if not match_smoke:
            raise RuntimeError("Failed to extract smoke-pointer python validation code from release.yml")
        raw_code = match_smoke.group(1)
        import textwrap
        cls.smoke_pointer_code = textwrap.dedent(raw_code)

    def run_pointer_decision(self, path, line, tag, smoke, sm_json, mm_json, ptr, repo, src_time, force_repoint, decision_path):
        cmd = [sys.executable, "-c", self.pointer_decision_code, str(path), line, tag, smoke,
               json.dumps(sm_json) if isinstance(sm_json, dict) else str(sm_json),
               json.dumps(mm_json) if isinstance(mm_json, dict) else str(mm_json),
               ptr, repo, str(src_time), str(force_repoint), str(decision_path)]
        return subprocess.run(cmd, capture_output=True, text=True)

    def run_release_resolver_script(self, check_dir, sm_files, mm_files, base_tag, tag_map_line, lines_json_path):
        script_path = ROOT / "builder/scripts/resolve-repoint-pair.py"
        cmd = [sys.executable, str(script_path),
               base_tag, tag_map_line, str(lines_json_path), str(check_dir)] + list(sm_files) + ["---MM---"] + list(mm_files)
        return subprocess.run(cmd, capture_output=True, text=True)

    def run_smoke_pointer_check(self, line_json_dict, env_dict):
        cmd = [sys.executable, "-c", self.smoke_pointer_code]
        input_data = json.dumps(line_json_dict)
        return subprocess.run(cmd, input=input_data, capture_output=True, text=True, env=dict(os.environ, **env_dict))

    def test_repoint_decision_switch_and_stale_and_force(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            line_json = tmp_path / "lines.json"
            decision_file = tmp_path / "decision"

            sm_manifest = {
                "sm_version": "1.12.0.7253", "sm_commit": "88713a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f",
                "mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                "extension_api": 14, "extension_api_min": 1, "metamod_binary": "metamod.2.ep1"
            }
            mm_manifest = {
                "mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                "metamod_binary": "metamod.2.ep1"
            }

            line_json.write_text("{}")
            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7253-mm1.12.0", "pass",
                                            sm_manifest, mm_manifest, "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1600000000, "0", decision_file)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(decision_file.read_text(), "switch")
            saved = json.loads(line_json.read_text())["sm12-latest"]
            self.assertEqual(saved["tag"], "1.12.0.7253-mm1.12.0")
            self.assertEqual(saved["source_commit_time"], 1600000000)

            # Older commit time without force -> stale decision
            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7200-mm1.12.0", "pass",
                                            sm_manifest, mm_manifest, "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1500000000, "0", decision_file)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(decision_file.read_text(), "stale")
            saved = json.loads(line_json.read_text())["sm12-latest"]
            self.assertEqual(saved["tag"], "1.12.0.7253-mm1.12.0") # intact

            # Older commit time WITH force -> force repoint rollback
            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7200-mm1.12.0", "pass",
                                            sm_manifest, mm_manifest, "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1500000000, "1", decision_file)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(decision_file.read_text(), "switch")
            saved = json.loads(line_json.read_text())["sm12-latest"]
            self.assertEqual(saved["tag"], "1.12.0.7200-mm1.12.0")

    def test_repoint_decision_failed_smoke_records_candidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            line_json = tmp_path / "lines.json"
            decision_file = tmp_path / "decision"

            line_json.write_text(json.dumps({
                "sm12-latest": {
                    "tag": "1.12.0.7253-mm1.12.0", "smoke": "pass", "source_commit_time": 1600000000
                }
            }))

            sm_manifest = {
                "sm_version": "1.12.0.7255", "sm_commit": "88713a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f",
                "mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                "extension_api": 14, "extension_api_min": 1, "metamod_binary": "metamod.2.ep1"
            }
            mm_manifest = {
                "mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                "metamod_binary": "metamod.2.ep1"
            }

            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7255-mm1.12.0", "fail",
                                            sm_manifest, mm_manifest, "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1610000000, "0", decision_file)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(decision_file.read_text(), "record")
            saved = json.loads(line_json.read_text())["sm12-latest"]
            self.assertEqual(saved["tag"], "1.12.0.7253-mm1.12.0") # served tag retained
            self.assertEqual(saved["candidate"]["tag"], "1.12.0.7255-mm1.12.0")
            self.assertEqual(saved["candidate"]["smoke"], "fail")

    def test_repoint_decision_rejects_corrupted_or_mismatched_manifests(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            line_json = tmp_path / "lines.json"
            decision_file = tmp_path / "decision"
            line_json.write_text("{}")

            # Corrupted JSON
            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7253-mm1.12.0", "pass",
                                            "not json", "not json", "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1600000000, "0", decision_file)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("Invalid SM package manifest JSON", res.stderr)

            # Mismatched mm_version
            sm = {"sm_version": "1.12.0.7253", "sm_commit": "88713a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f",
                  "mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                  "extension_api": 14, "extension_api_min": 1, "metamod_binary": "metamod.2.ep1"}
            mm = {"mm_version": "1.10.7-dev", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                  "metamod_binary": "metamod.2.ep1"}
            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7253-mm1.12.0", "pass",
                                            sm, mm, "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1600000000, "0", decision_file)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("mismatch", res.stderr)

            # Placeholder string value
            sm_placeholder = dict(sm, sm_version="null")
            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7253-mm1.12.0", "pass",
                                            sm_placeholder, mm, "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1600000000, "0", decision_file)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("placeholder value", res.stderr)

            # Invalid SHA format
            mm_matching = {"mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                           "metamod_binary": "metamod.2.ep1"}
            sm_bad_sha = dict(sm, sm_commit="invalid_sha_123")
            res = self.run_pointer_decision(line_json, "sm12-latest", "1.12.0.7253-mm1.12.0", "pass",
                                            sm_bad_sha, mm_matching, "line-sm12-latest", "fmu1337/sourcemod-css34",
                                            1600000000, "0", decision_file)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("Invalid sm_commit format", res.stderr)

    def test_release_resolver_multi_candidates_filtering(self):
        lines_json = ROOT / "builder/lines.json"
        with tempfile.TemporaryDirectory() as tmp:
            check_dir = Path(tmp)

            def create_tarball(filename, manifest_data, subpath):
                stage = check_dir / "stage" / filename
                stage.mkdir(parents=True, exist_ok=True)
                mfile = stage / subpath
                mfile.parent.mkdir(parents=True, exist_ok=True)
                mfile.write_text(json.dumps(manifest_data))
                tar_path = check_dir / filename
                subprocess.run(["tar", "-czf", str(tar_path), "-C", str(stage), "addons"], check=True)
                shutil.rmtree(stage)

            # SM12 valid manifest
            sm12_manifest = {
                "line": "sm12-latest", "sm_version": "1.12.0.7253", "sm_commit": "88713a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f",
                "mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                "metamod_binary": "metamod.2.ep1"
            }
            # SM13 valid manifest
            sm13_manifest = {
                "line": "sm13-latest", "sm_version": "1.13.0.7472", "sm_commit": "88713a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f",
                "mm_version": "1.12.0-dev+1226", "mm_commit": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
                "metamod_binary": "metamod.2.ep1"
            }

            create_tarball("sourcemod-1.12.0-css34-linux.tar.gz", sm12_manifest, "addons/sourcemod/css34-package.json")
            create_tarball("sourcemod-1.13.0-css34-linux.tar.gz", sm13_manifest, "addons/sourcemod/css34-package.json")

            create_tarball("mmsource-1.12.0-css34-linux.tar.gz", sm12_manifest, "addons/metamod/css34-package.json")
            create_tarball("mmsource-1.13.0-css34-linux.tar.gz", sm13_manifest, "addons/metamod/css34-package.json")

            sm_files = ["sourcemod-1.12.0-css34-linux.tar.gz", "sourcemod-1.13.0-css34-linux.tar.gz"]
            mm_files = ["mmsource-1.12.0-css34-linux.tar.gz", "mmsource-1.13.0-css34-linux.tar.gz"]

            # Run 1: Filter for tag mapped to sm12-latest in a copy of check_dir
            with tempfile.TemporaryDirectory() as run1_dir:
                run1_path = Path(run1_dir)
                for f in sm_files + mm_files:
                    shutil.copyfile(check_dir / f, run1_path / f)
                res = self.run_release_resolver_script(run1_path, sm_files, mm_files, "1.12.0.7253-mm1.12.0", "sm12-latest", lines_json)
                self.assertEqual(res.returncode, 0, res.stderr)
                out = json.loads(res.stdout.strip())
                self.assertEqual(out["line"], "sm12-latest")
                self.assertEqual(out["sm_asset"], "sourcemod-1.12.0-css34-linux.tar.gz")
                self.assertEqual(out["mm_asset"], "mmsource-1.12.0-css34-linux.tar.gz")

            # Run 2: Historical unmapped tag (tag_map_line=""), resolves single valid candidate sm12 if sm13 is removed
            with tempfile.TemporaryDirectory() as run2_dir:
                run2_path = Path(run2_dir)
                shutil.copyfile(check_dir / "sourcemod-1.12.0-css34-linux.tar.gz", run2_path / "sourcemod-1.12.0-css34-linux.tar.gz")
                shutil.copyfile(check_dir / "mmsource-1.12.0-css34-linux.tar.gz", run2_path / "mmsource-1.12.0-css34-linux.tar.gz")
                res = self.run_release_resolver_script(run2_path, ["sourcemod-1.12.0-css34-linux.tar.gz"], ["mmsource-1.12.0-css34-linux.tar.gz"], "historical-tag", "", lines_json)
                self.assertEqual(res.returncode, 0, res.stderr)
                out = json.loads(res.stdout.strip())
                self.assertEqual(out["line"], "sm12-latest")

            # Run 3: Without tag-map mapping, both pairs are valid -> ambiguity error
            with tempfile.TemporaryDirectory() as run3_dir:
                run3_path = Path(run3_dir)
                for f in sm_files + mm_files:
                    shutil.copyfile(check_dir / f, run3_path / f)
                res_ambig = self.run_release_resolver_script(run3_path, sm_files, mm_files, "custom-tag", "", lines_json)
                self.assertNotEqual(res_ambig.returncode, 0)
                self.assertIn("Ambiguous SM/MM package pairs", res_ambig.stderr)

    def test_known_bad_and_archived_and_no_pointer_line_rules(self):
        tag_map_script = (ROOT / "builder/generated/tag-map.sh").read_text(encoding="utf-8")
        # Execute actual bash helper functions from tag-map.sh to verify function definitions
        bash_cmd = f"source '{ROOT}/builder/generated/tag-map.sh' && css34_tag_is_known_bad 1.12.0.7245-mm1.12.0 && css34_line_for_tag 1.12.0.7257-mm1.12.0"
        res = subprocess.run(["bash", "-c", bash_cmd], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "sm12-latest")

        # Validate line pointer rules in lines.json
        lines_data = json.loads((ROOT / "builder/lines.json").read_text(encoding="utf-8"))
        self.assertTrue(lines_data["lines"]["sm12-latest"]["pointer"])
        self.assertTrue(lines_data["lines"]["sm13-latest"]["pointer"])
        self.assertFalse(lines_data["lines"]["sm13-dev"]["pointer"])
        self.assertFalse(lines_data["lines"]["sm13-mm20-khook"]["releasable"])

    def test_annotated_tag_commit_time_and_deref_resolution(self):
        # Create a temporary git repo to create an actual annotated tag
        with tempfile.TemporaryDirectory() as tmp_repo:
            repo_path = Path(tmp_repo)
            subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo_path, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo_path, check=True)
            (repo_path / "file.txt").write_text("hello")
            subprocess.run(["git", "add", "file.txt"], cwd=repo_path, check=True)
            subprocess.run(["git", "commit", "-m", "initial commit"], cwd=repo_path, check=True)

            commit_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo_path, capture_output=True, text=True, check=True).stdout.strip()

            # Create annotated tag
            subprocess.run(["git", "tag", "-a", "v1.0.0-annotated", "-m", "annotated tag message"], cwd=repo_path, check=True)

            # Dereference tag to target commit SHA
            tag_target = subprocess.run(["git", "rev-parse", "v1.0.0-annotated^{commit}"], cwd=repo_path, capture_output=True, text=True, check=True).stdout.strip()
            self.assertEqual(tag_target, commit_sha)

            # Get commit time of target commit
            commit_time = subprocess.run(["git", "show", "-s", "--format=%ct", "v1.0.0-annotated^{commit}"], cwd=repo_path, capture_output=True, text=True, check=True).stdout.strip()
            self.assertGreater(int(commit_time), 1600000000)

    def test_smoke_pointer_verification_code_path(self):
        # Case 1: Valid served build matching target tag and time
        line_data = {"sm12-latest": {"smoke": "pass", "tag": "1.12.0.7253-mm1.12.0", "source_commit_time": 1600000000}}
        env = {"LINE": "sm12-latest", "TAG": "1.12.0.7253-mm1.12.0", "TARGET_TIME": "1600000000", "FORCE_REPOINT": "0"}
        res = self.run_smoke_pointer_check(line_data, env)
        self.assertEqual(res.returncode, 0, res.stderr)

        # Case 2: FORCE_REPOINT=1 with mismatched served tag -> failure
        line_data_mismatch = {"sm12-latest": {"smoke": "pass", "tag": "1.12.0.7200-mm1.12.0", "source_commit_time": 1500000000}}
        env_force_mismatch = {"LINE": "sm12-latest", "TAG": "1.12.0.7253-mm1.12.0", "TARGET_TIME": "1600000000", "FORCE_REPOINT": "1"}
        res_force_fail = self.run_smoke_pointer_check(line_data_mismatch, env_force_mismatch)
        self.assertNotEqual(res_force_fail.returncode, 0)
        self.assertIn("FORCE_REPOINT expected pointer to serve", res_force_fail.stderr)

        # Case 3: FORCE_REPOINT=1 with matching served tag and time -> success
        line_data_repointed = {"sm12-latest": {"smoke": "pass", "tag": "1.12.0.7200-mm1.12.0", "source_commit_time": 1500000000}}
        env_force_ok = {"LINE": "sm12-latest", "TAG": "1.12.0.7200-mm1.12.0", "TARGET_TIME": "1500000000", "FORCE_REPOINT": "1"}
        res_force_pass = self.run_smoke_pointer_check(line_data_repointed, env_force_ok)
        self.assertEqual(res_force_pass.returncode, 0, res_force_pass.stderr)

        # Case 4: Non-forced update where served build is newer than target -> notice logged, success
        line_data_newer = {"sm12-latest": {"smoke": "pass", "tag": "1.12.0.7255-mm1.12.0", "source_commit_time": 1610000000}}
        env_older_target = {"LINE": "sm12-latest", "TAG": "1.12.0.7253-mm1.12.0", "TARGET_TIME": "1600000000", "FORCE_REPOINT": "0"}
        res_notice = self.run_smoke_pointer_check(line_data_newer, env_older_target)
        self.assertEqual(res_notice.returncode, 0, res_notice.stderr)
        self.assertIn("line pointer serves newer tag", res_notice.stdout)

    def test_workflow_job_conditions_and_skipped_dependencies(self):
        workflow_content = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        # Ensure smoke-release and botplay-release do not depend on windows or checksums
        self.assertIn("smoke-release:\n    needs: [resolve-line, linux, release-pins]", workflow_content)
        self.assertIn("botplay-release:\n    needs: [resolve-line, linux, release-pins]", workflow_content)
        self.assertIn("line-pointer:\n    needs: [resolve-line, linux, smoke-release, botplay-release]", workflow_content)
        # Verify repoint condition permits repoint=1 without linux/checksums requirement
        self.assertIn("needs.resolve-line.outputs.repoint == '1'", workflow_content)


if __name__ == "__main__":
    unittest.main()
