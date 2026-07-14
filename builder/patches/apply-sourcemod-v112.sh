#!/usr/bin/env bash
# CS:S v34 compatibility for SourceMod 1.12+ (hl2sdk-manifests / AMBuild 2.2).
# Pairs with Metamod:Source 1.12 (PLAPI 16 / modern Core / metamod.2.ep1).
# Primary binary: sourcemod.2.ep1.so (SE_EPISODEONE / gamesuffix 2.ep1).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

sourcemod_dir="${1:?sourcemod directory required}"
builder_dir="$(cd "$script_dir/.." && pwd)"

echo "==> Applying SourceMod 1.12+ css34 patches (Metamod 1.12 / 2.ep1)"

# --- manifests ---
manifests_dir="$sourcemod_dir/hl2sdk-manifests/manifests"
if [ ! -d "$manifests_dir" ]; then
  echo "hl2sdk-manifests missing; is this SourceMod 1.12+?" >&2
  exit 1
fi

# Ensure episode1 linux defines match css34 (ABI0 + no HL2 malloc hooks).
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYMAN'
from pathlib import Path
import json, os
man = Path(os.environ['SOURCEMOD_DIR']) / 'hl2sdk-manifests/manifests/episode1.json'
data = json.loads(man.read_text())
linux = data.setdefault('linux', {})
defs = linux.setdefault('defines', [])
changed = False
for d in ('NO_HOOK_MALLOC', 'NO_MALLOC_OVERRIDE', '_GLIBCXX_USE_CXX11_ABI=0'):
    if d not in defs:
        defs.append(d)
        changed = True
if changed:
    man.write_text(json.dumps(data, indent=4) + '\n')
    print('==> Patched SM episode1.json linux defines for css34')
else:
    print('==> SM episode1.json linux defines already ok')
PYMAN

# --- AMBuildScript / SdkHelpers (1.12 structure) ---
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

sm = Path(os.environ['SOURCEMOD_DIR'])
ambuild = sm / 'AMBuildScript'
text = ambuild.read_text()

# css34: for episode1 (and optional ep1) embed ConVar from static tier1 before
# shared vstdlib, and record pthread/rt DT_NEEDED on older glibc.
needle = "    SdkHelpers.configureCxx(context, binary, sdk)\n\n    return binary"
insert = """    SdkHelpers.configureCxx(context, binary, sdk)

    # css34: episode1 -> sourcemod.2.ep1.so (Metamod 1.12); optional ep1 -> 1.ep1
    if sdk.get('name') in ('ep1', 'episode1'):
      if sdk.get('name') == 'ep1':
        compiler.defines += ['SM_CSS34_GAMEFIX_1_EP1']
      # Static tier1 BEFORE shared vstdlib so ConVar is embedded, not imported.
      if compiler.target.platform == 'linux':
        tier1 = os.path.join(sdk['path'], 'linux_sdk', 'tier1_i486.a')
        if os.path.isfile(tier1):
          compiler.linkflags[0:0] = [tier1]
        for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s'):
          if flag not in compiler.linkflags:
            compiler.linkflags += [flag]

    return binary"""
if 'css34: episode1 -> sourcemod.2.ep1.so' not in text and 'SM_CSS34_GAMEFIX_1_EP1' not in text:
    if needle not in text:
        raise SystemExit('Failed to locate ConfigureForHL2 SdkHelpers.configureCxx return')
    text = text.replace(needle, insert, 1)
    print('==> Patched ConfigureForHL2 for episode1 tier1-before-vstdlib')
elif 'css34: episode1 -> sourcemod.2.ep1.so' in text:
    print('==> ConfigureForHL2 episode1 css34 link already patched')
else:
    # Older patch only covered ep1 - widen to episode1.
    if "if sdk.get('name') == 'ep1':" in text and "in ('ep1', 'episode1')" not in text:
        text = text.replace(
            "    # css34: sourcemod.1.ep1.so / extensions must advertise gamesuffix 1.ep1\n"
            "    if sdk.get('name') == 'ep1':\n"
            "      compiler.defines += ['SM_CSS34_GAMEFIX_1_EP1']\n",
            "    # css34: episode1 -> sourcemod.2.ep1.so (Metamod 1.12); optional ep1 -> 1.ep1\n"
            "    if sdk.get('name') in ('ep1', 'episode1'):\n"
            "      if sdk.get('name') == 'ep1':\n"
            "        compiler.defines += ['SM_CSS34_GAMEFIX_1_EP1']\n",
            1,
        )
        print('==> Widened ConfigureForHL2 css34 link patch to episode1')
    else:
        print('==> ConfigureForHL2 css34 link patch present')

# ExtLibrary pthread/rt + leave META_NO_HL2SDK happy against Metamod 1.12 headers
old_ext = """  def ExtLibrary(self, context, compiler, name):
    binary = self.Library(context, compiler, name)
    SetArchFlags(compiler)
    self.ConfigureForExtension(context, binary.compiler)
    return binary
"""
new_ext = """  def ExtLibrary(self, context, compiler, name):
    binary = self.Library(context, compiler, name)
    SetArchFlags(compiler)
    self.ConfigureForExtension(context, binary.compiler)
    # css34: pthread/rt DT_NEEDED on pre-2.34 glibc
    if compiler.target.platform == 'linux':
      for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt'):
        if flag not in binary.compiler.linkflags:
          binary.compiler.linkflags += [flag]
    return binary
"""
if 'css34: pthread/rt DT_NEEDED on pre-2.34' not in text:
    if old_ext not in text:
        print('==> WARN: ExtLibrary pattern not found (continuing)')
    else:
        text = text.replace(old_ext, new_ext, 1)
        print('==> Patched ExtLibrary for pthread/rt')
