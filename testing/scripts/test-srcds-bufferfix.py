#!/usr/bin/env python3
"""patch-srcds-bufferfix.py: verifies its input, is idempotent, fails closed."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / 'testing/scripts/patch-srcds-bufferfix.py'
ELF_FILES = ('bin/engine_amd.so', 'bin/engine_i486.so', 'bin/engine_i686.so',
             'cstrike/bin/server_i486.so')
SITE = bytes.fromhex('c70424cca95e00e8fcffffff')
AFTER = bytes.fromhex('8b45088b4018c9c3')

SOURCE = ('extern void *memcpy(void *, const void *, unsigned);\n'
          'extern void *memmove(void *, const void *, unsigned);\n'
          'void f(char *a, char *b, unsigned n) { %s }\n')


class BufferFix(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.tree = self.root / 'srv'

    def library(self, body):
        c = self.root / 'lib.c'
        c.write_text(SOURCE % body)
        out = self.root / 'lib.so'
        subprocess.run(['gcc', '-m32', '-fno-builtin', '-nostdlib', '-shared', '-fPIC',
                        str(c), '-o', str(out)], check=True)
        return out.read_bytes()

    def make_tree(self, body='memcpy(a, b, n); memmove(b, a, n);', sites=3):
        lib = self.library(body)
        for rel in ELF_FILES:
            (self.tree / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.tree / rel).write_bytes(lib)
        (self.tree / 'bin/steamclient_i486.so').write_bytes(
            b'\0' * 16 + (SITE + AFTER + b'\0' * 8) * sites)

    def run_patcher(self):
        return subprocess.run([sys.executable, str(PATCHER), str(self.tree)],
                              capture_output=True, text=True)

    def relocs(self, rel):
        return subprocess.check_output(['readelf', '-rW', str(self.tree / rel)], text=True)

    def test_patches_then_second_run_is_noop(self):
        self.make_tree()
        first = self.run_patcher()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertNotIn('memcpy', self.relocs('bin/engine_i486.so'))
        snapshot = {p: p.read_bytes() for p in self.tree.rglob('*.so')}
        second = self.run_patcher()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('already patched', second.stdout)
        self.assertIn('0 assertion site(s), 3 already muted', second.stdout)
        self.assertEqual(snapshot, {p: p.read_bytes() for p in self.tree.rglob('*.so')})

    def test_unknown_binary_without_memcpy_fails(self):
        # Neither stock (memcpy imported) nor patched (zeroed memcpy entry).
        self.make_tree('memmove(b, a, n);')
        result = self.run_patcher()
        self.assertEqual(result.returncode, 1)
        self.assertIn('FAIL', result.stderr)

    def test_not_an_elf_fails(self):
        self.make_tree()
        (self.tree / 'cstrike/bin/server_i486.so').write_bytes(b'MZ not an elf')
        result = self.run_patcher()
        self.assertEqual(result.returncode, 1)
        self.assertIn('FAIL cstrike/bin/server_i486.so', result.stderr)

    def test_wrong_steamclient_fails(self):
        self.make_tree(sites=2)
        result = self.run_patcher()
        self.assertEqual(result.returncode, 1)
        self.assertIn('expected 3 assertion sites', result.stderr)


if __name__ == '__main__':
    unittest.main()
