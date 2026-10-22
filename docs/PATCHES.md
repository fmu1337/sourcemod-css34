# Compatibility patch inventory

## sm13 PostgreSQL explicit_bzero (temporary)

`builder/patches/apply-sourcemod-v112.sh` invokes
`patch-pgsql-explicit-bzero.py` only for SourceMod 1.13, adding a Linux C source
only to `dbi.pgsql.ext`. The vendored `libpq.a` imports `explicit_bzero`, which
is absent from glibc 2.17 and otherwise remains an unversioned undefined import.
The hidden definition uses `memset` followed by a compiler memory barrier so
password erasure survives dead-store elimination and cannot interpose on libc
or other extensions. Missing or inconsistent patch anchors fail the build.

Remove this patch when libpq is built from source in manylinux2014; PostgreSQL
already provides `src/port/explicit_bzero.c` for platforms without the function.

## Unversioned import contract

`testing/unversioned-imports.txt` lists exact symbol names and providers. System
providers were inspected from the pinned manylinux2014 i686 image in
`builder/docker/build.sh` (glibc 2.17 / libgcc_s). Engine providers were inspected
from CS:S v34 build 4044 `bin/{engine_i486,engine_i686,tier0_i486,vstdlib_i486}.so`.
Only observed imports are listed, rather than admitting every engine export.
New imports require verification against those providers, never the host libc.
Optional GCC instrumentation hooks are permitted only for weak undefined imports;
strong references to those names still fail. Unknown weak imports also fail.
Both SourceMod and Metamod package checks inspect every shipped ELF, including
executables, using `nm -D --undefined-only`; inspection errors fail closed.

## sm13 MySQL dependencies

The strict import check also found `compress2`, `uncompress` and weak
`getentropy` in sm13's MariaDB extension. The builder compiles checksum-pinned
zlib 1.3.1 with PIC and runs its tests; `patch-mysql-static-zlib.py` moves zlib
inside the extension's existing static-library link group. Compression therefore
has no unversioned imports or new runtime dependency.

OpenSSL 1.1.1w normally probes libc's `getentropy` through a weak symbol (glibc
2.25+), then uses its Linux `getrandom` syscall path and existing random-device
fallback. `patch-openssl-getentropy.py` omits only that libc probe on Linux.
The upstream syscall path, kernel-seeding checks and device fallback remain
intact. The build runs `openssl rand` to verify entropy acquisition and changes
the build stamp so cached, unpatched libcrypto archives cannot be reused.
Both patchers fail on missing or inconsistent anchors. No new unsupported libc
symbol is allowlisted. Revisit the OpenSSL patch when replacing OpenSSL 1.1.1w.