else:
    print('==> ExtLibrary already patched')

# Force link via C++ driver (AMBuild master defaults to raw `ld`, which rejects
# -static-libstdc++ and other gcc/clang driver flags used by SourceMod).
if "css34: link via C++ driver" not in text:
    detect_anchor = "    if not self.all_targets:\n        raise Exception('No suitable C/C++ compiler was found.')\n"
    detect_insert = detect_anchor + """
    # css34: link via C++ driver (AMBuild tip uses raw ld by default)
    for _cxx in self.all_targets:
      _cxx.linker_argv = list(_cxx.cxx_argv)
"""
    if detect_anchor not in text:
        raise SystemExit('Failed to locate DetectCxx all_targets guard')
    text = text.replace(detect_anchor, detect_insert, 1)
    print('==> Forced linker_argv to C++ driver')
else:
    print('==> linker_argv already forced to C++ driver')

# Global CXX11 ABI + SDK warning suppressions for clang/gcc on episode1
if "CSS34 SDK compatibility" not in text:
    marker = "    if have_gcc:\n      cxx.cflags += ['-mfpmath=sse']\n      cxx.cflags += ['-Wno-maybe-uninitialized']\n"
    extra = marker + """    # CSS34 SDK compatibility
    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']
    if have_gcc:
      cxx.cflags += [
        '-Wno-stringop-overflow', '-Wno-error=stringop-overflow',
        '-Wno-stringop-truncation', '-Wno-error=stringop-truncation',
        '-Wno-format-truncation', '-Wno-error=format-truncation',
      ]
    cxx.defines += ['_GLIBCXX_USE_CXX11_ABI=0']
"""
    if marker not in text:
        alt = "    have_gcc = cxx.family == 'gcc'\n"
        if alt not in text:
            raise SystemExit('Failed to locate configure_gcc warning block')
        text = text.replace(
            alt,
            alt + "    # CSS34 SDK compatibility (early)\n"
                 "    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']\n"
                 "    if cxx.family == 'gcc':\n"
                 "      cxx.cflags += ['-Wno-stringop-overflow', '-Wno-error=stringop-overflow', '-Wno-stringop-truncation', '-Wno-error=stringop-truncation', '-Wno-format-truncation', '-Wno-error=format-truncation']\n"
                 "    if '_GLIBCXX_USE_CXX11_ABI=0' not in cxx.defines:\n"
                 "      cxx.defines += ['_GLIBCXX_USE_CXX11_ABI=0']\n",
            1,
        )
        print('==> Injected CSS34 compiler flags (alt path)')
    else:
        text = text.replace(marker, extra, 1)
        print('==> Injected CSS34 compiler flags')
else:
    print('==> CSS34 compiler flags already present')

ambuild.write_text(text, encoding='utf-8')

# SourcePawn sign-compare under -Werror on gcc-9
sp = sm / 'sourcepawn/AMBuildScript'
if sp.exists():
    sp_text = sp.read_text()
    if 'CSS34 sign-compare' not in sp_text:
        sp_text = sp_text.replace(
            "'-Werror',\n",
            "'-Werror',\n            '-Wno-sign-compare',  # CSS34 sign-compare\n",
            1,
        )
        if "cxx.cxxflags += ['-std=c++17']" in sp_text and "CSS34 sign-compare" not in "".join(sp_text.split("cxx.cxxflags")[1:2]):
            sp_text = sp_text.replace(
                "cxx.cxxflags += ['-std=c++17']\n",
                "cxx.cxxflags += ['-std=c++17']\n        cxx.cxxflags += ['-Wno-sign-compare']  # CSS34 sign-compare\n",
                1,
            )
        sp.write_text(sp_text)
        print('==> Patched sourcepawn AMBuildScript for sign-compare')
        sp_text = sp.read_text()

    # Force pthread/rt DT_NEEDED (glibc < 2.34 / Debian 11) - bare -lpthread is
    # dropped by --as-needed when nothing in the .o files references it directly.
    # Note: when SourcePawn is built under SourceMod, Configure() is skipped and
    # SM.all_targets is used - so also patch BuildDynamicCoreLib below.
    old_pl = "                cxx.postlink += ['-lpthread', '-lrt']"
    new_pl = (
        "                # css34: force pthread/rt NEEDED for Debian 11 / CentOS 7 glibc\n"
        "                cxx.postlink += ['-Wl,--no-as-needed', '-lpthread', '-lrt']"
    )
    sp_text = sp.read_text()
    if 'css34: force pthread/rt NEEDED for Debian 11' in sp_text and 'BuildDynamicCoreLib' in sp_text:
        pass  # may still need BuildDynamicCoreLib below
    if old_pl in sp_text and 'css34: force pthread/rt NEEDED for Debian 11' not in sp_text:
        sp.write_text(sp_text.replace(old_pl, new_pl, 1))
        print('==> Patched sourcepawn AMBuildScript Configure for pthread/rt DT_NEEDED')
        sp_text = sp.read_text()
    elif 'css34: force pthread/rt NEEDED for Debian 11' in sp_text:
        print('==> sourcepawn Configure pthread/rt already patched')
    else:
        print('==> WARN: sourcepawn linux pthread postlink not found')

    # Embedded under SM: libsourcepawn.so is built via SPRoot.Library(SM) using
    # SM.all_targets (no SP Configure postlink). Force DT_NEEDED on the shared lib
    # that package.sh renames to sourcepawn.jit.x86.so.
    dyn_marker = 'css34: libsourcepawn pthread/rt DT_NEEDED'
    if dyn_marker not in sp_text:
        dyn_old = (
            "    def BuildDynamicCoreLib(self, builder):\n"
            "        cxx = builder.cxx\n"
            "        binary = self.root.Library(builder, 'libsourcepawn')\n\n"
            "        self.SetupBinForArch(binary, builder)\n"
        )
        dyn_new = (
            "    def BuildDynamicCoreLib(self, builder):\n"
            "        cxx = builder.cxx\n"
            "        binary = self.root.Library(builder, 'libsourcepawn')\n\n"
            "        self.SetupBinForArch(binary, builder)\n"
            "        # css34: libsourcepawn pthread/rt DT_NEEDED (packaged as sourcepawn.jit.x86.so)\n"
            "        if binary.compiler.target.platform == 'linux':\n"
            "          for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt'):\n"
            "            if flag not in binary.compiler.linkflags:\n"
            "              binary.compiler.linkflags += [flag]\n"
        )
        if dyn_old not in sp_text:
            print('==> WARN: BuildDynamicCoreLib pattern not found')
        else:
            sp.write_text(sp_text.replace(dyn_old, dyn_new, 1))
            print('==> Patched BuildDynamicCoreLib for pthread/rt DT_NEEDED')
    else:
        print('==> BuildDynamicCoreLib pthread/rt already patched')

    # css34: static libsourcepawn is linked into logic.so — must use ABI0.
    if 'CSS34 ABI0 for static libsourcepawn' not in sp_text:
        sp_text = sp_text.replace(
            "    def SetupBinForArch(self, binary, builder):\n        if binary.compiler.like('gcc'):",
            "    def SetupBinForArch(self, binary, builder):\n"
            "        # CSS34 ABI0 for static libsourcepawn (embedded in logic.so)\n"
            "        if '_GLIBCXX_USE_CXX11_ABI=0' not in binary.compiler.defines:\n"
            "            binary.compiler.defines += ['_GLIBCXX_USE_CXX11_ABI=0']\n"
            "        if binary.compiler.like('gcc'):",
            1,
        )
        sp.write_text(sp_text)
        print('==> Patched sourcepawn SetupBinForArch for ABI0 static lib')
        sp_text = sp.read_text()
    else:
        print('==> sourcepawn ABI0 static lib patch already present')

