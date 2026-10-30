#!/usr/bin/env python3
"""Probe the actual ISmmPlugin factory contract and failure paths."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class TestPlapi(unittest.TestCase):
    def test_factory_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            probe = root / "probe"
            subprocess.run(["gcc", "-Wall", "-Wextra", "-Werror", str(ROOT / "testing/tools/plapi-probe.c"),
                            "-o", str(probe), "-ldl"], check=True)
            source = root / "plugin.c"
            source.write_text("""
#include <string.h>
static int api(void *self) { (void)self; return 16; }
static void *table[] = {(void *)api};
static void **plugin = table;
void *CreateInterface(const char *name, int *status) {
    *status = 1;
    if (strcmp(name, "ISmmPlugin") != 0) return 0;
    *status = 0;
    return &plugin;
}
""")
            module = root / "plugin.so"
            subprocess.run(["gcc", "-shared", "-fPIC", str(source), "-o", str(module)], check=True)
            good = subprocess.run([str(probe), str(module)], capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            self.assertEqual(good.stdout.strip(), "PLAPI:16")
            bad = subprocess.run([str(probe), str(module), "wrong-interface"], capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
            missing = subprocess.run([str(probe), str(root / "missing.so")], capture_output=True, text=True)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("dlopen failed", missing.stderr)

if __name__ == "__main__":
    unittest.main()
