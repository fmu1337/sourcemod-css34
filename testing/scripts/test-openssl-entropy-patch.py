#!/usr/bin/env python3
"""builder/patches/patch-openssl-getentropy.py on OpenSSL 3.5's syscall_random().

The fixture is that function as OpenSSL 3.5.9 ships it
(providers/implementations/rands/seeding/rand_unix.c). Needs GCC and binutils:
the patched function must compile on Linux with no getentropy reference while
keeping the getrandom syscall, and every kind of drift must fail closed.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / 'builder/patches/patch-openssl-getentropy.py'
SOURCE = 'providers/implementations/rands/seeding/rand_unix.c'

PRELUDE = '''#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <sys/types.h>
#include <sys/syscall.h>
#include <unistd.h>

'''

FIXTURE = r'''/*
 * syscall_random(): Try to get random data using a system call
 * returns the number of bytes returned in buf, or < 0 on error.
 */
ssize_t syscall_random(void *buf, size_t buflen)
{
    /*
     * Note: 'buflen' equals the size of the buffer which is used by the
     * get_entropy() callback of the RAND_DRBG. It is roughly bounded by
     *
     *   2 * RAND_POOL_FACTOR * (RAND_DRBG_STRENGTH / 8) = 2^14
     *
     * which is way below the OSSL_SSIZE_MAX limit. Therefore sign conversion
     * between size_t and ssize_t is safe even without a range check.
     */

    /*
     * Do runtime detection to find getentropy().
     *
     * Known OSs that should support this:
     * - Darwin since 16 (OSX 10.12, IOS 10.0).
     * - Solaris since 11.3
     * - OpenBSD since 5.6
     * - Linux since 3.17 with glibc 2.25
     *
     * Note: Sometimes getentropy() can be provided but not implemented
     * internally. So we need to check errno for ENOSYS
     */
#if !defined(__DragonFly__) && !defined(__NetBSD__) && !defined(__FreeBSD__)
#if defined(__GNUC__) && __GNUC__ >= 2 && defined(__ELF__) && !defined(__hpux)
    extern int getentropy(void *buffer, size_t length) __attribute__((weak));

    if (getentropy != NULL) {
        if (getentropy(buf, buflen) == 0)
            return (ssize_t)buflen;
        if (errno != ENOSYS)
            return -1;
    }
#elif defined(OPENSSL_APPLE_CRYPTO_RANDOM)

    if (CCRandomGenerateBytes(buf, buflen) == kCCSuccess)
        return (ssize_t)buflen;

    return -1;
#else
    union {
        void *p;
        int (*f)(void *buffer, size_t length);
    } p_getentropy;

    /*
     * We could cache the result of the lookup, but we normally don't
     * call this function often.
     */
    ERR_set_mark();
    p_getentropy.p = DSO_global_lookup("getentropy");
    ERR_pop_to_mark();
    if (p_getentropy.p != NULL)
        return p_getentropy.f(buf, buflen) == 0 ? (ssize_t)buflen : -1;
#endif
#endif /* !__DragonFly__ && !__NetBSD__ && !__FreeBSD__ */

    /* Linux supports this since version 3.17 */
#if defined(__linux) && defined(__NR_getrandom)
    return syscall(__NR_getrandom, buf, buflen, 0);
#elif (defined(__DragonFly__) && __DragonFly_version >= 500700) \
    || (defined(__NetBSD__) && __NetBSD_Version >= 1000000000)  \
    || (defined(__FreeBSD__) && __FreeBSD_version >= 1200061)
    return getrandom(buf, buflen, 0);
#elif (defined(__FreeBSD__) || defined(__NetBSD__)) && defined(KERN_ARND)
    return sysctl_random(buf, buflen);
#elif defined(__wasi__) || defined(__EMSCRIPTEN__)
    if (getentropy(buf, buflen) == 0)
        return (ssize_t)buflen;
    return -1;
#else
    errno = ENOSYS;
    return -1;
#endif
}
'''


class EntropyPatch(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.file = self.root / SOURCE
        self.file.parent.mkdir(parents=True)

    def write(self, text):
        self.file.write_text(PRELUDE + text)

    def patch(self):
        return subprocess.run(['python3', str(PATCHER), str(self.root)], capture_output=True, text=True)

    def symbols(self):
        obj = self.root / 'rand_unix.o'
        subprocess.run(['gcc', '-O2', '-c', str(self.file), '-o', str(obj)], check=True)
        return subprocess.run(['nm', str(obj)], capture_output=True, text=True, check=True).stdout

    def test_unpatched_fixture_has_the_weak_import(self):
        self.write(FIXTURE)
        self.assertRegex(self.symbols(), r'\bw getentropy\b')

    def test_patched_function_keeps_only_the_syscall(self):
        self.write(FIXTURE)
        result = self.patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        symbols = self.symbols()
        self.assertNotIn('getentropy', symbols)
        self.assertRegex(symbols, r'\bU syscall\b')
        text = self.file.read_text()
        self.assertIn('return syscall(__NR_getrandom, buf, buflen, 0);', text)
        # The non-Linux probe stays as upstream wrote it.
        self.assertEqual(text.count('extern int getentropy('), 1)

    def test_idempotent(self):
        self.write(FIXTURE)
        self.assertEqual(self.patch().returncode, 0)
        once = self.file.read_text()
        result = self.patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.file.read_text(), once)

    def assert_refused(self, text, message):
        self.write(text)
        before = self.file.read_text()
        result = self.patch()
        self.assertEqual(result.returncode, 1)
        self.assertIn(message, result.stderr)
        self.assertEqual(self.file.read_text(), before, 'a refused source must stay untouched')

    def test_missing_source_fails(self):
        result = self.patch()
        self.assertEqual(result.returncode, 1)
        self.assertIn('not found', result.stderr)

    def test_anchor_drift_fails(self):
        self.assert_refused(FIXTURE.replace('Do runtime detection to find getentropy().', 'Probe getentropy().'),
                            'anchor drift')
        self.assert_refused(FIXTURE.replace('/* Linux supports this since version 3.17 */', '/* Linux */'),
                            'anchor drift')

    def test_probe_drift_fails(self):
        self.assert_refused(FIXTURE.replace('__attribute__((weak))', '__attribute__((weak, visibility("hidden")))'),
                            'getentropy probe drift')

    def test_syscall_drift_fails(self):
        self.assert_refused(FIXTURE.replace('syscall(__NR_getrandom, buf, buflen, 0)',
                                            'syscall(__NR_getrandom, buf, buflen, GRND_NONBLOCK)'),
                            'syscall path drift')

    def test_new_getentropy_use_fails(self):
        self.assert_refused(FIXTURE.replace('    errno = ENOSYS;\n    return -1;\n#endif\n}',
                                            '    return getentropy(buf, buflen);\n#endif\n}'),
                            'outside the probe')

    def test_half_patched_source_fails(self):
        self.write(FIXTURE)
        self.assertEqual(self.patch().returncode, 0)
        text = self.file.read_text().replace('#endif /* css34 Linux entropy */\n\n', '', 1)
        self.file.write_text(text)
        result = self.patch()
        self.assertEqual(result.returncode, 1)
        self.assertIn('inconsistent earlier patch', result.stderr)


if __name__ == '__main__':
    unittest.main()