# sourcemod.logic.so must match rom4s link profile (old libstdc++ ABI, pthread/rt
# NEEDED, static embed). SM 1.12 uses `for cxx in builder.targets` - adapt the
# g++-9 + SM_LOGIC_CXX_SYSROOT toolchain from the 1.11 apply-sourcemod.sh path.
logic_am = sm / 'core/logic/AMBuilder'
if logic_am.exists():
    lt = logic_am.read_text()
    pv_parts = (sm / 'product.version').read_text().strip().split('.')
    sm_minor = int(pv_parts[1]) if len(pv_parts) > 1 else 11
    if 'SM_LOGIC_CXX_SYSROOT gcc-4.9 g++-9' not in lt and 'SM_LOGIC_CXX_SYSROOT gcc-9 g++-9' not in lt:
        loop_old = "for cxx in builder.targets:\n  binary = SM.Library(builder, cxx, 'sourcemod.logic')\n"
        # SM 1.12: gcc-4.9 sysroot + strptime ParseTime shim.
        # SM 1.13+: static SourcePawn headers need C++17 (<string_view>); use host
        # g++-9 headers with ABI0 + static gcc-9 libstdc++.a at link time.
        sysroot_inc = ""
        if sm_minor < 13:
            sysroot_inc = """
    _sysroot = _os.environ.get('SM_LOGIC_CXX_SYSROOT', '')
    if _sysroot and logic_cxx.target.arch == 'x86':
      logic_cxx.cxxflags += [
        '-nostdinc++',
        '-isystem', _os.path.join(_sysroot, 'usr/include/c++/4.9'),
        '-isystem', _os.path.join(_sysroot, 'usr/include/x86_64-linux-gnu/c++/4.9/32'),
        '-isystem', _os.path.join(_sysroot, 'usr/include/i386-linux-gnu/c++/4.9'),
        '-isystem', _os.path.join(_sysroot, 'usr/include/i386-linux-gnu/c++/4.9/i686-linux-gnu'),
        '-isystem', _os.path.join(_sysroot, 'usr/include/c++/4.9/backward'),
      ]"""
        logic_toolchain = "gcc-4.9 g++-9" if sm_minor < 13 else "gcc-9 g++-9"
        loop_new = f"""for cxx in builder.targets:
  if cxx.target.platform == 'linux':
    # css34: SM_LOGIC_CXX_SYSROOT {logic_toolchain} logic toolchain.
    import shutil as _shutil
    import os as _os
    logic_cxx = cxx.clone()
    _gpp9 = _shutil.which('g++-9') or '/usr/bin/g++-9'
    _gcc9 = _shutil.which('gcc-9') or '/usr/bin/gcc-9'
    logic_cxx.cxx_argv = [_gpp9]
    logic_cxx.cc_argv = [_gcc9]
    logic_cxx.linker_argv = [_gpp9]
    if logic_cxx.target.arch == 'x86':
      if '-m32' not in logic_cxx.cflags:
        logic_cxx.cflags += ['-m32']
      if '-m32' not in logic_cxx.linkflags:
        logic_cxx.linkflags += ['-m32']
    _clang_only = [
      '-Wno-nonportable-include-path', '-Wno-macro-redefined', '-Wno-writable-strings',
      '-Wno-sometimes-uninitialized', '-Wno-inconsistent-missing-override',
      '-Wno-implicit-exception-spec-mismatch', '-Wno-deprecated-register',
      '-Wno-tautological-overlap-compare',
    ]
    for _attr in ('cflags', 'cxxflags'):
      _flags = getattr(logic_cxx, _attr)
      setattr(logic_cxx, _attr, [_f for _f in _flags if _f not in _clang_only]){sysroot_inc}
    for _flag in ('-lgcc_eh', '-static-libstdc++'):
      if _flag in logic_cxx.linkflags:
        logic_cxx.linkflags.remove(_flag)
    if '-static-libgcc' not in logic_cxx.linkflags:
      logic_cxx.linkflags += ['-static-libgcc']
    logic_cxx.cxxflags += [
      '-Wno-maybe-uninitialized', '-Wno-class-memaccess', '-Wno-packed-not-aligned',
      '-Wno-stringop-truncation', '-Wno-unused-result',
      '-D_GLIBCXX_USE_CXX11_ABI=0',
      '-fno-sized-deallocation',  # css34: no UND _ZdlPvj/_ZdaPvj at dlopen
    ]
    binary = SM.Library(builder, logic_cxx, 'sourcemod.logic')
  else:
    binary = SM.Library(builder, cxx, 'sourcemod.logic')
"""
        if loop_old not in lt:
            print('==> WARN: logic AMBuilder for-cxx loop not found (layout changed?)')
        else:
            lt = lt.replace(loop_old, loop_new, 1)
            print(f'==> Patched logic AMBuilder ({logic_toolchain})')

    # Defines: old ABI + no HL2 malloc hooks (rom4s logic profile).
    if '_GLIBCXX_USE_CXX11_ABI=0' not in lt or 'NO_HOOK_MALLOC' not in lt:
        defs_old = """  binary.compiler.defines += [
    'SM_DEFAULT_THREADER',
    'SM_LOGIC'
  ]"""
        defs_new = """  binary.compiler.defines += [
    'SM_DEFAULT_THREADER',
    'SM_LOGIC',
    '_GLIBCXX_USE_CXX11_ABI=0',
    'NO_HOOK_MALLOC',
    'NO_MALLOC_OVERRIDE',
  ]"""
        # boot-trace may already have added SM_BOOT_TRACE
        defs_old_boot = """  binary.compiler.defines += [
    'SM_DEFAULT_THREADER',
    'SM_LOGIC',
    'SM_BOOT_TRACE',
  ]"""
        defs_new_boot = """  binary.compiler.defines += [
    'SM_DEFAULT_THREADER',
    'SM_LOGIC',
    '_GLIBCXX_USE_CXX11_ABI=0',
    'NO_HOOK_MALLOC',
    'NO_MALLOC_OVERRIDE',
    'SM_BOOT_TRACE',
  ]"""
        if defs_old_boot in lt:
            lt = lt.replace(defs_old_boot, defs_new_boot, 1)
            print('==> Patched logic AMBuilder css34 ABI defines (with boot-trace)')
        elif defs_old in lt:
            lt = lt.replace(defs_old, defs_new, 1)
            print('==> Patched logic AMBuilder css34 ABI defines')
        else:
            print('==> WARN: logic AMBuilder defines block not found')

    # Linux link: static sysroot/gcc-9 libstdc++ + forced pthread/rt DT_NEEDED.
    if 'css34: gcc-4.9 libstdc++ static when SM_LOGIC_CXX_SYSROOT' not in lt:
        linux_old_variants = [
            """  if binary.compiler.target.platform == 'linux':
    binary.compiler.postlink += ['-lpthread', '-lrt', '-lm']
  elif binary.compiler.target.platform == 'mac':""",
            """  if binary.compiler.target.platform == 'linux':
    # css34: force pthread/rt NEEDED for Debian 11 / CentOS 7 glibc
    binary.compiler.postlink += ['-Wl,--no-as-needed', '-lpthread', '-lrt']
  elif binary.compiler.target.platform == 'mac':""",
            """  if binary.compiler.target.platform == 'linux':
    binary.compiler.postlink += ['-lpthread', '-lrt']
  elif binary.compiler.target.platform == 'mac':""",
        ]
        linux_new = """  if binary.compiler.target.platform == 'linux':
    # css34: gcc-4.9 libstdc++ static when SM_LOGIC_CXX_SYSROOT set; else gcc-9.
    import os as _os
    for flag in ('-static-libstdc++', '-lgcc_eh', '-lstdc++', '-nodefaultlibs'):
      if flag in binary.compiler.linkflags:
        binary.compiler.linkflags.remove(flag)
    for flag in list(binary.compiler.postlink):
      if flag in ('-lpthread', '-lrt', '-Wl,--no-as-needed'):
        binary.compiler.postlink.remove(flag)
    _sysroot = _os.environ.get('SM_LOGIC_CXX_SYSROOT', '')
    _stdcxx = None
    _sup = None
    if _sysroot:
      for _base in (
          _os.path.join(_sysroot, 'usr/lib/gcc/x86_64-linux-gnu/4.9/32'),
          _os.path.join(_sysroot, 'usr/lib/gcc/i686-linux-gnu/4.9'),
          _os.path.join(_sysroot, 'usr/lib/gcc/x86_64-linux-gnu/8/32'),
          _os.path.join(_sysroot, 'usr/lib/gcc/i686-linux-gnu/8'),
          _os.path.join(_sysroot, 'usr/lib/gcc/i686-linux-gnu/4.8'),
      ):
        _cand = _os.path.join(_base, 'libstdc++.a')
        if _os.path.isfile(_cand):
          _stdcxx = _cand
          _sup = _os.path.join(_base, 'libsupc++.a')
          break
    if _stdcxx is None:
      for _cand in (
          '/usr/lib/gcc/i686-linux-gnu/9/libstdc++.a',
          '/usr/lib/gcc/x86_64-linux-gnu/9/32/libstdc++.a',
      ):
        if _os.path.isfile(_cand):
          _stdcxx = _cand
          _sup = _os.path.join(_os.path.dirname(_cand), 'libsupc++.a')
          break
    if _stdcxx is None:
      raise Exception('logic libstdc++.a not found (install sysroot-i386 or gcc-9-multilib)')
    _gcc = _os.path.join(_os.path.dirname(_stdcxx), 'libgcc.a')
    _gcc_eh = _os.path.join(_os.path.dirname(_stdcxx), 'libgcc_eh.a')
    for flag in ('-static-libgcc',):
      if flag in binary.compiler.linkflags:
        binary.compiler.linkflags.remove(flag)
    _static = ['-nodefaultlibs', '-Wl,-Bstatic', _stdcxx]
    if _sup and _os.path.isfile(_sup):
      _static.append(_sup)
    if _os.path.isfile(_gcc_eh):
      _static.append(_gcc_eh)
    if _os.path.isfile(_gcc):
      _static.append(_gcc)
    binary.compiler.linkflags += _static + [
      '-Wl,-Bdynamic',
      '-lc', '-lm',
      '-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s',
    ]
    # css34: hide static archive symbols from the dynamic export table (libsourcepawn_static)
    if '-Wl,--exclude-libs,ALL' not in binary.compiler.linkflags:
      binary.compiler.linkflags += ['-Wl,--exclude-libs,ALL']
  elif binary.compiler.target.platform == 'mac':"""
        replaced = False
        for linux_old in linux_old_variants:
            if linux_old in lt:
                lt = lt.replace(linux_old, linux_new, 1)
                replaced = True
                print('==> Patched logic AMBuilder linux static libstdc++ + pthread/rt')
                break
        if not replaced:
            print('==> WARN: logic linux postlink block not found for static link patch')
    else:
        print('==> logic AMBuilder static libstdc++ already patched')

    if 'css34: logic postlink pthread after static SP' not in lt:
        sp_libs_anchor = """  binary.compiler.linkflags += [
    SP.static_libsp[arch],
    SP.libamtl[arch],
    SP.zlib[arch],
  ]"""
        sp_libs_new = sp_libs_anchor + """
  if binary.compiler.target.platform == 'linux':
    # css34: logic postlink pthread after static SP archives (DT_NEEDED on glibc < 2.34)
    for flag in list(binary.compiler.linkflags):
      if flag in ('-lpthread', '-lrt', '-Wl,--no-as-needed'):
        binary.compiler.linkflags.remove(flag)
    for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt'):
      if flag not in binary.compiler.postlink:
        binary.compiler.postlink += [flag]
"""
        if sp_libs_anchor not in lt:
            print('==> WARN: logic AMBuilder SP static libs anchor not found')
        else:
            lt = lt.replace(sp_libs_anchor, sp_libs_new, 1)
            print('==> Patched logic AMBuilder postlink pthread after static SP')

    logic_am.write_text(lt)

