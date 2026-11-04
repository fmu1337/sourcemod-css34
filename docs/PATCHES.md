# Compatibility patch inventory

## sm13-latest patch series (T3.4)

`builder/patches/series/sm13-latest/` is how sm13-latest is patched
(`apply-sourcemod.sh` applies the line's series with `apply-series.sh`; a line
without one fails). `series.json` names SourceMod `b34de51b` (1.13.0.7478) and the
tree each repository must have after `git apply --index`; the build fails on any
other result. The series was generated from the former scripted patcher
(`apply-sourcemod-v112.sh`, removed at the end of T3.4) on a clean
checkout with each file's original line endings kept (the old patcher rewrote
every source file to LF), and a full build from it matches the scripted build's
files, exports, `NEEDED` and `SONAME` (`compare-package-abi.py`).

| Patch | What | Why (failure without it) |
|-------|------|--------------------------|
| `sourcemod/0001-build-episode1-toolchain` | `AMBuildScript`: episode1 links static `tier1_i486.a` before `vstdlib`; `-lpthread -lrt -lgcc_s` kept `NEEDED`; link through the C++ driver; GCC 10 warning flags; `-static-libstdc++` with hidden symbols; dynamic `libgcc_s`. `core/logic/AMBuilder`: host static libstdc++, static SourcePawn before it, `--exclude-libs,ALL` + version script, css34 ABI defines. | ConVars imported from `vstdlib` instead of embedded (console commands break); pthread/rt missing on glibc 2.17; `ld` rejects driver flags; `-Werror` stops the build; `logic.so` exports `std::`/`__cxxabiv1` (srcds hang, `check-package.sh` fails). |
| `sourcemod/0002-glibc217-database-imports` | `pgsql`: hidden `explicit_bzero`; `mysql`: zlib inside the static link group. | Unversioned `explicit_bzero` / `compress2` / `uncompress` imports; see the sections below. |
| `sourcemod/0003-cstrike-episode1` | Build `game.cstrike` for episode1, extend its `SE_CSS` guards to `SE_EPISODEONE`, `FindDataMapInfo` in `GetPlayerVarAddressOrError`. | No cstrike extension on CS:S v34; EP1 `FindInDataMap` returns an incomplete `typedescription_t`. |
| `sourcemod/0004-gameconfigs-rtld-noload` | `CacheGameBinaryInfo` / `@`-signatures open already-mapped modules with `RTLD_NOLOAD`. On Linux a library's address is its own `CreateInterface` only if `dladdr` puts it in that module, else the module's `_DYNAMIC` (`link_map::l_ld`); when the `GAMEBIN` / `EXECUTABLE_PATH` search finds no mapped module, the module mapped as `<name>_i486.so`, `_i686.so` or `_amd.so` (`dl_iterate_phdr`). | `dlopen(engine_i486.so)` + `dlclose` leaves dangling ConVars in `vstdlib` (srcds loads `engine_i686.so`). CS:S v34 `engine_*.so` exports no `CreateInterface`, and `dlsym(handle)` also searches the module's dependencies, so SM 1.12+ took a dependency's `CreateInterface` and looked every `"library" "engine"` signature (`@sv`, `Cmd_ExecuteString`, navfile_blocker's `OnResourcePrecachedFullPath`) up in that library: 0, native x86 as well. SM 1.11 used the engine factory (`css34_gamedata_probe` in botplay). |
| `sourcemod/0005-sourcemm-api-safe-iface` | `GET_V_IFACE_*` check the factory for NULL before `VInterfaceMatch` and report which interface is missing. | A NULL factory on CS:S v34 dereferenced at load instead of a load error. |
| `sourcemod/0006-gcc10-warnings` | curl `-Wno-stringop-truncation`; `MIN()` replaced in two units. | `-Werror` build failures with GCC 10. |
| `sourcemod/0007-css34-versioning` | Build number from `SOURCEMOD_GIT_REV` (lines.json), detached/submodule HEAD in `Versioning`, `CSS34 pack:` line in `sm version`. | Shallow clones give a wrong build number; smoke checks the pack commit. |
| `sourcemod/0008-dbi-connect-options` | New interface `IDBConnectOptions` (`public/IDBConnectOptions.h`): core keeps every key of a `databases.cfg` entry and of `SQL_ConnectCustom`'s KeyValues (bridge hook `GetKeyValuesPairs`, `SM_LOGIC_MAGIC` changed) and a driver reads them by the `DatabaseInfo` pointer it received. `DatabaseInfo` and the existing DBI interfaces are unchanged. | Core passes only driver/host/database/user/pass/port/timeout/schema to a driver; `ssl_mode` / `ssl_ca` never reach it. Section "sm13 MySQL TLS options" below. |
| `sourcemod/0009-mysql-tls-options` | `dbi.mysql.ext`: `ssl_mode` / `ssl_ca` (keys and values of fmu1337/sm-dbi-mysql; default `disabled`, as stock SourceMod) mapped onto MariaDB Connector/C, TLS 1.2/1.3 with OpenSSL, `utf8mb4` in the handshake; unknown modes and verify modes without a readable CA fail the connect; persistent connections are shared only with equal TLS settings. | Upstream turns certificate verification off and requests no TLS: plaintext to every server, a `REQUIRE SSL` account (HeatWave's usual setup) is refused. |
| `sourcemod/0010-handlesys-lazy-table` | `HandleSystem` allocates its 2^20-entry table with `calloc` instead of `new[]` + `memset` (and frees it with `free`). Limit and handle encoding unchanged. | Upstream `cab60f73` (1.11.0.6792, "Bump handle limit to 1MB") zeroes ~64 MB at startup, all of it resident: srcds RSS 156 MB with stock plugins vs 82 MB on rom4s 1.11.0.6572; 90 MB with the patch (README "Memory use"). |
| `sourcepawn/0001-gcc10-link-flags` | `-Wno-sign-compare`; pthread/rt/`-lgcc_s` `NEEDED`. | GCC 10 sign-compare errors in the JIT/compiler; missing `NEEDED` on glibc 2.17. |
| `hl2sdk-manifests/0001-episode1-defines` | episode1 Linux defines `NO_HOOK_MALLOC`, `NO_MALLOC_OVERRIDE`. | The SDK's malloc hooks/overrides in SourceMod modules on CS:S v34. |
| `hl2sdk-manifests/0002-compiler-flag-guard` | Drop manifest compiler flags GCC 10 does not know (formerly `manifest_flag_guard.py`). | Unknown-flag errors from newer manifests (hl2sdk-manifests `ebd6e10`). |

## sm12-latest patch series

`builder/patches/series/sm12-latest/` is made the same way for SourceMod `e68dada2`
(1.12.0.7257) and patches sm12-latest. Its patches are the
sm13 ones above except:

- no `glibc217-database-imports`: SM 1.12's database extensions need neither shim;
- no `dbi-connect-options` / `mysql-tls-options`: SM 1.12 links the MySQL 5.6.15
  client with bundled yaSSL (TLS 1.0/1.1 only, no `caching_sha2_password`), which
  cannot log in to MySQL 8.4 / HeatWave at all. Use sm13 for those servers;
  sm12 ignores `ssl_mode` / `ssl_ca` like stock SourceMod;
- `sourcemod/0007-sdktools-onmapend-list`: `EntityOutputManager::OnMapEnd` uses
  `SourceHook::List<omg_hooks *>`, the type `OutputHookList` stores (section
  "SM 1.12: entity-output map-end cleanup list type" below);
- `sourcepawn/0001-gcc10-link-flags` also fixes a sign-compare in `vm/shell/shell.cpp`;
- `sourcemod/0008-handlesys-lazy-table` is sm13's `0010-handlesys-lazy-table` (SM 1.12 has the same
  2^20-entry table: RSS 147 MB with stock plugins on `1.12.0.7257-mm1.12.0-r4`).

A full build from the series matches the scripted build's files, exports, `NEEDED`
and `SONAME`.

## Metamod 1.12 patch series (MM_112)

`builder/patches/series/MM_112/` (`"root": "metamod"`) is keyed by the Metamod pin
rather than a line: every line that builds `MM_112_COMMIT` (`cb477558`, 1.12.0
git1228) uses it. `checkout-deps.sh` fetches the pin with `fetch-sourcemod.sh`
(exact tree, LF as committed), applies the series whose `commit` matches, then
`apply-mmsource-oldbridge.sh modern` (the legacy-plugin bridge stays a script: it
is our own code, kept once in `builder/patches/mm-oldbridge/`). `build-metamod.sh`
no longer patches MM 1.12. A full build from the series matches the scripted
build's files, exports, `NEEDED` and `SONAME`.

| Patch | What | Why (failure without it) |
|-------|------|--------------------------|
| `metamod/0001-build-episode1-toolchain` | `AMBuildScript`: episode1 `tier1_i486.a` before `vstdlib`; pthread/rt/`gcc_s` `NEEDED`; link through the C++ driver; GCC 10 flags; hidden static libstdc++. | As SourceMod's `0001`: ConVars from `vstdlib`, missing `NEEDED` on glibc 2.17, `-Werror`, exported `std::` symbols. |
| `metamod/0002-episode1-mem-h` | `provider_ep2.cpp` includes `tier0/mem.h`. | `MemAllocScratch` undeclared on episode1. |
| `metamod/0003-css34-versioning` | Build number from lines.json (`generate_headers.py`), `CSS34 pack:` line in `meta version`. | A `--depth` clone gives a wrong build number; smoke checks the pack commit. |
| `hl2sdk-manifests/0001-episode1-defines`, `0002-compiler-flag-guard` | As in SourceMod, for Metamod's own manifests (`4304a88`). | As in SourceMod. |

## Refreshing a series

After a pin bump in `builder/lines.json`: `builder/scripts/patch-series.sh
refresh <line>` (or `refresh MM_112` after an MM pin bump) rebases the series
(`git apply --3way`) and rewrites `series.json`; it reads the pin from
`lines.json` itself, because `lines.py gen` and `check` fail until it has run.
Then run `python3 builder/lines.py gen`. `builder/scripts/upstream-bump.py`
(T4.4) does all of this for the weekly bump PRs.
`builder/scripts/patch-series.sh check <series>` applies the series to a fresh
checkout of the pin. Before a bump, `builder/scripts/check-patch-drift.sh
--sm-commit <rev> --line <line>` (or `--range old..new`, `--mm-commit`) dry-runs
the series on the candidate with `git apply --3way` and names the first patch
that no longer applies; `--check-pins` checks every series on its own pin and
the MM 1.10 bridge patcher on the bridge pin.

## sm13 PostgreSQL explicit_bzero (temporary)

The sm13 series (`sourcemod/0002-glibc217-database-imports`) adds a Linux C
source, `css34_explicit_bzero.c`, only to `dbi.pgsql.ext`; sm12 has no such patch. The vendored `libpq.a` imports `explicit_bzero`, which
is absent from glibc 2.17 and otherwise remains an unversioned undefined import.
The hidden definition uses `memset` followed by a compiler memory barrier so
password erasure survives dead-store elimination and cannot interpose on libc
or other extensions (`test-glibc-imports.py` compiles the shim from the series).
A patch that does not apply fails the build.

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
zlib 1.3.1 with PIC and runs its tests; the same sm13 series patch moves zlib
inside the extension's existing static-library link group. Compression therefore
has no unversioned imports or new runtime dependency.

### OpenSSL 3.5 LTS and the MariaDB connector (T4.5)

Only sm13's Linux `dbi.mysql.ext` links our OpenSSL: sm12's MySQL 5.6.15 client
bundles yaSSL, the vendored `libpq` is built without SSL, and the Windows
MariaDB connector (AlliedModders' `v3.4.9-sm.5` zip) uses Schannel. The builder
compiles OpenSSL 3.5.9 (LTS; `linux-elf no-shared no-tests no-dso -fPIC`) only
for lines whose `configure.py` takes `--mariadb-path`. Its `Configure`
(`IPC::Cmd`) and Makefile template (`Time::Piece`) need perl modules CentOS 7
ships outside the image's perl: nine CentOS 7.9 i386 RPMs that match its
`perl-5.16.3-299.el7_9` (sha256-pinned from vault.centos.org, signed by the
CentOS 7 key) are unpacked under `deps/build-perl` and reach only the OpenSSL
build through `PERL5LIB`. Nothing is installed into the image, and a different
image perl fails the build.

AlliedModders' Linux connector archive is compiled against Debian 11's OpenSSL
1.1.1 headers. Linked with OpenSSL 3 it leaves `EVP_PKEY_size` and
`SSL_get_peer_certificate` undefined (macros in 3.x) and passes a 32-bit
`SSL_CTX_set_options` argument where 3.x takes `uint64_t`. The builder therefore
compiles the same Connector/C 3.4.9 source from MariaDB's signed tarball
(identical to the `v3.4.9` tag behind `v3.4.9-sm.5`). It uses that release's
CMake options, adds PIC, and builds against the static OpenSSL and zlib in
this image. The configure step fails unless CMake found `deps/openssl`. The
static plugins are unchanged: native password, caching_sha2, zlib and
pvio_socket.

OpenSSL 3.5's `syscall_random()` still probes libc's `getentropy` through a weak
symbol (glibc 2.25+) before its Linux `getrandom` syscall path; the random-device
fallback follows in the caller. `patch-openssl-getentropy.py` compiles out only
that libc probe on Linux. The upstream syscall path, kernel-seeding checks and
device fallback remain intact. The patcher fails closed on missing or
inconsistent anchors, a changed syscall line, or any other `getentropy()` call.
The build runs `openssl rand`, fails if `libcrypto.a`/`libssl.a` still mention
`getentropy`, and versions its stamps by OpenSSL release, so cached 1.1.1w or
unpatched archives are rebuilt. `testing/scripts/test-openssl-entropy-patch.py`
compiles the patched function and covers each refusal. No new libc symbol is
allowlisted: any OpenSSL symbol the connector misses would be an unversioned
undefined import, which `check-package.sh` rejects.

Upstream SourceMod 1.13's MySQL driver never asks for TLS: `MyDriver.cpp` turns
server certificate verification off and sets no TLS option. The sm13 series
adds TLS on request (next section). The CI probe
(`testing/scripts/mysql-tls-test.sh`, every smoke image) runs against MariaDB
11.8, MySQL 8.4 and MySQL 8.4 without TLS (`mysql-tls-server.sh`, digests in
`lines.json`). `css34_mysql_tls_probe` is linked from the extension's own
archives and link group (`testing/tools/mysql-tls-probe.c`,
`packages/test-plugins`, never released): verified TLS (CA and host name) to a
`REQUIRE SSL` MariaDB account must succeed, client and server must report the
same TLS version and cipher, and the TLS library must be the OpenSSL the build
compiled against; a plaintext login must be refused, and so must an unrelated
CA. `css34_mysql_probe.sp` then exercises every `ssl_mode` through
`dbi.mysql.ext` inside srcds (cases in `testing/README.md`).

## sm13 MySQL TLS options (ssl_mode / ssl_ca)

Patches `0008-dbi-connect-options` and `0009-mysql-tls-options` let a
`databases.cfg` entry (or `SQL_ConnectCustom` KeyValues) ask `dbi.mysql.ext` for
TLS, so Oracle MySQL HeatWave and MySQL 8.4+ (`caching_sha2_password`, `REQUIRE
SSL` accounts) work without a custom extension or ProxySQL. Usage and an example
are in the README section "Connecting to MySQL HeatWave / MySQL 8.4".

| Key | Values | Default |
|-----|--------|---------|
| `ssl_mode` | `disabled`, `preferred`, `required`, `verify_ca`, `verify_identity` (ASCII case-insensitive) | `disabled` (also for an empty value): stock SourceMod behaviour |
| `ssl_ca` | CA certificate (PEM), relative to `addons/sourcemod/` unless absolute; read by `verify_ca` / `verify_identity` only | none |

The keys and values are those of fmu1337/sm-dbi-mysql, so an entry with an
explicit `ssl_mode` written for that drop-in driver keeps working. Differences:
the default is `disabled` (sm-dbi-mysql: `preferred`), so an entry that relied on
that default must add `"ssl_mode" "preferred"` or stricter; for HeatWave
(`REQUIRE SSL`, `caching_sha2_password`) use `required` at minimum and
`verify_ca` with the DB system's CA file. An unknown `ssl_mode` fails the
connect (`[0]: ssl_mode "..." is not one of ...`; sm-dbi-mysql falls back to
`preferred`); `verify_ca` / `verify_identity`
without `ssl_ca`, or with a file that cannot be opened, fail the connect (sm-dbi-
mysql falls back to OpenSSL's built-in CA path); `verify_ca` really skips the
host-name check (sm-dbi-mysql checks it in both verify modes, so `verify_ca` to
an IP address only works here); entries are matched exactly, by the entry the
plugin named, not by host+user+database(+port).

How each mode maps onto MariaDB Connector/C 3.4.9 (`MySsl_Apply` in
`MyDriver.cpp`), which has no ssl-mode option of its own:

| `ssl_mode` | Connector/C options | Server without TLS | Certificate |
|------------|---------------------|--------------------|-------------|
| `disabled` (default) | verification off, no TLS requested (upstream's setting) | plaintext | — |
| `preferred` | `MYSQL_OPT_SSL_ENFORCE`, verification off | plaintext (falls back) | not checked |
| `required` | enforce, verification on, a callback that accepts any certificate | refused before login, `[2026]` | not checked |
| `verify_ca` | enforce, verification on, `MYSQL_OPT_SSL_CA`, the library's check without `MARIADB_TLS_VERIFY_HOST` | refused before login | chain to `ssl_ca`, expiry |
| `verify_identity` | enforce, verification on, `MYSQL_OPT_SSL_CA`, the library's own check | refused before login | chain, expiry, host name (DNS SAN / IP) |

`preferred` therefore encrypts whenever the server offers TLS but does not
authenticate the server: it protects against passive eavesdropping, not an
active man in the middle, and it falls back to plaintext when the server offers
no TLS. Use `verify_identity` (or `verify_ca` when connecting by an address the
certificate does not name) where that matters. With OpenSSL (Linux) the protocol is pinned to
TLS 1.2/1.3 (`MARIADB_OPT_TLS_VERSION`); `required` and the verify modes also
check after login that the session is encrypted. All options are copied by the
connector's automatic reconnect, so a reconnect cannot downgrade either. The
handshake asks for `utf8mb4` (the connector's default, now explicit); plugins
may still call `SQL_SetCharset`. A persistent connection is shared only between
configurations with the same mode and CA.

`required` needs the connector's TLS verification status cleared, which only
`MARIADB_TLS` (`ma_tls.h`, not installable without `ma_hash.h`) reaches: the
patch mirrors its two leading members and refuses to compile against any
Connector/C other than 3.4.9 (`MARIADB_PACKAGE_VERSION_ID`), so a connector bump
must re-check them; at run time the callback also checks the back pointers and
fails closed. `verify_ca` calls the library's `ma_pvio_tls_verify_server_cert`
(declared in the installed `ma_tls.h`, present in both the Linux and the
Windows archive).

Design: `DatabaseInfo` is part of the DBI ABI (third-party drivers and
extensions build it), so it does not grow. Core instead keeps all keys of each
configuration and registers `IDBConnectOptions` (version 1) next to `IDBI`;
`dbi.mysql.ext` requests it in `SDK_OnLoad` and logs an error if the core has
none (stock core: every connection then uses `disabled`, no TLS, whatever the
entry says). The registry maps the
`DatabaseInfo` pointer core hands to `IDBDriver::Connect` to its configuration:
`databases.cfg` entries for their lifetime (refcounted, so a pending threaded
connect keeps its entry across `sm_reload_databases`), `SQL_ConnectCustom`
KeyValues for the duration of the call. This covers `SQL_Connect`,
`SQL_TConnect`, `Database.Connect`, `IDBManager::Connect` and extensions that
call `FindDatabaseConf` (clientprefs). `SQL_ConnectEx` and a `DatabaseInfo` an
extension builds itself have no keys and use `disabled`. Re-parsing
`databases.cfg` inside the extension (sm-dbi-mysql's approach) was not needed:
it could not see `SQL_ConnectCustom` and matches entries only heuristically.

Windows: the same patch builds against AlliedModders' Schannel connector
(`v3.4.9-sm.5`). The modes map the same way; Schannel reads `ssl_ca` (PEM) and
honours the verification flags, the protocol set is the system's (TLS 1.3 only
on Windows 11 / Server 2022). Windows TLS is not exercised by CI (the Wine smoke
has no database).

Failure without the patches: no TLS from srcds at all; MySQL 8.4 / HeatWave
`REQUIRE SSL` accounts refuse SourceMod (`[1045]`), and other accounts log in
in plaintext.

## SM 1.12: entity-output map-end cleanup list type

- Introduced by css34 commit `bc2d291` (PR #126, T1.5 / #84).
- Implementation: `builder/patches/series/sm12-latest/sourcemod/0007-sdktools-onmapend-list.patch`
  (generated from the `PYOUT` block of the former `apply-sourcemod-v112.sh`).
- Upstream: SourceMod #2589, cherry-picked as `e68dada2979eb3093d81d2e3766f741e7d431e4a`
  (SM 1.12.0.7257).
- Change: use `SourceHook::List<omg_hooks *>` in
  `EntityOutputManager::OnMapEnd`, matching the list stored in `OutputHookList`.
- Evidence without patch: GCC 10 fails with `'list' is not a member of 'std'`.
  Adding `<list>` alone would leave the cleanup interpreting a SourceHook list
  as a different container type. SM 1.13 already uses `std::list` consistently
  and is not rewritten.
- Drift policy: fail on missing/changed map-end anchors, unknown storage types,
  or malformed already-patched code; validate the consistent SM 1.13 layout.
- Validation: checker fixtures plus runtime entity-output probe across map
  changes; manylinux GCC 10 build and PR CI remain required.
- Upstream report candidate for **#101 / T3.6**: the 1.12-dev cherry-pick uses
  the wrong container type. Report against that branch with the compiler error
  and storage-type mismatch, rather than proposing a change to 1.13.
