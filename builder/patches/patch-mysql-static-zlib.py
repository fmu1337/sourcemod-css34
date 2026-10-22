#!/usr/bin/env python3
"""Embed zlib in the sm13 MariaDB extension; reject linker-anchor drift."""
from pathlib import Path
import sys

sm = Path(sys.argv[1])
if not (sm / 'product.version').read_text().strip().startswith('1.13.'):
    sys.exit(0)
path = sm / 'extensions/mysql/AMBuilder'
text = path.read_text()
old = "        '-lcrypto',\n        '-Wl,-Bdynamic',\n        '-lz',\n"
new = "        '-lcrypto',\n        '-lz',  # css34: embed pinned PIC zlib with the static TLS libraries\n        '-Wl,-Bdynamic',\n"
if text.count(new) == 1 and old not in text:
    pass
elif text.count(old) == 1 and new not in text:
    path.write_text(text.replace(old, new))
else:
    sys.exit('FAIL: sm13 MariaDB static zlib link anchor drift')
print('==> sm13 MariaDB links zlib statically')