# cstrike: build for episode1 (Metamod 1.12 path)
cstrike = sm / 'extensions/cstrike/AMBuilder'
if cstrike.exists():
    ct = cstrike.read_text()
    if "['episode1', 'css', 'csgo']" not in ct and "['ep1', 'episode1'" not in ct:
        ct = ct.replace(
            "for sdk_name in ['css', 'csgo']:",
            "for sdk_name in ['episode1', 'css', 'csgo']:",
            1,
        )
        cstrike.write_text(ct)
        print('==> cstrike AMBuilder includes episode1')
    else:
        print('==> cstrike AMBuilder already includes episode1')

for rel in ('extensions/cstrike/forwards.cpp', 'extensions/cstrike/natives.cpp'):
    p = sm / rel
    if p.exists():
        p.write_text(p.read_text().replace(
            '#if SOURCE_ENGINE == SE_CSS',
            '#if SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_EPISODEONE',
        ))

# cstrike GetPlayerVarAddressOrError: FindInDataMap returns incomplete typedescription_t on EP1
natives = sm / 'extensions/cstrike/natives.cpp'
if natives.exists():
    text = natives.read_text()
    old_block = """\t\tdatamap_t *pMap = gamehelpers->GetDataMap(pPlayerEntity);
\t\ttypedescription_t *td = gamehelpers->FindInDataMap(pMap, pszBaseVar);
\t\tif (td)
\t\t{
#if SOURCE_ENGINE >= SE_LEFT4DEAD
\t\t\tinterimOffset = td->fieldOffset;
#else
\t\t\tinterimOffset = td->fieldOffset[TD_OFFSET_NORMAL];
#endif
\t\t}"""
    new_block = """\t\tdatamap_t *pMap = gamehelpers->GetDataMap(pPlayerEntity);
\t\tsm_datatable_info_t datamapInfo;
\t\tif (gamehelpers->FindDataMapInfo(pMap, pszBaseVar, &datamapInfo))
\t\t{
\t\t\tinterimOffset = datamapInfo.actual_offset;
\t\t}"""
    if old_block in text:
        natives.write_text(text.replace(old_block, new_block, 1))
        print('==> Patched cstrike natives FindDataMapInfo')
    elif 'FindDataMapInfo(pMap, pszBaseVar' in text:
        print('==> cstrike natives FindDataMapInfo already patched')
    else:
        print('==> WARN: cstrike natives FindInDataMap block not found')

