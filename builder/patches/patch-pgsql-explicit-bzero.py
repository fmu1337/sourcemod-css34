#!/usr/bin/env python3
"""Temporary sm13 libpq compatibility patch; reject upstream anchor drift."""
from pathlib import Path
import sys

sm = Path(sys.argv[1])
version = (sm / 'product.version').read_text().strip()
if not version.startswith('1.13.'):
    sys.exit(0)

path = sm / 'extensions/pgsql/AMBuilder'
text = path.read_text()
anchor = '  SM.extensions += [builder.Add(binary)]\n'
addition = """  # css34: temporary glibc 2.17 explicit_bzero for vendored libpq.
  if compiler.target.platform == 'linux':
    binary.sources += ['css34_explicit_bzero.c']
"""
source = """/* Temporary until libpq is built from source in manylinux2014.
 * PostgreSQL provides src/port/explicit_bzero.c for that build.
 * Hidden: never interpose on the host libc or another extension.
 */
#include <string.h>

__attribute__((visibility("hidden")))
void explicit_bzero(void *buf, size_t len)
{
    memset(buf, 0, len);
    /* Prevent dead-store elimination of password erasure. */
    __asm__ __volatile__("" : : "r"(buf) : "memory");
}
"""
target = path.parent / 'css34_explicit_bzero.c'
if text.count(anchor) != 1:
    sys.exit('FAIL: pgsql AMBuilder Add(binary) anchor drift')
if addition in text:
    if text.count(addition) != 1 or not target.exists() or target.read_text() != source:
        sys.exit('FAIL: inconsistent explicit_bzero patch')
else:
    if 'css34_explicit_bzero' in text or target.exists():
        sys.exit('FAIL: unexpected partial explicit_bzero patch')
    path.write_text(text.replace(anchor, addition + anchor))
    target.write_text(source)
print('==> sm13 pgsql hidden explicit_bzero shim verified')
