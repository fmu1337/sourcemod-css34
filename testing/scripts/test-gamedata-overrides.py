#!/usr/bin/env python3
"""A frozen line's gamedata hotfix counts in the package checks, and only then.

check-css34-gamedata.py --allow-custom treats <name>.games/custom/*.txt as SourceMod
overrides (read after the shipped file, keys replace the shipped values);
check-package.sh passes it only with HOTFIX_DIR, and frozen-verify.yml sets
HOTFIX_DIR to hotfixes/<line> when that tree exists (docs/FREEZE.md).
"""

import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "testing/scripts/check-css34-gamedata.py"
ASSETS = ROOT / "builder/assets/gamedata"
HOTFIX = ROOT / "hotfixes/sm11-oldstable"
OVERRIDE = "core.games/custom/css34-hinttext-prebyte.txt"
HINT_KEY = '"HintTextPreByte"'


class GamedataOverrides(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.gamedata = Path(self.temp.name) / "gamedata"
        shutil.copytree(ASSETS, self.gamedata)

    def check(self, *flags):
        return subprocess.run(["python3", str(CHECK), str(self.gamedata), *flags],
                              capture_output=True, text=True)

    def drop_hint_key(self):
        """The frozen sm11 package: core.games without HintTextPreByte."""
        path = self.gamedata / "core.games/common.games.txt"
        lines = path.read_text(encoding="latin-1").splitlines(keepends=True)
        kept = [line for line in lines if HINT_KEY not in line]
        self.assertEqual(len(kept), len(lines) - 1)
        path.write_text("".join(kept), encoding="latin-1")

    def add_override(self, rel, source=None, text=None):
        target = self.gamedata / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if source is not None:
            shutil.copyfile(source, target)
        else:
            target.write_text(text, encoding="latin-1")

    def test_active_contract_passes_without_overrides(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_hint_key_fails(self):
        self.drop_hint_key()
        result = self.check("--allow-custom")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HintTextPreByte", result.stderr)

    def test_sm11_hotfix_override_satisfies_the_contract(self):
        self.drop_hint_key()
        self.add_override(OVERRIDE, source=HOTFIX / "addons/sourcemod/gamedata" / OVERRIDE)
        result = self.check("--allow-custom")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("custom gamedata overrides: " + OVERRIDE, result.stdout)

    def test_overrides_are_unexpected_without_the_flag(self):
        self.drop_hint_key()
        self.add_override(OVERRIDE, source=HOTFIX / "addons/sourcemod/gamedata" / OVERRIDE)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected upstream gamedata: " + OVERRIDE, result.stderr)

    def test_override_of_another_directory_does_not_count(self):
        self.drop_hint_key()
        self.add_override("sdktools.games/custom/hint.txt",
                          source=HOTFIX / "addons/sourcemod/gamedata" / OVERRIDE)
        result = self.check("--allow-custom")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HintTextPreByte", result.stderr)

    def test_forbidden_entry_in_an_override_fails(self):
        self.add_override("sdkhooks.games/custom/bad.txt",
                          text='"Games"\n{\n\t"cstrike"\n\t{\n\t\t"Offsets"\n\t\t{\n'
                               '\t\t\t"GetMaxHealth"\n\t\t\t{\n\t\t\t\t"linux"\t"107"\n'
                               '\t\t\t}\n\t\t}\n\t}\n}\n')
        result = self.check("--allow-custom")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('"GetMaxHealth"', result.stderr)

    def test_check_package_refuses_a_hotfix_without_addons(self):
        package = Path(self.temp.name) / "sm.tar.gz"
        with tarfile.open(package, "w:gz") as tar:
            tar.add(self.gamedata, arcname="addons/sourcemod/gamedata")
        empty = Path(self.temp.name) / "empty-hotfix"
        empty.mkdir()
        env = dict(os.environ, SM_PACKAGE=str(package), HOTFIX_DIR=str(empty))
        result = subprocess.run(["bash", str(ROOT / "testing/scripts/check-package.sh")],
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("has no addons/", result.stderr)

    def test_wiring(self):
        package_check = (ROOT / "testing/scripts/check-package.sh").read_text()
        self.assertIn("gamedata_args+=(--allow-custom)", package_check)
        self.assertIn('if [[ -n "${HOTFIX_DIR}" ]]; then', package_check)
        smoke = (ROOT / "testing/scripts/release-smoke.sh").read_text()
        self.assertIn("export HOTFIX_DIR", smoke)
        self.assertIn('cp -R "/workspace/${HOTFIX_DIR}/." /workspace/.ci-server/cstrike/', smoke)
        verify = (ROOT / ".github/workflows/frozen-verify.yml").read_text()
        self.assertIn('if [[ -d "hotfixes/${LINE}" ]]; then HOTFIX_DIR="hotfixes/${LINE}"; fi', verify)
        self.assertIn("LINE: ${{ matrix.line }}", verify)


if __name__ == "__main__":
    unittest.main()