# Prefer full upstream SHA in sourcemod_version_auto.h (smoke checks Built from).
gen = sm / 'tools/buildbot/generate_headers.py'
if gen.exists():
    gt = gen.read_text()
    if 'css34: full commit SHA' in gt:
        print('==> SM generate_headers already prefers full SHA')
    else:
        old = '""".format(tag, shorthash, major, minor, release, fullstring, count))'
        new = '""".format(tag, longhash, major, minor, release, fullstring, count))'
        if old not in gt:
            print('==> WARN: SM generate_headers SHA format unchanged')
        else:
            # Replace both .h and .inc emitters (two identical format(...) lines).
            gt = gt.replace(old, new)
            gt = gt.replace(
                "  with open(os.path.join(OutputFolder, 'sourcemod_version_auto.h'), 'w') as fp:\n",
                "  # css34: full commit SHA for sm version Built from\n"
                "  with open(os.path.join(OutputFolder, 'sourcemod_version_auto.h'), 'w') as fp:\n",
                1,
            )
            gen.write_text(gt)
            print('==> Patched SM generate_headers.py to emit full commit SHA')

# css34: CacheGameBinaryInfo dlopen(engine_i486.so)+dlclose leaves dangling
# ConVars on vstdlib's s_pConCommandBases (srcds loads engine_i686.so). Prefer
# RTLD_NOLOAD and the already-loaded _i686 sibling; never RTLD_NOW a second copy.
gc = sm / 'core/logic/GameConfigs.cpp'
if gc.exists():
    gt = gc.read_text()
    if 'css34: RTLD_NOLOAD game binary' in gt:
        print('==> GameConfigs CacheGameBinaryInfo already RTLD_NOLOAD patched')
    else:
        old_cache = """#else
\t\tvoid *pHandle = dlopen(binary_path, RTLD_NOW);
\t\tif (pHandle)
\t\t{
\t\t\tinfo.m_pAddr = dlsym(pHandle, "CreateInterface");
\t\t\tdlclose(pHandle);
\t\t}
#endif"""
        new_cache = """#else
\t\t/* css34: RTLD_NOLOAD game binary - avoid loading engine_i486.so while
\t\t * engine_i686.so is already mapped. A temporary RTLD_NOW copy runs
\t\t * ConVar static ctors into vstdlib's list; dlclose then dangling-pointer
\t\t * crashes FindVar (sv_logecho) during SM init. */
\t\tvoid *pHandle = dlopen(binary_path, RTLD_NOW | RTLD_NOLOAD);
\t\tif (!pHandle)
\t\t{
\t\t\tchar alt_path[PLATFORM_MAX_PATH];
\t\t\tke::SafeStrcpy(alt_path, sizeof(alt_path), binary_path);
\t\t\tchar *suf = strstr(alt_path, "_i486.so");
\t\t\tif (suf)
\t\t\t{
\t\t\t\tmemcpy(suf, "_i686.so", 8);
\t\t\t\tpHandle = dlopen(alt_path, RTLD_NOW | RTLD_NOLOAD);
\t\t\t}
\t\t\telse if ((suf = strstr(alt_path, "_i686.so")) != nullptr)
\t\t\t{
\t\t\t\tmemcpy(suf, "_i486.so", 8);
\t\t\t\tpHandle = dlopen(alt_path, RTLD_NOW | RTLD_NOLOAD);
\t\t\t}
\t\t}
\t\tif (pHandle)
\t\t{
\t\t\tinfo.m_pAddr = dlsym(pHandle, "CreateInterface");
\t\t\tdlclose(pHandle);
\t\t}
#endif"""
        if old_cache not in gt:
            print('==> WARN: CacheGameBinaryInfo dlopen block not found')
        else:
            gt = gt.replace(old_cache, new_cache, 1)
            # Symbol '@' lookups: also use NOLOAD on dli_fname (already mapped).
            old_sym = """\t\t\t\t\t\tvoid *handle = dlopen(info.dli_fname, RTLD_NOW);
\t\t\t\t\t\tif (handle)
\t\t\t\t\t\t{
\t\t\t\t\t\t\tif (bridge->SymbolsAreHidden())
\t\t\t\t\t\t\t\tfinal_addr = g_MemUtils.ResolveSymbol(handle, &s_TempSig.sig[1]);
\t\t\t\t\t\t\telse
\t\t\t\t\t\t\t\tfinal_addr = dlsym(handle, &s_TempSig.sig[1]);
\t\t\t\t\t\t\tdlclose(handle);"""
            new_sym = """\t\t\t\t\t\t/* css34: RTLD_NOLOAD - dli_fname is an already-mapped module */
\t\t\t\t\t\tvoid *handle = dlopen(info.dli_fname, RTLD_NOW | RTLD_NOLOAD);
\t\t\t\t\t\tif (handle)
\t\t\t\t\t\t{
\t\t\t\t\t\t\tif (bridge->SymbolsAreHidden())
\t\t\t\t\t\t\t\tfinal_addr = g_MemUtils.ResolveSymbol(handle, &s_TempSig.sig[1]);
\t\t\t\t\t\t\telse
\t\t\t\t\t\t\t\tfinal_addr = dlsym(handle, &s_TempSig.sig[1]);
\t\t\t\t\t\t\tdlclose(handle);"""
            if old_sym in gt:
                gt = gt.replace(old_sym, new_sym, 1)
                print('==> Patched GameConfigs @-sig dlopen to RTLD_NOLOAD')
            else:
                print('==> WARN: @-sig dlopen block not found (continuing)')
            gc.write_text(gt)
            print('==> Patched GameConfigs CacheGameBinaryInfo for css34 RTLD_NOLOAD')

