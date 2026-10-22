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
