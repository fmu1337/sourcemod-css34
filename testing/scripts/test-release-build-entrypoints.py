#!/usr/bin/env python3
"""Exercise release orchestration and the Docker wrapper without full builds.

The release step uses real pin/path resolution and package-set verification;
ELF checks are stubbed (covered separately by package regression tests).
Docker is replaced at the process boundary to inspect the actual run arguments.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Entrypoints(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in (
            "builder/package-paths.sh", "builder/resolve-version.sh",
            "builder/versions.env", "builder/lines.json", "builder/lines.py",
            "builder/resolve-metamod-pins.py", "builder/py.sh",
            "builder/docker/build.sh",
            "testing/scripts/verify-line-metamod-packages.sh",
        ):
            dest = self.root / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, dest)
        self.env = os.environ.copy()
        for key in ("PACKAGES_DIR", "MMS_LINE", "CHECK_METAMOD_SCRIPT",
                    "CSS34_DEBUG_TRACE"):
            self.env.pop(key, None)
        self.env.update(GITHUB_OUTPUT=str(self.root / "outputs"),
                        CAPTURE=str(self.root / "calls"))

    def executable(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + content)
        path.chmod(0o755)

    def release(self, line, missing_secondary=False, reject_secondary=False):
        self.env["CSS34_LINE"] = line
        self.executable("testing/scripts/check-package.sh", 'test -f "$SM_PACKAGE"\n')
        self.executable("testing/scripts/check-metamod-package.sh", """
test -f "$MM_PACKAGE"
printf '%s %s %s\n' "$MM_PACKAGE" "$EXPECTED_MM_REV" "$EXPECTED_MM_COMMIT" >> "$CAPTURE"
[[ "${REJECT_REV:-}" != "$EXPECTED_MM_REV" ]]
""")
        data = json.loads((self.root / "builder/lines.json").read_text())
        config = data["lines"][line]
        sm = data["pins"][config["sourcemod"]]
        packages = self.root / "packages"
        packages.mkdir()
        sm_name = f'sourcemod-1.{sm["major"]}.0-git{sm["rev"]}-css34-linux.tar.gz'
        (packages / sm_name).touch()
        mm_names = []
        for role in ("metamod", "secondary_metamod"):
            if role not in config:
                continue
            pin = data["pins"][config[role]]
            version = {"1.10": "1.10.7", "1.12": "1.12.0"}[pin["mode"]]
            name = f'mmsource-{version}-git{pin["rev"]}-css34-linux.tar.gz'
            mm_names.append(name)
            if role == "secondary_metamod":
                if missing_secondary:
                    continue
                if reject_secondary:
                    self.env["REJECT_REV"] = str(pin["rev"])
            (packages / name).touch()
        # Older packages must not affect primary selection.
        (packages / "mmsource-1.12.0-git1-css34-linux.tar.gz").touch()
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Static package checks\n", 1)[1]
        step = step.split("      - name:", 1)[0]
        self.assertIn("CSS34_LINE: ${{ needs.resolve-line.outputs.css34_line }}", step)
        script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        result = subprocess.run(["bash", "-c", script], cwd=self.root,
                                env=self.env, capture_output=True, text=True)
        return result, sm_name, mm_names

    def test_sm11_checks_both_and_outputs_primary(self):
        result, sm, mm = self.release("sm11-oldstable")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "outputs").read_text(),
                         f"sm_asset={sm}\nmm_asset={mm[0]}\n")
        calls = (self.root / "calls").read_text().splitlines()
        self.assertEqual([row.split()[0] for row in calls],
                         ["packages/" + name for name in mm])

    def test_sm11_missing_secondary_fails_before_outputs(self):
        result, _, _ = self.release("sm11-oldstable", missing_secondary=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected secondary Metamod package", result.stderr)
        self.assertFalse((self.root / "outputs").exists())

    def test_sm11_secondary_check_failure_propagates(self):
        result, _, _ = self.release("sm11-oldstable", reject_secondary=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "outputs").exists())

    def test_sm13_single_mm(self):
        result, sm, mm = self.release("sm13-latest")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "outputs").read_text(),
                         f"sm_asset={sm}\nmm_asset={mm[0]}\n")

    def test_docker_debug_default_and_opt_in(self):
        self.executable("bin/docker", """
if [[ "$1" == info ]]; then exit 0; fi
printf '%s\n' "$@" > "$CAPTURE"
exit 42
""")
        self.env.update(PATH=str(self.root / "bin") + ":" + self.env["PATH"],
                        CSS34_LINE="sm13-latest")
        for value in (None, "1"):
            with self.subTest(debug=value):
                if value is None:
                    self.env.pop("CSS34_DEBUG_TRACE", None)
                else:
                    self.env["CSS34_DEBUG_TRACE"] = value
                result = subprocess.run(["bash", "builder/docker/build.sh"],
                                        cwd=self.root, env=self.env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 42, result.stderr)
                args = (self.root / "calls").read_text().splitlines()
                passed = [args[i + 1] for i, arg in enumerate(args[:-1]) if arg == "-e"]
                self.assertIn("CSS34_DEBUG_TRACE=" + (value or "0"), passed)


if __name__ == "__main__":
    unittest.main()