# ParseTime uses std::get_time (C++11 <iomanip>); gcc-4.9 sysroot headers lack it.
# SM 1.13+ uses host g++-9 headers — keep upstream std::get_time.
smn_core = sm / 'core/logic/smn_core.cpp'
if smn_core.exists():
    sc = smn_core.read_text()
    pv_parts = (sm / 'product.version').read_text().strip().split('.')
    sm_minor = int(pv_parts[1]) if len(pv_parts) > 1 else 11
    if sm_minor >= 13:
        print('==> ParseTime strptime shim skipped (SM 1.13+ uses g++-9 headers)')
    elif 'css34: ParseTime via strptime' in sc:
        print('==> ParseTime strptime already patched')
    elif 'std::get_time' in sc:
        old_pt = """\t// https://stackoverflow.com/a/33542189
\tstd::tm t{};
\tstd::istringstream input(datetime);

\tauto previousLocale = input.imbue(std::locale::classic());
\tinput >> std::get_time(&t, format);
\tbool failed = input.fail();
\tinput.imbue(previousLocale);

\tif (failed)
\t{
\t\treturn pContext->ThrowNativeError("Invalid date/time string or time format.");
\t}
"""
        new_pt = """\t/* css34: ParseTime via strptime (gcc-4.9 sysroot has no std::get_time) */
\tstd::tm t{};
#if defined PLATFORM_WINDOWS
\tstd::istringstream input(datetime);
\tauto previousLocale = input.imbue(std::locale::classic());
\tinput >> std::get_time(&t, format);
\tbool failed = input.fail();
\tinput.imbue(previousLocale);
\tif (failed)
#else
\tif (strptime(datetime, format, &t) == NULL)
#endif
\t{
\t\treturn pContext->ThrowNativeError("Invalid date/time string or time format.");
\t}
"""
        if old_pt not in sc:
            print('==> WARN: ParseTime get_time block not found')
        else:
            sc = sc.replace(old_pt, new_pt, 1)
            # Drop unused iostream helpers when possible (keep if used elsewhere).
            smn_core.write_text(sc)
            print('==> Patched ParseTime to use strptime for gcc-4.9 sysroot')
    else:
        print('==> ParseTime has no std::get_time (ok)')

