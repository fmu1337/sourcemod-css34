#!/usr/bin/env python3
"""Host-side regression tests; require GCC and binutils, no game server."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / 'testing/scripts/check-unversioned-imports.py'
PATCH = ROOT / 'builder/patches/patch-pgsql-explicit-bzero.py'


class Imports(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def compile(self, source):
        c = self.root / 'test.c'
        c.write_text(source)
        subprocess.run(['gcc', '-shared', '-fPIC', '-nostdlib', str(c),
                        '-o', str(self.root / 'test.so')], check=True)

    def check(self):
        return subprocess.run(['python3', str(CHECK), str(self.root)],
                              capture_output=True, text=True)

    def test_unversioned_explicit_bzero_rejected(self):
        self.compile('extern void explicit_bzero(void*, unsigned long);\n'
                     'void erase(void *p) { explicit_bzero(p, 32); }')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('unversioned undefined symbol explicit_bzero', result.stderr)

    def test_engine_import_allowed(self):
        self.compile('extern void *GetCVarIF(void); void *probe(void) { return GetCVarIF(); }')
        self.assertEqual(self.check().returncode, 0)

    def test_arbitrary_weak_rejected(self):
        self.compile('extern void future_glibc(void) __attribute__((weak));\n'
                     'void probe(void) { if (future_glibc) future_glibc(); }')
        self.assertEqual(self.check().returncode, 1)

    def test_toolchain_hook_only_allowed_when_weak(self):
        for declaration, expected in [('__attribute__((weak))', 0), ('', 1)]:
            self.compile('extern void __gmon_start__(void) ' + declaration + ';\n'
                         'void probe(void) { if (__gmon_start__) __gmon_start__(); }')
            self.assertEqual(self.check().returncode, expected)

    def test_bad_elf_fails_closed(self):
        (self.root / 'broken').write_bytes(b'\x7fELFgarbage')
        self.assertEqual(self.check().returncode, 1)

    def test_no_elf_fails_closed(self):
        self.assertEqual(self.check().returncode, 1)


class Shim(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.pgsql = self.root / 'extensions/pgsql'
        self.pgsql.mkdir(parents=True)
        (self.root / 'product.version').write_text('1.13.0\n')
        (self.pgsql / 'AMBuilder').write_text('  SM.extensions += [builder.Add(binary)]\n')

    def patch(self):
        return subprocess.run(['python3', str(PATCH), str(self.root)], capture_output=True)

    def test_patch_idempotent_and_drift_rejected(self):
        self.assertEqual(self.patch().returncode, 0)
        self.assertEqual(self.patch().returncode, 0)
        (self.pgsql / 'css34_explicit_bzero.c').write_text('/* corrupt */')
        self.assertNotEqual(self.patch().returncode, 0)

    def test_anchor_drift_rejected(self):
        (self.pgsql / 'AMBuilder').write_text('changed upstream\n')
        self.assertNotEqual(self.patch().returncode, 0)

    def test_other_lines_untouched(self):
        for version in ['1.11.0', '1.12.0']:
            (self.root / 'product.version').write_text(version)
            self.assertEqual(self.patch().returncode, 0)
            self.assertFalse((self.pgsql / 'css34_explicit_bzero.c').exists())

    def test_optimized_shim_hidden_and_erases(self):
        self.assertEqual(self.patch().returncode, 0)
        source = self.pgsql / 'css34_explicit_bzero.c'
        library = self.root / 'shim.so'
        subprocess.run(['gcc', '-O3', '-flto', '-shared', '-fPIC', str(source),
                        '-o', str(library)], check=True)
        dynamic = subprocess.check_output(['nm', '-D', str(library)], text=True)
        self.assertNotIn('explicit_bzero', dynamic)
        # LTO can see the dead local password; the barrier must retain its erase.
        caller = self.root / 'caller.c'
        caller.write_text('extern void explicit_bzero(void*, unsigned long);\n'
                          'int main(void) { char password[32] = "secret";\n'
                          'explicit_bzero(password, sizeof password); return 0; }\n')
        executable = self.root / 'probe'
        subprocess.run(['gcc', '-O3', '-flto', str(source), str(caller), '-o', str(executable)],
                       check=True)
        assembly = subprocess.check_output(['objdump', '-d', '--disassemble=main',
                                             str(executable)], text=True)
        self.assertRegex(assembly, r'movaps|movups|memset|stos')
        subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    unittest.main()
