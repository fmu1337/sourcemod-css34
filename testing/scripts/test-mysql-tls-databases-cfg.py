#!/usr/bin/env python3
"""mysql-tls-test.sh inserts its probe entries before the last closing brace of
databases.cfg, which SourceMod ships with CRLF line ends. The awk program must
find that brace in CRLF and LF files, and must not rely on POSIX classes
([[:space:]]) that mawk 1.3.3 on debian:8 / ubuntu:14.04 lacks."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "testing/scripts/mysql-tls-test.sh"
ENTRY = '\t"css34_probe"\n\t{\n\t\t"driver"\t\t"mysql"\n\t}\n'
CFG = ['"Databases"', "{", '\t"driver_default"\t\t"mysql"', "", '\t"default"', "\t{",
       '\t\t"driver"\t\t\t"default"', "\t}", "}"]


def awk_program():
    text = SCRIPT.read_text()
    match = re.search(r"""ENTRIES="\$\{entries\}" awk '\n(.*?)' "\$\{databases\}\.mysql-tls\"""", text, re.S)
    if not match:
        raise AssertionError("awk insertion program not found in mysql-tls-test.sh")
    return match.group(1)


class DatabasesCfgInsertion(unittest.TestCase):
    def run_awk(self, content):
        env = dict(os.environ, ENTRIES=ENTRY)
        return subprocess.run(["awk", awk_program()], input=content.encode(), env=env,
                              capture_output=True, check=False)

    def test_no_posix_classes(self):
        self.assertNotIn("[[:", awk_program())

    def test_inserts_before_last_brace(self):
        for eol in ("\r\n", "\n"):
            with self.subTest(eol=repr(eol)):
                result = self.run_awk(eol.join(CFG) + eol)
                self.assertEqual(result.returncode, 0, result.stderr)
                out = result.stdout.decode()
                body, _, tail = out.rpartition(ENTRY)
                self.assertTrue(body, out)
                self.assertTrue(body.endswith("\t}" + eol), body)
                self.assertEqual(tail, "}" + eol)

    def test_no_brace_fails(self):
        self.assertNotEqual(self.run_awk('"Databases"\r\n{\r\n').returncode, 0)


if __name__ == "__main__":
    if shutil.which("awk") is None:
        raise SystemExit("awk is required")
    unittest.main()