# css34: LogToOpenFileEx must not call FindConVar(sv_logecho) on first mapchange.
# icvar->FindVar can infinite-loop when vstdlib's ConVar list is corrupted (engine_i486 dlopen).
logger_cpp = sm / 'core/logic/Logger.cpp'
if logger_cpp.exists():
    lt = logger_cpp.read_text()
    if 'CSS34 LOG_ECHO_SAFE' not in lt:
        old_lte = """void Logger::LogToOpenFileEx(FILE *fp, const char *msg, va_list ap)
{
\tstatic ConVar *sv_logecho = bridge->FindConVar("sv_logecho");

\tchar buffer[3072];
\tke::SafeVsprintf(buffer, sizeof(buffer), msg, ap);

\tconst char* date = GetFormattedDate();
\tfprintf(fp, "L %s: %s\\n", date, buffer);

\tif (!sv_logecho || bridge->GetCvarBool(sv_logecho))
\t{
\t\tstatic char conBuffer[4096];
\t\tke::SafeSprintf(conBuffer, sizeof(conBuffer), "L %s: %s\\n", date, buffer);
\t\tbridge->ConPrint(conBuffer);
\t}

\tfflush(fp);
}"""
        new_lte = """void Logger::LogToOpenFileEx(FILE *fp, const char *msg, va_list ap)
{
\tchar buffer[3072];
\tke::SafeVsprintf(buffer, sizeof(buffer), msg, ap);

\tconst char* date = GetFormattedDate();
\tfprintf(fp, "L %s: %s\\n", date, buffer);

\t/* CSS34 LOG_ECHO_SAFE: skip FindConVar(sv_logecho) - icvar->FindVar can hang
\t * on corrupted vstdlib ConVar lists after engine_i486 dlopen side-effects. */
\t{
\t\tstatic char conBuffer[4096];
\t\tke::SafeSprintf(conBuffer, sizeof(conBuffer), "L %s: %s\\n", date, buffer);
\t\tbridge->ConPrint(conBuffer);
\t}

\tfflush(fp);
}"""
        if old_lte not in lt:
            print('==> WARN: Logger LogToOpenFileEx block not found')
        else:
            logger_cpp.write_text(lt.replace(old_lte, new_lte, 1))
            print('==> Patched Logger LogToOpenFileEx (skip sv_logecho FindConVar)')
    else:
        print('==> Logger LOG_ECHO_SAFE already patched')

# bundled curl fortify noise on gcc only (clang-9 rejects -Wno-stringop-*)
curl_ambuild = sm / 'extensions/curl/curl-src/lib/AMBuilder'
if curl_ambuild.exists() and 'stringop-truncation' not in curl_ambuild.read_text():
    ct = curl_ambuild.read_text()
    ct = ct.replace(
        "binary.compiler.defines += ['_GNU_SOURCE']",
        "binary.compiler.defines += ['_GNU_SOURCE']\n"
        "    if binary.compiler.family == 'gcc':\n"
        "      binary.compiler.cflags += ['-Wno-stringop-truncation', '-Wno-error=stringop-truncation']",
        1,
    )
    curl_ambuild.write_text(ct)
    print('==> Patched bundled libcurl for stringop-truncation (gcc)')

