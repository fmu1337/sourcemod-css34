#!/usr/bin/env python3
"""Reject unversioned dynamic imports absent from the glibc 2.17 ABI contract."""
from pathlib import Path
import subprocess
import sys

ALLOWLIST = Path(__file__).resolve().parent.parent / 'unversioned-imports.txt'


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
        print('OK: unversioned dynamic imports checked in {} ELF files'.format(count))
    return int(failed)


if __name__ == '__main__':
    sys.exit(check(sys.argv[1]))
