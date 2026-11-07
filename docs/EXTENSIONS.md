# Building SourceMod extensions for these packages

## One `.so` cannot serve SourceMod 1.12 and 1.13

SourceMod checks the API version an extension was compiled with
(`SMINTERFACE_EXTENSIONAPI_VERSION` in `public/IExtensionSys.h`, returned by
`GetExtensionVersion()`), so the version comes from the headers the extension was built
against, not from its source:

| Line | SourceMod | Extension API it loads | Built with older headers | Built with newer headers |
|------|-----------|------------------------|--------------------------|--------------------------|
| `sm11-oldstable` (frozen) | 1.11.0.6970 | up to 8 | loads | `too new to load` |
| `sm12-latest` | 1.12.0.7257 | up to 8 | loads | `too new to load` |
| `sm13-latest` | 1.13.0.7478 | **9 and 11** (10 is refused) | `Extension version is too old to load (8, max is 9)` | — |

SourceMod 1.13 raised the minimum to 9 (V9: SourcePawn API revamp) and builds at 11; its
`ExtensionSys.cpp` also refuses 10 explicitly. The wording "max is 9" in the 1.13 error is
upstream's; it is the minimum. So an extension built with SourceMod 1.12 or older headers does not load on
`sm13-latest`, and one rebuilt for 1.13 does not load on `sm12-latest` or `sm11-oldstable`:
ship one binary per line. `extension_api` / `extension_api_min` in `css34-package.json`,
`lines.json` and `VERSIONS.txt` give the range of each package.

ProtectCMDS, cssdm and navfile_blocker need builds against compatible 1.13 headers;
their older API 7/8 binaries are rejected by the loader.

## Third-party extensions running on `sm13-latest`

Builds for SourceMod 1.13 that run on the Danyas servers with `1.13.0.7478-mm1.12.0-r7` (2026-11-05). This repository
does not build or ship them.

| Extension | 1.13 build | Notes |
|---|---|---|
| ProtectCMDS | `css34.sm113` build of `fmu1337/ProtectCMDS` v1.1.4 (`protectcmds.css34.sm113.ext.so`) | the old 1.0.10 / v1.1.1 builds are API 7 |
| navfile_blocker | rebuilt from the original 2012 source with SM 1.13 headers | needs `-r5` or newer: earlier packages resolved `"library" "engine"` signatures to 0 ([PATCHES.md](PATCHES.md), `0004-gameconfigs-rtld-noload`) |
| CS:S DM | `fmu1337/sm34.cssdm` 2.1.6-git325 sm13 (`cssdm.ext.2.ep1.so`) | replaces both the `.1.ep1` and the `.2.ep1` builds of older trees |
| socket | `JoinedSenses/sm-ext-socket` (legacy Socket 3.x API: `SocketCreate`, `SocketConnect`, `SocketSend`, …) rebuilt with SM 1.13 `public/smsdk_ext.*` | see below |

**socket.** Many old v34 plugins need it: wS plugins, kigen-ac, MyArena vip. The rewrites by Accelerator74 and ProjectSky (libuv) offer only
the methodmap API, and plugins compiled against the old natives fail to load with them. The JoinedSenses source builds for
API 11 after two changes:

- replace `boost::thread`, `boost::mutex` and `boost::shared_mutex` (and their lock types) with C++17
  `std::thread`, `std::mutex` and `std::shared_mutex`;
- use asio header-only (boost 1.83 headers with `-DBOOST_ERROR_CODE_HEADER_ONLY -DBOOST_ASIO_NO_TS_EXECUTORS`).

Link with `-static-libstdc++ -static-libgcc -lpthread`. The build in use was made with an Ubuntu 24.04 cross
compiler and needs glibc 2.38 or newer. Built in the release image as in the recipe below, it gets the packages'
2.17 floor instead.

## Recipe

Build with the same trees and toolchain as the release, so the headers match the binary
you run. Verified on 2026-11-04 by building SourceMod's `public/sample_ext` this way and
loading it into `srcds` with the `sm13-latest` package.

1. The trees: SourceMod at the line's pinned commit with this repository's patch series
   applied, Metamod:Source 1.12, hl2sdk episode1 and AMBuild, all pinned in
   `builder/lines.json` / `builder/checkout-deps.sh`. One package build leaves them in
   `sourcemod/` and `deps/`:

   ```bash
   git clone https://github.com/fmu1337/sourcemod-css34 && cd sourcemod-css34
   git checkout <css34_pack_commit from the release's VERSIONS.txt>   # or master for the current pins
   CSS34_LINE=sm13-latest builder/docker/build.sh                      # sm12-latest for an API 8 build
   ```

