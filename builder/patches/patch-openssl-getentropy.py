#!/usr/bin/env python3
"""Keep OpenSSL's Linux syscall/device entropy paths without a new libc import.

OpenSSL 3.5 (providers/implementations/rands/seeding/rand_unix.c,
syscall_random()) first probes libc's getentropy() through a weak reference
(glibc 2.25+), then falls back to the getrandom syscall and, in the caller,
to the random devices. A weak undefined getentropy is an unversioned import
the glibc 2.17 contract forbids, so on Linux only that libc probe is compiled
out; the syscall path, kernel-seeding checks and device fallback stay as
upstream wrote them. Every anchor must match exactly once: a drifted source
fails the build instead of shipping an unpatched or half-patched libcrypto.
"""
from pathlib import Path
import sys

SOURCE = 'providers/implementations/rands/seeding/rand_unix.c'
START = '    /*\n     * Do runtime detection to find getentropy().'
END = '    /* Linux supports this since version 3.17 */\n'
SYSCALL = ('#if defined(__linux) && defined(__NR_getrandom)\n'
           '    return syscall(__NR_getrandom, buf, buflen, 0);\n')
# The only getentropy() call left outside the probe (WASI/Emscripten).
WASI = ('#elif defined(__wasi__) || defined(__EMSCRIPTEN__)\n'
        '    if (getentropy(buf, buflen) == 0)\n')
WEAK = 'extern int getentropy(void *buffer, size_t length) __attribute__((weak));'
GUARD = '#if !defined(__linux) /* css34: Linux uses the getrandom syscall path below */\n'
GUARD_END = '#endif /* css34 Linux entropy */\n\n'


def fail(message):
    sys.exit('FAIL: OpenSSL entropy patch: ' + message)


def patched(text):
    """The source with the Linux guard applied; fails on any drift."""
    if text.count(START) != 1 or text.count(END) != 1:
        fail('getentropy block anchor drift')
    a, b = text.index(START), text.index(END)
    if a >= b:
        fail('getentropy block anchors out of order')
    block = text[a:b]
    if (block.count(WEAK) != 1 or block.count('DSO_global_lookup("getentropy")') != 1
            or not block.endswith('#endif /* !__DragonFly__ && !__NetBSD__ && !__FreeBSD__ */\n\n')):
        fail('getentropy probe drift')
    rest = text[b:]
    if not rest.startswith(END + SYSCALL) or text.count(SYSCALL) != 1:
        fail('Linux getrandom syscall path drift')
    outside = text[:a] + rest
    if outside.count('getentropy(') - outside.count('getentropy(2)') != 1 or outside.count(WASI) != 1:
        fail('unexpected getentropy() use outside the probe')
    return text[:a] + GUARD + block + GUARD_END + rest


def patch(root):
    path = Path(root) / SOURCE
    if not path.is_file():
        fail(SOURCE + ' not found (OpenSSL layout drift)')
    text = path.read_text()
    if GUARD in text or GUARD_END in text:
        # Already patched: it must be exactly our patch of a clean source.
        if text.count(GUARD) != 1 or text.count(GUARD_END) != 1:
            fail('inconsistent earlier patch')
        clean = text.replace(GUARD, '', 1).replace(GUARD_END, '', 1)
        if patched(clean) != text:
            fail('inconsistent earlier patch')
    else:
        path.write_text(patched(text))
    print('==> OpenSSL Linux entropy uses the getrandom syscall and the existing device fallback')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: patch-openssl-getentropy.py OPENSSL_SOURCE_DIR')
    patch(sys.argv[1])
