#!/usr/bin/env python3
"""Host-side regression tests; require GCC and binutils, no game server."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / 'testing/scripts/check-unversioned-imports.py'
# The hidden explicit_bzero shim the sm13 series adds to dbi.pgsql.ext (T3.4).
PATCH = ROOT / 'builder/patches/series/sm13-latest/sourcemod/0002-glibc217-database-imports.patch'
SHIM = 'extensions/pgsql/css34_explicit_bzero.c'


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

    def test_weak_getentropy_still_rejected(self):
        self.compile('extern int getentropy(void*, unsigned long) __attribute__((weak));\n'
                     'int probe(void *p) { return getentropy ? getentropy(p, 32) : -1; }')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('unversioned undefined symbol getentropy', result.stderr)

    def test_toolchain_hook_only_allowed_when_weak(self):
        for declaration, expected in [('__attribute__((weak))', 0), ('', 1)]:
            self.compile('extern void __gmon_start__(void) ' + declaration + ';\n'
                         'void probe(void) { if (__gmon_start__) __gmon_start__(); }')
            self.assertEqual(self.check().returncode, expected)

    def versioned(self, name, version, elf='test.so'):
        """An ELF importing `name@version` from a stub provider library."""
        (self.root / 'stub.c').write_text('void ' + name + '(void) {}\n')
        (self.root / 'stub.map').write_text(version + ' { global: ' + name + '; local: *; };\n')
        libs = tempfile.TemporaryDirectory()
        self.addCleanup(libs.cleanup)
        provider = Path(libs.name)
        subprocess.run(['gcc', '-shared', '-fPIC', '-nostdlib', str(self.root / 'stub.c'),
                        '-Wl,--version-script=' + str(self.root / 'stub.map'),
                        '-Wl,-soname,libstub.so', '-o', str(provider / 'libstub.so')], check=True)
        (self.root / 'stub.c').unlink()
        (self.root / 'stub.map').unlink()
        c = self.root / 'test.c'
        c.write_text('extern void ' + name + '(void); void probe(void) { ' + name + '(); }\n')
        subprocess.run(['gcc', '-shared', '-fPIC', '-nostdlib', str(c), '-L' + str(provider),
                        '-lstub', '-o', str(self.root / elf)], check=True)
        c.unlink()

    def test_new_libgcc_version_rejected(self):
        # Only GLIBC_ was bounded: __divmoddi4@GCC_7.0.0 passed (#201).
        self.versioned('__divmoddi4', 'GCC_7.0.0')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('GCC_7.0.0 > GCC_4.2.0', result.stderr)

    def test_old_libgcc_version_allowed(self):
        self.versioned('_Unwind_GetIPInfo', 'GCC_4.2.0')
        self.assertEqual(self.check().returncode, 0, self.check().stderr)

    def test_libstdcxx_only_in_spcomp(self):
        self.versioned('_ZSt4cout', 'GLIBCXX_3.4')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('libstdc++ must be linked statically', result.stderr)
        (self.root / 'test.so').unlink()
        self.versioned('_ZSt4cout', 'GLIBCXX_3.4', elf='spcomp')
        self.assertEqual(self.check().returncode, 0)
        (self.root / 'spcomp').unlink()
        self.versioned('_ZSt4cout', 'GLIBCXX_3.4.30', elf='spcomp')
        self.assertEqual(self.check().returncode, 1)

    def test_unknown_version_namespace_rejected(self):
        self.versioned('ssl_thing', 'OPENSSL_3.0.0')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('unknown symbol version namespace', result.stderr)

    def test_bad_elf_fails_closed(self):
        (self.root / 'broken').write_bytes(b'\x7fELFgarbage')
        self.assertEqual(self.check().returncode, 1)

    def test_no_elf_fails_closed(self):
        self.assertEqual(self.check().returncode, 1)


def shim_source():
    """The new file css34_explicit_bzero.c, taken from the series patch."""
    text = PATCH.read_text()
    section = text.split('diff --git a/' + SHIM + ' b/' + SHIM + '\n', 1)[1]
    section = section.split('\ndiff --git ', 1)[0]
    body = section.split('\n@@ ', 1)[1].split('\n', 1)[1]
    return ''.join(line[1:] + '\n' for line in body.splitlines() if line.startswith('+'))


class Shim(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_series_adds_the_shim_to_pgsql_only(self):
        text = PATCH.read_text()
        self.assertIn('new file mode', text.split(SHIM, 1)[1][:200])
        pgsql = text.split('diff --git a/extensions/pgsql/AMBuilder', 1)[1].split('\ndiff --git ', 1)[0]
        self.assertIn('css34_explicit_bzero.c', pgsql)
        # SM 1.12's libpq does not import explicit_bzero: no shim there.
        for patch in (ROOT / 'builder/patches/series/sm12-latest').rglob('*.patch'):
            self.assertNotIn('css34_explicit_bzero', patch.read_text(), patch.name)

    def test_optimized_shim_hidden_and_erases(self):
        source = self.root / 'css34_explicit_bzero.c'
        source.write_text(shim_source())
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