2. Build the extension in the release image (CentOS 7 i686, glibc 2.17, GCC 10.2.1), so
   it runs on every distribution the packages run on:

   ```bash
   docker run --rm -it --platform linux/386 --entrypoint linux32 \
     -v "$PWD:/workspace:ro" -v /path/to/my_ext:/ext \
     quay.io/pypa/manylinux2014_i686@sha256:30305867f278896ee117b0d162a8e4f9b7b16819e6590f6139e14c5ed5b23fdd bash
   ```

   Inside the container:

   ```bash
   source /opt/rh/devtoolset-10/enable
   export PATH="/opt/python/cp311-cp311/bin:$HOME/.local/bin:$PATH"
   cp -r /workspace/deps/ambuild /tmp/ambuild
   python3 -m pip install --user --no-index --find-links /workspace/deps/wheels /tmp/ambuild
   cd /ext && mkdir -p build && cd build
   python3 ../configure.py --sm-path=/workspace/sourcemod --mms-path=/workspace/deps/mmsource-1.12 \
     --hl2sdk-root=/workspace/deps --hl2sdk-manifest-path=/workspace/sourcemod/hl2sdk-manifests \
     --sdks=episode1 --targets=x86 --enable-optimize
   ambuild
   ```

   This assumes the extension uses the `AMBuildScript` / `configure.py` of SourceMod's
   `public/sample_ext` (current SourceMod; copy them from `sourcemod/public/sample_ext` if
   the project has an older one). The result is `<name>.ext.2.ep1.so` for the episode1
   SDK (CS:S v34) and needs `tier0_i486.so` and `vstdlib_i486.so`, which srcds already has
   loaded. Without an SDK the result is `<name>.ext.so`.

3. Compiler and linker settings that build uses (from `sample_ext/AMBuildScript` and the
   episode1 manifest): `-m32 -msse -mfpmath=sse -fvisibility=hidden
   -fvisibility-inlines-hidden -fno-threadsafe-statics -std=c++17`, defines `LINUX _LINUX
   POSIX GNUC COMPILER_GCC SOURCE_ENGINE=1 SE_EPISODEONE=1 NO_HOOK_MALLOC
   NO_MALLOC_OVERRIDE`, `-static-libstdc++ -static-libgcc`, static `mathlib_i486.a` and
   `tier1_i486.a`, dynamic `tier0_i486.so` and `vstdlib_i486.so` from
   `deps/hl2sdk-episode1/linux_sdk/`. Also add `-fPIC` (`cxx.cflags += ['-fPIC']`): the
   stock sample compiles without it and `ld` warns `creating DT_TEXTREL`.

4. Check the binary before shipping it:

   ```bash
   readelf -d my.ext.2.ep1.so | grep NEEDED            # tier0_i486.so if it calls Msg/Warning/DevMsg
   nm -D --undefined-only my.ext.2.ep1.so               # nothing that srcds does not provide
   objdump -T my.ext.2.ep1.so | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1   # 2.17 or lower
   ```

   On the server, `sm exts info <name>` prints `Binary info: API version 11`.

## `undefined symbol: Msg`

`Msg`, `Warning`, `DevMsg` and `ConMsg` live in the game's `bin/tier0_i486.so`. srcds
loads tier0 as a dependency of the engine, not into the global symbol scope:
`dlsym(RTLD_DEFAULT, "Msg")` inside a running `srcds_i686` returns 0 with the `sm13-latest`
packages and with rom4s SourceMod 1.11.0.6572 + Metamod 1.10.6 alike, and `srcds_i686`
itself needs only `libm`, `libdl` and `libc`. A library loaded later finds `Msg` only
through its own `NEEDED` entry for `tier0_i486.so`. SourceMod never exported `Msg`, and
tier0 is the game's own file, so nothing about it changed with SourceMod 1.13: a binary
that loaded on 1.11 and called `Msg` was linked against tier0; the rebuild was not.

Shown with the same source file that calls `Msg()` in `SDK_OnLoad`, built twice:

```text
sm exts load msgsdk        # AMBuild, --sdks=episode1: NEEDED vstdlib_i486.so tier0_i486.so
css34 msgprobe: Msg() from tier0 works
[SM] Loaded extension msgsdk.ext.so successfully.
sm exts load msgnosdk      # g++ without the SDK: Msg undefined, no tier0 in NEEDED
[SM] Extension msgnosdk.ext.so failed to load: .../msgnosdk.ext.so: undefined symbol: Msg
```

So an extension that calls `Msg` must link tier0. Either build it as an SDK extension
(step 2: `--sdks=episode1`), or add `-L<hl2sdk-episode1>/linux_sdk -l:tier0_i486.so` to a
hand-written link line. No rpath is needed: the dynamic linker reuses the
`tier0_i486.so` srcds has already loaded. Or drop `Msg` and log through SourceMod
(`smutils->LogMessage(myself, ...)`, `smutils->LogError(myself, ...)`). A stub such as
`-DMsg=nb_Msg` only hides the messages.
