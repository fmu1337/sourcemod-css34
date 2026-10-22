#!/usr/bin/env python3
"""Keep OpenSSL's Linux syscall/device entropy paths without a new libc import."""
from pathlib import Path
import sys


def patch(root):
    path = Path(root) / 'crypto/rand/rand_unix.c'
    text = path.read_text()
    start = '    /*\n     * Do runtime detection to find getentropy().'
    end = '    /* Linux supports this since version 3.17 */'
    guard = '#  if !defined(__linux) /* css34: use the existing Linux syscall path */\n'
    if text.count(start) != 1 or text.count(end) != 1:
        sys.exit('FAIL: OpenSSL getentropy block anchor drift')
    a, b = text.index(start), text.index(end)
    block = text[a:b]
    if block.count('extern int getentropy(') != 1 or text.count('return syscall(__NR_getrandom, buf, buflen, 0);') != 1:
        sys.exit('FAIL: OpenSSL entropy implementation drift')
    if guard in text:
        if text.count(guard) != 1 or not text[:a].endswith(guard) or not block.endswith('#  endif /* css34 Linux entropy */\n\n'):
            sys.exit('FAIL: inconsistent OpenSSL entropy patch')
    else:
        text = text[:a] + guard + block + '#  endif /* css34 Linux entropy */\n\n' + text[b:]
        path.write_text(text)
    print('==> OpenSSL Linux entropy uses getrandom syscall and existing device fallback')


if __name__ == '__main__':
    patch(sys.argv[1])
