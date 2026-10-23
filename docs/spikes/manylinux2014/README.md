# Spike: manylinux2014 (glibc 2.17) and dual-core SM 1.11

**Reference material only. This branch is not for merging.** It is the evidence and starting point for ROADMAP tasks
T1.1–T1.4 (issues #80–#83) and T2.1–T2.3 (#88–#90). Port the ideas into proper builder code. Do not copy the env-var
hacks.

## What was proven (October 2026, container tests on a 6.18 host kernel)

| Build | Toolchain | Max GLIBC | Smoke PASSED on |
|---|---|---|---|
| SM 1.13.0.7472 + MM 1.12 git1226, real `-std=c++20` | manylinux2014_i686, devtoolset-10 GCC 10.2.1 | 2.17 | centos:7, ubuntu:14.04/16.04/18.04/24.04, debian:8/9/10/13 |
| SM 1.12.0.7253 + MM 1.12 git1226 | same | 2.17 | centos:7, ubuntu:24.04, debian:13 |
| SM 1.11.0.6970 + MM 1.10.7 git976 | same | 2.17 | centos:7, ubuntu:24.04, debian:13 (the published sm11 SIGABRTs here) |
| SM 1.11 dual-core (1.ep1 → MM 1.10.7, 2.ep1 → MM 1.12 git1227) | same | 2.17 | ubuntu:24.04 on both MM. Botplay: green on MM 1.12; on MM 1.10.7 one FAIL, `failed extension(s) in botplay sm exts list` (most likely DHooks 2.ep1 on the old MM; T2.4 must turn that into an expected SKIP) |

No step needed clang-9/10, the jessie gcc-4.9 sysroot, or the C++17 downgrade/`cxx17-compat` span polyfill.

## Key facts for the agents

- **Image:** `quay.io/pypa/manylinux2014_i686@sha256:30305867f278896ee117b0d162a8e4f9b7b16819e6590f6139e14c5ed5b23fdd`
  (CentOS 7.9 i686, glibc 2.17, `/opt/rh/devtoolset-10`, CPython in `/opt/python/cp3*/`).
- **OpenSSL:** CentOS 7 ships only static OpenSSL 1.0.2. Build 1.1.1w from source:
  `./Configure linux-elf no-shared no-tests no-dso -fPIC --prefix=/opt/ossl`, then point `CPATH` / `LIBRARY_PATH`
  at it for the MariaDB/MySQL connector.
- **GCC 10 warnings that break `-Werror`:**
  - `-Wno-format-truncation -Wno-stringop-truncation` (MM 1.12 metamod.cpp:852);
  - `-Wno-volatile` (C++20);
  - `-Wno-sign-compare` (SM 1.11).
- **Hide libstdc++:** every module needs `-static-libstdc++ -Wl,--exclude-libs=libstdc++.a:libsupc++.a`. logic.so and
  non-SDK extensions can use `--exclude-libs,ALL`. Cores, game extensions and `metamod.*.ep1` must keep their tier1
  exports (ConVar, `s_pConCommandBases`).
- **Root cause of the sm11 SIGABRT on new OSes:**
  - MM 1.10.7 loads libstdc++.so.6 dynamically, and SM 6970's logic.so exports ~2,500 symbols, std::locale among them,
    from its static libstdc++. Hiding the exports fixes it.
  - `testing/scripts/check-package.sh` currently *requires* the leak: its "logic exports ≥ 100" rule for SM < 1.13
    must go.
- **MM 1.10 `__GNUC__ == 4` checks** (`core-legacy/oslink.h`, `core-legacy/ISmmPlugin.h`, `core-legacy/sourcemm.cpp`)
  are true only for clang. Under GCC 10 they hide GetGameDllBridge/GetVspBridge and drop MM's operator new. That is why
  the builder pinned clang-9 for 1.11. Change them to `>= 4`.
- **The `gcc-9`/`g++-9` names are hardcoded** in the logic link path, and so are the Debian `libstdc++.a` paths. The
  spike used wrapper scripts; the real fix is to remove the hardcoding.
- **spcomp** built this way needs only GLIBCXX_3.4.19 and GLIBC_2.17, because devtoolset links
  `libstdc++_nonshared.a`.
- **Not covered:**
  - botplay was not run on the single-core manylinux builds;
  - old kernels (e.g. CentOS 7's 3.10) are untested;
  - `_GLIBCXX_USE_CXX11_ABI=0` is believed unnecessary but has not been tested without it.

## Files

- `oldos-builder.diff`: changes to master (as of 2026-10-13) used for the single-core builds. It is gated by spike-only
  env vars: `OLDOS_GNUC_FIX`, `CSS34_KEEP_CXX20`, `CSS34_EXCLUDE_LIBS_ALL`.
- `dual-core-builder.diff`: changes on top of `88713a7` for the dual-core SM 1.11 spike (Phase 2), including
  `builder/dual-mm-modern.sh`.
- `scripts/build-css34-ml2014-{cxx20,sm12,sm11}.sh`, `scripts/build-dual-ml2014.sh`: run inside the manylinux image with
  `/workspace` = repo copy and `/dl/openssl-1.1.1w.tar.gz`.
  - Lines mentioning `/proxy-ca.crt` and the `curl` wrapper are **sandbox-only** (a TLS-intercepting proxy). Drop them.
  - The `gcc-9`/`g++-9` wrappers are a hack that stands in for removing the hardcoded compiler names.
- `scripts/run-case-lite.sh`, `scripts/run-dual.sh`: how the smoke runs were driven (server tree + `testing/scripts/*`).
  The paths are from the spike sandbox.
- `scripts/elf-floor.sh <dir>`: prints, per ELF, the max GLIBC/GLIBCXX version, NEEDED libraries, the export count and
  the symbols above `$THR`.
- `results/*-floor.txt`:
  - our C++20 build (cxx20);
  - official AlliedModders drops (official): 6970 has floor 2.17, while 7255/7477 and MM 1227 have 2.29–2.30;
  - the v34 server binaries themselves (srv): ≤ GLIBC_2.3.2.
- `results/*-findings.json`: full research notes with the evidence. Paths in them point to the spike sandbox.
