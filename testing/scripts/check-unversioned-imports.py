#!/usr/bin/env python3
"""Check every dynamic import of the shipped ELFs against the target ABI.

Unversioned imports must be in testing/unversioned-imports.txt. Versioned
imports must stay within the providers of the glibc 2.17 image and the
servers we support: GLIBC_ <= 2.17, GCC_ (libgcc_s) <= 4.2.0 (the highest
any shipped ELF uses today; raise it only after checking the oldest
supported server's libgcc_s), and GLIBCXX_ / CXXABI_ only in spcomp /
oldspcomp, which link libstdc++ dynamically (<= GCC 4.8.5's 3.4.19 / 1.3.7).
Any other version namespace fails.
"""
from pathlib import Path
import os
import re
import subprocess
import sys

ALLOWLIST = Path(__file__).resolve().parent.parent / 'unversioned-imports.txt'
SPCOMP = {'spcomp', 'oldspcomp'}
VERSIONED = re.compile(r'^(GLIBC|GCC|GLIBCXX|CXXABI)_([0-9]+(?:\.[0-9]+)*)$')


def limits():
    return {
        'GLIBC': os.environ.get('GLIBC_FLOOR', '2.17'),
        'GCC': os.environ.get('GCC_MAX', '4.2.0'),
        'GLIBCXX': os.environ.get('GLIBCXX_SPCOMP_MAX', '3.4.19'),
        'CXXABI': os.environ.get('CXXABI_SPCOMP_MAX', '1.3.7'),
    }


def vtuple(text):
    return tuple(int(part) for part in text.split('.'))


def versioned_problem(name, version, maxima):
    """None if symbol version `version` is allowed in ELF `name`, else why not."""
    match = VERSIONED.match(version)
    if not match:
        return 'unknown symbol version namespace'
    space, number = match.groups()
    if space in ('GLIBCXX', 'CXXABI') and name not in SPCOMP:
        return 'libstdc++ must be linked statically (only spcomp may import it)'
    if vtuple(number) > vtuple(maxima[space]):
        return '{}_{} > {}_{}'.format(space, number, space, maxima[space])
    return None


def check(root):
    allowed = {}
    for line in ALLOWLIST.read_text().splitlines():
        if line and not line.startswith('#'):
            symbol, provider = line.split()
            if symbol in allowed:
                raise ValueError('duplicate allowlist symbol: ' + symbol)
            allowed[symbol] = provider
    failed = False
    count = 0
    maxima = limits()
    for elf in sorted(Path(root).rglob('*')):
        if not elf.is_file():
            continue
        with elf.open('rb') as stream:
            if stream.read(4) != b'\x7fELF':
                continue
        count += 1
        result = subprocess.run(['nm', '-D', '--undefined-only', '--format=posix', str(elf)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                universal_newlines=True)
        if result.returncode:
            print('FAIL: cannot inspect {}: {}'.format(elf, result.stderr), file=sys.stderr)
            failed = True
            continue
        for row in result.stdout.splitlines():
            fields = row.split()
            if len(fields) < 2:
                raise ValueError('invalid nm output: ' + row)
            symbol, kind = fields[:2]
            if '@' in symbol:
                name, version = symbol.split('@', 1)
                problem = versioned_problem(elf.name, version.lstrip('@'), maxima)
                if problem:
                    print('FAIL: {}: imports {}: {}'.format(
                        elf.relative_to(root), symbol, problem), file=sys.stderr)
                    failed = True
                continue
            provider = allowed.get(symbol)
            # ELF permits unresolved weak instrumentation hooks, but never grant
            # the same exception to a strong import (or to arbitrary weak names).
            if provider and (provider != 'optional-weak-toolchain' or kind in ('w', 'v')):
                continue
            print('FAIL: {}: unversioned undefined symbol {} ({}) is not allowed by '
                  'the glibc 2.17 / libgcc_s / engine ABI'.format(
                      elf.relative_to(root), symbol, kind), file=sys.stderr)
            failed = True
    if count == 0:
        print('FAIL: no shipped ELF files inspected', file=sys.stderr)
        failed = True
    if not failed:
        print('OK: dynamic imports (unversioned and GLIBC/GCC/GLIBCXX/CXXABI) checked in {} ELF files'.format(count))
    return int(failed)


if __name__ == '__main__':
    sys.exit(check(sys.argv[1]))