# shell.cpp sign-compare
shell = sm / 'sourcepawn/vm/shell/shell.cpp'
if shell.exists() and 'if (index > params[0])' in shell.read_text():
    shell.write_text(shell.read_text().replace(
        'if (index > params[0])',
        'if (index > (size_t)params[0])',
    ))
PY

# --- Source-level patches ---
while IFS= read -r -d '' file; do
  sed -i 's/\r$//' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' -o -name 'AMBuildScript' -o -name 'AMBuilder' \) -print0)

# Episode One CON_COMMAND / pre-OB guards (SE_CSS leftovers still matter for some units)
while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE <= SE_DARKMESSIAH$/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/g' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_CSS/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/g' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

# MIN macros
for rel in extensions/sdktools/vstringtable.cpp core/MenuStyle_Base.cpp; do
  f="$sourcemod_dir/$rel"
  if [ -f "$f" ]; then
    sed -i \
      -e 's/MIN(maxBytes, datalen)/(maxBytes < datalen ? maxBytes : datalen)/g' \
      -e 's/MIN(GetItemCount(), 255)/(GetItemCount() < 255 ? GetItemCount() : 255)/g' \
      -e 's/MIN(length, stop)/(length < stop ? length : stop)/g' \
      -e 's/MIN(length, 255)/(length < 255 ? length : 255)/g' \
      "$f"
  fi
done

# Versioning submodule HEAD
versioning="$sourcemod_dir/tools/buildbot/Versioning"
if [ -f "$versioning" ] && ! grep -q '_resolve_git_head_path' "$versioning"; then
  SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os
versioning = Path(os.environ['SOURCEMOD_DIR']) / 'tools/buildbot/Versioning'
text = versioning.read_text()
old = """with open(os.path.join(builder.sourcePath, '.git', 'HEAD')) as fp:
  head_contents = fp.read().strip()
  if re.search('^[a-fA-F0-9]{40}$', head_contents):
    git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
  else:
    git_state = head_contents.split(':')[1].strip()
    git_head_path = os.path.join(builder.sourcePath, '.git', git_state)
    if not os.path.exists(git_head_path):
      git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
"""
new = """def _resolve_git_head_path(source_path):
  git_meta = os.path.join(source_path, '.git')
  if os.path.isfile(git_meta):
    with open(git_meta) as meta_fp:
      gitdir_line = meta_fp.read().strip()
    if gitdir_line.startswith('gitdir: '):
      git_dir = gitdir_line[8:]
      if not os.path.isabs(git_dir):
        git_dir = os.path.normpath(os.path.join(source_path, git_dir))
    else:
      git_dir = git_meta
  else:
    git_dir = git_meta
  return os.path.join(git_dir, 'HEAD')

git_head_path = _resolve_git_head_path(builder.sourcePath)
with open(git_head_path) as fp:
  head_contents = fp.read().strip()
  if re.search('^[a-fA-F0-9]{40}$', head_contents):
    pass
  else:
    git_state = head_contents.split(':')[1].strip()
    candidate = os.path.join(os.path.dirname(git_head_path), git_state)
    if os.path.exists(candidate):
      git_head_path = candidate
"""
if old in text:
    versioning.write_text(text.replace(old, new, 1))
    print('==> Patched Versioning for submodule gitdir')
else:
    print('==> Versioning already patched or layout changed')
PY
fi

# Optional logger / boot-trace (best-effort; may no-op on 1.12)
bash "$script_dir/apply-logger-mapchange-fix.sh" "$sourcemod_dir" || \
  echo "==> WARN: apply-logger-mapchange-fix.sh failed (continuing)"
bash "$script_dir/apply-sm-boot-trace.sh" "$sourcemod_dir" || \
  echo "==> WARN: apply-sm-boot-trace.sh failed (continuing)"

# sm version CSS34 pack line
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYVER'
from pathlib import Path
import os
path = Path(os.environ['SOURCEMOD_DIR']) / 'core/logic/RootConsoleMenu.cpp'
text = path.read_text()
if 'CSS34 pack:' in text:
    print('==> sm version already prints CSS34 pack commit')
else:
    if '#include <sourcemod_version.h>' not in text:
        print('==> WARN: sourcemod_version.h include missing')
    else:
        text = text.replace(
            '#include <sourcemod_version.h>',
            '#include <sourcemod_version.h>\n#include <css34_build_stamp.h>',
            1,
        )
        old = '''#if defined(SM_GENERATED_BUILD)
\t\tConsolePrint("    Built from: https://github.com/alliedmodders/sourcemod/commit/%s", SOURCEMOD_SHA);
\t\tConsolePrint("    Build ID: %s:%s", SOURCEMOD_LOCAL_REV, SOURCEMOD_SHA);
#endif
'''
        new = '''#if defined(SM_GENERATED_BUILD)
\t\tConsolePrint("    Built from: https://github.com/alliedmodders/sourcemod/commit/%s", SOURCEMOD_SHA);
\t\tConsolePrint("    CSS34 pack: https://github.com/fmu1337/sourcemod-css34/commit/%s", CSS34_PACK_COMMIT);
\t\tConsolePrint("    Build ID: %s:%s", SOURCEMOD_LOCAL_REV, SOURCEMOD_SHA);
#endif
'''
        if old in text:
            path.write_text(text.replace(old, new, 1))
            print('==> Patched sm version CSS34 pack line')
        else:
            print('==> WARN: Built from block not found for CSS34 pack')
PYVER

echo "==> SourceMod 1.12+ css34 patches applied (Metamod 1.12 / 2.ep1)"
