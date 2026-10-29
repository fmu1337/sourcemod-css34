#!/usr/bin/env bash
# CS:S v34 compatibility for SourceMod 1.12+ (hl2sdk-manifests / AMBuild 2.2).
# Pairs with Metamod:Source 1.12 (PLAPI 16 / modern Core / metamod.2.ep1).
# Primary binary: sourcemod.2.ep1.so (SE_EPISODEONE / gamesuffix 2.ep1).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

sourcemod_dir="${1:?sourcemod directory required}"
echo "==> Applying SourceMod 1.12+ css34 patches (Metamod 1.12 / 2.ep1)"

# sm13's vendored libpq imports explicit_bzero (glibc >= 2.25).
"${PY[@]}" "$script_dir/patch-pgsql-explicit-bzero.py" "$sourcemod_dir"
"${PY[@]}" "$script_dir/patch-mysql-static-zlib.py" "$sourcemod_dir"

# --- manifests ---
manifests_dir="$sourcemod_dir/hl2sdk-manifests/manifests"
if [ ! -d "$manifests_dir" ]; then
  echo "hl2sdk-manifests missing; is this SourceMod 1.12+?" >&2
  exit 1
fi

# Ensure episode1 linux defines match css34 (no HL2 malloc hooks).
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYMAN'
from pathlib import Path
import json, os
man = Path(os.environ['SOURCEMOD_DIR']) / 'hl2sdk-manifests/manifests/episode1.json'
data = json.loads(man.read_text())
linux = data.setdefault('linux', {})
defs = linux.setdefault('defines', [])
changed = False
for d in ('NO_HOOK_MALLOC', 'NO_MALLOC_OVERRIDE'):
    if d not in defs:
        defs.append(d)
        changed = True
if '_GLIBCXX_USE_CXX11_ABI=0' in defs:
    defs.remove('_GLIBCXX_USE_CXX11_ABI=0')
    changed = True
if changed:
    man.write_text(json.dumps(data, indent=4) + '\n')
    print('==> Patched SM episode1.json linux defines for css34')
else:
    print('==> SM episode1.json linux defines already ok')
PYMAN

# Manifests can add flags GCC 10 does not know (hl2sdk-manifests ebd6e10).
"${PY[@]}" "$script_dir/manifest_flag_guard.py" \
  "$sourcemod_dir/hl2sdk-manifests/SdkHelpers.ambuild"

# 1.12-dev cherry-picked OnMapEnd (#2589) with std::list, but this branch still
# stores OutputHookList as SourceHook::List and does not include <list>.
# GCC 10 then fails sdktools: 'list' is not a member of 'std'. 1.13 already
# uses std::list for the whole file, so leave that tree alone.
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYOUT'
from pathlib import Path
import os
path = Path(os.environ['SOURCEMOD_DIR']) / 'extensions/sdktools/output.cpp'
text = path.read_text()
marker = 'css34: OnMapEnd uses SourceHook::List on SM 1.12'
old = (
    "void EntityOutputManager::OnMapEnd()\n"
    "{\n"
    "\tIPluginIterator *plugins = plsys->GetPluginIterator();\n"
    "\tfor (; plugins->MorePlugins(); plugins->NextPlugin())\n"
    "\t{\n"
    "\t\tstd::list<omg_hooks *> *pList = NULL;\n"
)
new = old.replace("{\n\tIPluginIterator", "{\n\t// " + marker + "\n\tIPluginIterator", 1).replace(
    'std::list<omg_hooks *>', 'SourceHook::List<omg_hooks *>')
sh_list = 'SourceHook::List<omg_hooks *>'
std_list = 'std::list<omg_hooks *>'
# Validate the stored list declarations as well as the map-end anchor. A marker
# alone, a missing function, or an unknown type must never count as success.
sh_storage = text.count('\t' + sh_list + ' *pList = NULL;\n')
std_storage = text.count('\t' + std_list + ' *pList = NULL;\n')
# ALLOWLIST: the acceptance baselines predate upstream OnMapEnd (#2589).
# Accept only the complete, unmodified historical files; a removed function
# in another revision remains an error. Git blob IDs include original CRLF.
import hashlib
raw = path.read_bytes()
blob = hashlib.sha1(b'blob %d\0' % len(raw) + raw).hexdigest()
historical = {
    '4e4db005a95d74939412b512e3115522eb3a202d',  # SM 1.12 r7253 baseline
    'cbc7edde32d6446a52cb721ebd746be73ade0085',  # SM 1.13 r7472 baseline
}
if blob in historical:
    print('==> Known pre-OnMapEnd upstream baseline; no cherry-pick fix needed')
elif marker in text:
    if text.count(new) != 1 or std_list in text or sh_storage != 3:
        raise SystemExit('FAIL: malformed OnMapEnd SourceHook::List patch')
    print('==> OnMapEnd SourceHook::List patch already present')
elif sh_list in text:
    if text.count(old) != 1 or text.count(std_list) != 1 or sh_storage != 2:
        raise SystemExit('FAIL: OnMapEnd std::list anchor or storage declarations drifted')
    path.write_text(text.replace(old, new, 1))
    print('==> Patched OnMapEnd to SourceHook::List (SM 1.12 #2589 cherry-pick)')
elif text.count(old) == 1 and std_storage == 3 and '#include <list>' in text:
    print('==> OnMapEnd uses std::list consistently (SM 1.13)')
else:
    raise SystemExit('FAIL: unrecognized OnMapEnd hook-list layout in output.cpp')

PYOUT

# --- AMBuildScript / SdkHelpers (1.12 structure) ---
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

sm = Path(os.environ['SOURCEMOD_DIR'])
ambuild = sm / 'AMBuildScript'
text = ambuild.read_text()

mms_inc_old = """    compiler.cxxincludes += [
      os.path.join(self.mms_root, 'core'),
      os.path.join(self.mms_root, 'core', 'sourcehook'),
    ]"""
mms_inc_new = """    legacy_core = os.path.join(self.mms_root, 'core-css34legacy')
    sdk_name = sdk.get('name') if isinstance(sdk, dict) else getattr(sdk, 'name', None)
    if sdk_name in ('ep1', 'episode1'):
      if os.path.isdir(legacy_core):
        mms_core = legacy_core
        print('==> Using Metamod core-css34legacy include path for ' + str(sdk_name) + ': ' + mms_core)
      elif os.path.isdir(os.path.join(self.mms_root, 'core-legacy')):
        raise SystemExit('MM 1.10 detected (core-legacy exists) but core-css34legacy is missing in ' + self.mms_root + '! Run checkout-deps.sh / apply-mmsource-css34.sh first.')
      else:
        mms_core = os.path.join(self.mms_root, 'core')
    else:
      mms_core = os.path.join(self.mms_root, 'core')
    compiler.cxxincludes += [
      mms_core,
      os.path.join(mms_core, 'sourcehook'),
    ]"""
if 'core-css34legacy' in text:
    print('==> ConfigureForHL2 cxxincludes already patched for core-css34legacy')
elif mms_inc_old in text:
    text = text.replace(mms_inc_old, mms_inc_new, 1)
    print('==> Patched ConfigureForHL2 cxxincludes for core-css34legacy')
else:
    raise SystemExit('FAIL: ConfigureForHL2 cxxincludes anchor not found in AMBuildScript')

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
      # css34: non-SDK extensions hide every static archive. Game extensions
      # (HL2Library) keep tier1 exports.
      _base = name[:-4] if name.endswith('.ext') else name
      if (_base.startswith('dbi.') or _base in (
          'bintools', 'clientprefs', 'geoip', 'regex', 'topmenus', 'updater', 'webternet')):
        if '-Wl,--exclude-libs,ALL' not in binary.compiler.linkflags:
          binary.compiler.linkflags += ['-Wl,--exclude-libs,ALL']
    return binary
"""
if 'css34: pthread/rt DT_NEEDED on pre-2.34' not in text:
    if old_ext not in text:
        raise SystemExit('FAIL: ExtLibrary anchor not found in AMBuildScript')
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

# SDK warning suppressions for gcc on episode1
if "CSS34 SDK compatibility" not in text:
    marker = "    if have_gcc:\n      cxx.cflags += ['-mfpmath=sse']\n      cxx.cflags += ['-Wno-maybe-uninitialized']\n"
    extra = marker + """    # CSS34 SDK compatibility
    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes', '-Wno-volatile']
    if have_gcc:
      cxx.cflags += [
        '-Wno-stringop-overflow', '-Wno-error=stringop-overflow',
        '-Wno-stringop-truncation', '-Wno-error=stringop-truncation',
        '-Wno-format-truncation', '-Wno-error=format-truncation',
      ]
"""
    if marker not in text:
        alt = "    have_gcc = cxx.family == 'gcc'\n"
        if alt not in text:
            raise SystemExit('Failed to locate configure_gcc warning block')
        text = text.replace(
            alt,
            alt + "    # CSS34 SDK compatibility (early)\n"
                 "    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes', '-Wno-volatile']\n"
                 "    if cxx.family == 'gcc':\n"
                 "      cxx.cflags += ['-Wno-stringop-overflow', '-Wno-error=stringop-overflow', '-Wno-stringop-truncation', '-Wno-error=stringop-truncation', '-Wno-format-truncation', '-Wno-error=format-truncation']\n",
            1,
        )
        print('==> Injected CSS34 compiler flags (alt path)')
    else:
        text = text.replace(marker, extra, 1)
        print('==> Injected CSS34 compiler flags')
else:
    print('==> CSS34 compiler flags already present')

# SM 7461+ sets -std=c++20. devtoolset-10 GCC 10.2 compiles that standard,
# including <span>, so the upstream flag is left unchanged.

ambuild.write_text(text, encoding='utf-8')

# SourcePawn builds with -Werror. GCC 10 still errors on sign-compare in the
# JIT/compiler, so keep -Wno-sign-compare. Anchor the C++ flag on the upstream
# -std=c++20 line (SM 1.13). SM 1.12 sourcepawn is still -std=c++17; that line
# gets the same flag so this shared patcher does not drop it.
sp = sm / 'sourcepawn/AMBuildScript'
if sp.exists():
    sp_text = sp.read_text()
    if 'CSS34 sign-compare' not in sp_text:
        sp_text = sp_text.replace(
            "'-Werror',\n",
            "'-Werror',\n            '-Wno-sign-compare',  # CSS34 sign-compare\n",
            1,
        )
        std_anchors = (
            "cxx.cxxflags += ['-std=c++20']\n",
            "cxx.cxxflags += ['-std=c++17']\n",
        )
        cxx_slice = "".join(sp_text.split("cxx.cxxflags")[1:2])
        if "CSS34 sign-compare" not in cxx_slice:
            anchored = False
            for anchor in std_anchors:
                if anchor in sp_text:
                    sp_text = sp_text.replace(
                        anchor,
                        anchor + "        cxx.cxxflags += ['-Wno-sign-compare']  # CSS34 sign-compare\n",
                        1,
                    )
                    anchored = True
                    break
            if not anchored:
                raise SystemExit(
                    'Failed to anchor sourcepawn -Wno-sign-compare on '
                    '-std=c++20 or -std=c++17'
                )
        if 'CSS34 sign-compare' not in sp_text:
            raise SystemExit('Failed to add sourcepawn -Wno-sign-compare')
        sp.write_text(sp_text)
        print('==> Patched sourcepawn AMBuildScript for sign-compare')
        sp_text = sp.read_text()

    # Force pthread/rt DT_NEEDED (glibc < 2.34 / Debian 11) - bare -lpthread is
    # dropped by --as-needed when nothing in the .o files references it directly.
    # Note: when SourcePawn is built under SourceMod, Configure() is skipped and
    # SM.all_targets is used - so also patch BuildDynamicCoreLib below.
    sp_text = sp.read_text()
    if "'-lgcc_s'" not in sp_text and "cxx.postlink += ['-Wl,--no-as-needed', '-lpthread', '-lrt']" in sp_text:
        sp_text = sp_text.replace(
            "cxx.postlink += ['-Wl,--no-as-needed', '-lpthread', '-lrt']",
            "cxx.postlink += ['-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s']",
        )
        sp.write_text(sp_text)
        print('==> Patched sourcepawn AMBuildScript Configure for pthread/rt/-lgcc_s')
    elif "'-lgcc_s'" not in sp_text and "cxx.postlink += ['-lpthread', '-lrt']" in sp_text:
        sp_text = sp_text.replace(
            "cxx.postlink += ['-lpthread', '-lrt']",
            "cxx.postlink += ['-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s']",
        )
        sp.write_text(sp_text)
        print('==> Patched sourcepawn AMBuildScript Configure for pthread/rt/-lgcc_s')
    else:
        print('==> sourcepawn Configure pthread/rt/-lgcc_s already patched')

    sp_text = sp.read_text()
    if 'css34: AddStaticLibraries lgcc_s' not in sp_text:
        old_add_static = "        if binary.compiler.linker.like('gcc') and binary.compiler.target.platform == 'linux':\n            binary.compiler.linkflags += ['-Wl,--end-group']"
        new_add_static = "        if binary.compiler.target.platform == 'linux':\n            # css34: AddStaticLibraries lgcc_s for 32-bit __mulodi4 in spcomp\n            binary.compiler.linkflags += ['-lgcc', '-lgcc_s', '-Wl,--end-group']"
        if old_add_static in sp_text:
            sp.write_text(sp_text.replace(old_add_static, new_add_static, 1))
            print('==> Patched AddStaticLibraries in sourcepawn for lgcc_s')
            sp_text = sp.read_text()

    # SM 1.13.7461+ builds static libsourcepawn_static only (no shared jit .so).
    # SM 1.12–1.13.7404 may still use BuildDynamicCoreLib → sourcepawn.jit.x86.so.
    dyn_marker = 'css34: libsourcepawn pthread/rt DT_NEEDED'
    if dyn_marker not in sp_text:
        pthread_block = (
            "        # css34: libsourcepawn pthread/rt DT_NEEDED\n"
            "        if binary.compiler.target.platform == 'linux':\n"
            "          for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s'):\n"
            "            if flag not in binary.compiler.linkflags:\n"
            "              binary.compiler.linkflags += [flag]\n"
        )
        dyn_targets = [
            (
                'BuildDynamicCoreLib',
                "    def BuildDynamicCoreLib(self, builder):\n"
                "        cxx = builder.cxx\n"
                "        binary = self.root.Library(builder, 'libsourcepawn')\n\n"
                "        self.SetupBinForArch(binary, builder)\n",
            ),
            (
                'BuildStaticCoreLib',
                "    def BuildStaticCoreLib(self, builder):\n"
                "        cxx = builder.cxx\n"
                "        binary = self.root.StaticLibrary(builder, 'libsourcepawn_static')\n\n"
                "        self.SetupBinForArch(binary, builder)\n",
            ),
        ]
        patched_dyn = False
        for fn, dyn_old in dyn_targets:
            if dyn_old not in sp_text:
                continue
            sp_text = sp_text.replace(dyn_old, dyn_old + pthread_block, 1)
            sp.write_text(sp_text)
            print(f'==> Patched {fn} for pthread/rt DT_NEEDED')
            patched_dyn = True
            sp_text = sp.read_text()
        if not patched_dyn:
            print('==> WARN: BuildDynamicCoreLib/BuildStaticCoreLib pattern not found')
    else:
        print('==> libsourcepawn pthread/rt already patched')

# sourcemod.logic.so must match rom4s link profile (old libstdc++ ABI, pthread/rt
# NEEDED, static embed). SM 1.12 uses `for cxx in builder.targets` - adapt the
# host g++ toolchain, same shape as the SM 1.11 logic patch.
logic_am = sm / 'core/logic/AMBuilder'
if logic_am.exists():
    lt = logic_am.read_text()
    pv_parts = (sm / 'product.version').read_text().strip().split('.')
    sm_minor = int(pv_parts[1]) if len(pv_parts) > 1 else 11
    # SM 1.13.7461+ indexes SP.static_libsp by Target, not arch string.
    uses_sp_target_key = 'SP.static_libsp[target]' in lt
    sp_idx_var = 'target' if uses_sp_target_key else 'arch'
    sp_idx_decl = (
        '    target = binary.compiler.target\n'
        if uses_sp_target_key else
        '    arch = binary.compiler.target.arch\n'
    )
    mimalloc_link = (
        '      SP.mimalloc[target],\n' if uses_sp_target_key else ''
    )
    mimalloc_nested_link = (
        '      SP.mimalloc[target],\n' if uses_sp_target_key else ''
    )
    mimalloc_tail_link = (
        '    SP.mimalloc[target],\n' if uses_sp_target_key else ''
    )
    if 'css34: host g++ logic toolchain' not in lt:
        loop_old = "for cxx in builder.targets:\n  binary = SM.Library(builder, cxx, 'sourcemod.logic')\n"
        # Static SourcePawn on SM 1.13+ needs the host libstdc++ (std::thread).
        sysroot_inc = ""
        logic_toolchain = "host g++"
        loop_new = f"""for cxx in builder.targets:
  if cxx.target.platform == 'linux':
    # css34: host g++ logic toolchain.
    import shutil as _shutil
    import os as _os
    logic_cxx = cxx.clone()
    _cxx_bin = _shutil.which((_os.environ.get('CXX') or 'g++').split()[0]) or (_os.environ.get('CXX') or 'g++').split()[0]
    _cc_bin = _shutil.which((_os.environ.get('CC') or 'gcc').split()[0]) or (_os.environ.get('CC') or 'gcc').split()[0]
    logic_cxx.cxx_argv = [_cxx_bin]
    logic_cxx.cc_argv = [_cc_bin]
    logic_cxx.linker_argv = [_cxx_bin]
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
    ]
    binary = SM.Library(builder, logic_cxx, 'sourcemod.logic')
  else:
    binary = SM.Library(builder, cxx, 'sourcemod.logic')
"""
        if loop_old not in lt:
            raise SystemExit('FAIL: logic AMBuilder for-cxx loop anchor not found')
        else:
            lt = lt.replace(loop_old, loop_new, 1)
            print(f'==> Patched logic AMBuilder ({logic_toolchain})')

    # Defines: no HL2 malloc hooks.
    if 'NO_HOOK_MALLOC' not in lt:
        defs_old = """  binary.compiler.defines += [
    'SM_DEFAULT_THREADER',
    'SM_LOGIC'
  ]"""
        defs_new = """  binary.compiler.defines += [
    'SM_DEFAULT_THREADER',
    'SM_LOGIC',
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
            raise SystemExit('FAIL: logic AMBuilder defines block anchor not found')

    # Linux link: static sysroot/gcc-9 libstdc++ + forced pthread/rt DT_NEEDED.
    if 'css34: host libstdc++ static' not in lt:
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
        # SM 1.12 logic does not link static SourcePawn (SP is not passed into
        # BuildScripts). SM 1.13+ embeds SP.static_libsp into logic.so.
        sp_link = ""
        if sm_minor >= 13:
            sp_link = f"""{sp_idx_decl}    # css34: static SP before libstdc++ for std::thread (libsourcepawn_static)
    binary.compiler.linkflags += [
      SP.static_libsp[{sp_idx_var}],
      SP.libamtl[{sp_idx_var}],
      SP.zlib[{sp_idx_var}],
{mimalloc_link}    ]
"""
        # Every line: logic.so must not export static libstdc++ / sourcepawn symbols.
        exclude_libs = """    # css34: hide static archive symbols from the dynamic export table
    if '-Wl,--exclude-libs,ALL' not in binary.compiler.linkflags:
      binary.compiler.linkflags += ['-Wl,--exclude-libs,ALL']
    # css34: template instantiations in .o files ignore --exclude-libs; export only the C API.
    _vs = _os.path.join(_os.environ.get('WDIR', ''), 'builder', 'patches', 'sourcemod-logic.version')
    if not _os.path.isfile(_vs):
      raise Exception('logic version script missing: ' + _vs)
    if '-Wl,--version-script,' + _vs not in binary.compiler.linkflags:
      binary.compiler.linkflags += ['-Wl,--version-script,' + _vs]
"""
        linux_new = f"""  if binary.compiler.target.platform == 'linux':
    # css34: host libstdc++ static.
    import os as _os
    for flag in ('-static-libstdc++', '-lgcc_eh', '-lstdc++', '-nodefaultlibs'):
      if flag in binary.compiler.linkflags:
        binary.compiler.linkflags.remove(flag)
    for flag in list(binary.compiler.postlink):
      if flag in ('-lpthread', '-lrt', '-Wl,--no-as-needed'):
        binary.compiler.postlink.remove(flag)
    _stdcxx = None
    _sup = None
    if _stdcxx is None:
      import subprocess as _sp
      _cxx = (_os.environ.get('CXX') or 'g++').split()[0]
      _printed = _sp.check_output([_cxx, '-print-file-name=libstdc++.a'], universal_newlines=True).strip()
      if _printed and _printed != 'libstdc++.a' and _os.path.isfile(_printed):
        _stdcxx = _printed
        _sup = _os.path.join(_os.path.dirname(_printed), 'libsupc++.a')
        if not _os.path.isfile(_sup):
          _sup_printed = _sp.check_output([_cxx, '-print-file-name=libsupc++.a'], universal_newlines=True).strip()
          if _sup_printed and _os.path.isfile(_sup_printed):
            _sup = _sup_printed
    if _stdcxx is None:
      raise Exception('logic libstdc++.a not found (%s -print-file-name=libstdc++.a)' % ((_os.environ.get('CXX') or 'g++').split()[0]))
    _gcc = _os.path.join(_os.path.dirname(_stdcxx), 'libgcc.a')
    _gcc_eh = _os.path.join(_os.path.dirname(_stdcxx), 'libgcc_eh.a')
    for flag in ('-static-libgcc',):
      if flag in binary.compiler.linkflags:
        binary.compiler.linkflags.remove(flag)
{sp_link}    _static = ['-nodefaultlibs', '-Wl,-Bstatic', _stdcxx]
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
{exclude_libs}  elif binary.compiler.target.platform == 'mac':"""
        replaced = False
        for linux_old in linux_old_variants:
            if linux_old in lt:
                lt = lt.replace(linux_old, linux_new, 1)
                replaced = True
                print('==> Patched logic AMBuilder linux static libstdc++ + pthread/rt')
                break
        if not replaced:
            raise SystemExit('FAIL: logic linux postlink anchor not found for static link patch')
    else:
        print('==> logic AMBuilder static libstdc++ already patched')

    # SM 1.13+: static SourcePawn was appended after libstdc++.a; reorder so std::thread resolves.
    # SM 1.12 has no SP in logic AMBuilder / BuildScripts — skip entirely.
    if sm_minor >= 13:
        if 'css34: static SP before libstdc++ for std::thread' not in lt:
            sp_before_old = """    for flag in ('-static-libgcc',):
      if flag in binary.compiler.linkflags:
        binary.compiler.linkflags.remove(flag)
    _static = ['-nodefaultlibs', '-Wl,-Bstatic', _stdcxx]
    if _sup and _os.path.isfile(_sup):
      _static.append(_sup)
    if _os.path.isfile(_gcc_eh):"""
            sp_before_new = f"""{sp_idx_decl}    # css34: static SP before libstdc++ for std::thread (libsourcepawn_static)
    binary.compiler.linkflags += [
      SP.static_libsp[{sp_idx_var}],
      SP.libamtl[{sp_idx_var}],
      SP.zlib[{sp_idx_var}],
{mimalloc_link}    ]
    for flag in ('-static-libgcc',):
      if flag in binary.compiler.linkflags:
        binary.compiler.linkflags.remove(flag)
    _static = ['-nodefaultlibs', '-Wl,-Bstatic', _stdcxx]
    if _sup and _os.path.isfile(_sup):
      _static.append(_sup)
    if _os.path.isfile(_gcc_eh):"""
            sp_before_old_wa = """    for flag in ('-static-libgcc',):
      if flag in binary.compiler.linkflags:
        binary.compiler.linkflags.remove(flag)
    _static = ['-nodefaultlibs', '-Wl,-Bstatic', '-Wl,--whole-archive', _stdcxx]
    if _sup and _os.path.isfile(_sup):
      _static.append(_sup)
    _static.append('-Wl,-no-whole-archive')  # css34: static SP needs full libstdc++ (std::thread)
    if _os.path.isfile(_gcc_eh):"""
            if sp_before_old_wa in lt:
                lt = lt.replace(sp_before_old_wa, sp_before_new, 1)
                print('==> Reordered logic AMBuilder: static SP before libstdc++ (std::thread)')
            elif sp_before_old in lt:
                lt = lt.replace(sp_before_old, sp_before_new, 1)
                print('==> Reordered logic AMBuilder: static SP before libstdc++ (std::thread)')

        if 'css34: skip duplicate logic static SP on linux' not in lt:
            sp_tail_old = f"""  {sp_idx_var} = binary.compiler.target{'.arch' if sp_idx_var == 'arch' else ''}
  binary.compiler.linkflags += [
    SP.static_libsp[{sp_idx_var}],
    SP.libamtl[{sp_idx_var}],
    SP.zlib[{sp_idx_var}],
{mimalloc_tail_link}  ]
  if binary.compiler.target.platform == 'linux':"""
            sp_tail_new = f"""  {sp_idx_var} = binary.compiler.target{'.arch' if sp_idx_var == 'arch' else ''}
  # css34: skip duplicate logic static SP on linux (linked inside linux block above)
  if binary.compiler.target.platform != 'linux':
    binary.compiler.linkflags += [
      SP.static_libsp[{sp_idx_var}],
      SP.libamtl[{sp_idx_var}],
      SP.zlib[{sp_idx_var}],
{mimalloc_nested_link}    ]
  if binary.compiler.target.platform == 'linux':"""
            if sp_tail_old in lt:
                lt = lt.replace(sp_tail_old, sp_tail_new, 1)
                print('==> logic AMBuilder: skip duplicate static SP on linux')
            elif uses_sp_target_key:
                sp_tail_after_mac = f"""  elif binary.compiler.target.platform == 'mac':
    binary.compiler.cflags += ['-Wno-deprecated-declarations']
    binary.compiler.postlink += ['-framework', 'CoreServices', '-lm']

  {sp_idx_var} = binary.compiler.target
  binary.compiler.linkflags += [
    SP.static_libsp[{sp_idx_var}],
    SP.libamtl[{sp_idx_var}],
    SP.zlib[{sp_idx_var}],
{mimalloc_tail_link}  ]

  if binary.compiler.family == 'gcc' or binary.compiler.family == 'clang':"""
                sp_tail_after_mac_new = f"""  elif binary.compiler.target.platform == 'mac':
    binary.compiler.cflags += ['-Wno-deprecated-declarations']
    binary.compiler.postlink += ['-framework', 'CoreServices', '-lm']

  {sp_idx_var} = binary.compiler.target
  # css34: skip duplicate logic static SP on linux (linked inside linux block above)
  if binary.compiler.target.platform != 'linux':
    binary.compiler.linkflags += [
      SP.static_libsp[{sp_idx_var}],
      SP.libamtl[{sp_idx_var}],
      SP.zlib[{sp_idx_var}],
{mimalloc_nested_link}    ]

  if binary.compiler.family == 'gcc' or binary.compiler.family == 'clang':"""
                if sp_tail_after_mac in lt:
                    lt = lt.replace(sp_tail_after_mac, sp_tail_after_mac_new, 1)
                    print('==> logic AMBuilder: skip duplicate static SP on linux (7461 layout)')

    if sm_minor >= 13 and 'css34: logic postlink pthread after static SP' not in lt:
        sp_libs_anchor = f"""  {sp_idx_var} = binary.compiler.target{'.arch' if sp_idx_var == 'arch' else ''}
  binary.compiler.linkflags += [
    SP.static_libsp[{sp_idx_var}],
    SP.libamtl[{sp_idx_var}],
    SP.zlib[{sp_idx_var}],
{mimalloc_tail_link}  ]"""
        sp_libs_new = f"""  {sp_idx_var} = binary.compiler.target{'.arch' if sp_idx_var == 'arch' else ''}
  if binary.compiler.target.platform != 'linux':
    binary.compiler.linkflags += [
      SP.static_libsp[{sp_idx_var}],
      SP.libamtl[{sp_idx_var}],
      SP.zlib[{sp_idx_var}],
{mimalloc_nested_link}    ]
  if binary.compiler.target.platform == 'linux':
    # css34: logic postlink pthread after static SP archives (DT_NEEDED on glibc < 2.34)
    for flag in list(binary.compiler.linkflags):
      if flag in ('-lpthread', '-lrt', '-Wl,--no-as-needed'):
        binary.compiler.linkflags.remove(flag)
    for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt'):
      if flag not in binary.compiler.postlink:
        binary.compiler.postlink += [flag]
"""
        sp_libs_anchor_linux = f"""  {sp_idx_var} = binary.compiler.target{'.arch' if sp_idx_var == 'arch' else ''}
  # css34: skip duplicate logic static SP on linux (linked inside linux block above)
  if binary.compiler.target.platform != 'linux':
    binary.compiler.linkflags += [
      SP.static_libsp[{sp_idx_var}],
      SP.libamtl[{sp_idx_var}],
      SP.zlib[{sp_idx_var}],
{mimalloc_nested_link}    ]"""
        if sp_libs_anchor_linux in lt:
            if 'binary.compiler.postlink += [flag]' not in lt:
                lt = lt.replace(
                    sp_libs_anchor_linux,
                    sp_libs_anchor_linux + """
    # css34: logic postlink pthread after static SP archives (DT_NEEDED on glibc < 2.34)
    for flag in list(binary.compiler.linkflags):
      if flag in ('-lpthread', '-lrt', '-Wl,--no-as-needed'):
        binary.compiler.linkflags.remove(flag)
    for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt'):
      if flag not in binary.compiler.postlink:
        binary.compiler.postlink += [flag]
""",
                    1,
                )
                print('==> Patched logic AMBuilder postlink pthread after static SP')
        elif sp_libs_anchor not in lt:
            print('==> WARN: logic AMBuilder SP static libs anchor not found')
        else:
            lt = lt.replace(sp_libs_anchor, sp_libs_new, 1)
            print('==> Patched logic AMBuilder postlink pthread after static SP')
    elif sm_minor < 13:
        print('==> SM < 1.13: skipping static SourcePawn logic link reorder')

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

# bundled curl fortify noise on gcc only
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

# css34: lines.json SOURCEMOD_GIT_REV (do not trust a shallow rev-list count).
"${PY[@]}" "$script_dir/pin-generate-headers.py" \
  "$sourcemod_dir/tools/buildbot/generate_headers.py" \
  --env SOURCEMOD_GIT_REV

# --- Safe GET_V_IFACE macros in sourcemm_api.cpp ---
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYIFACE'
from pathlib import Path
import os
sm_api = Path(os.environ['SOURCEMOD_DIR']) / 'core/sourcemm_api.cpp'
if sm_api.exists():
    text = sm_api.read_text()
    if 'CSS34_SAFE_GET_V_IFACE' not in text:
        macro_patch = """/* CSS34_SAFE_GET_V_IFACE: null factory guard */
#undef GET_V_IFACE_ANY
#define GET_V_IFACE_ANY(v_factory, v_var, v_type, v_name) \
	do { \
		CreateInterfaceFn _fn = ismm->v_factory(); \
		if (!_fn) \
		{ \
			if (error && maxlen) \
				ke::SafeSprintf(error, maxlen, "Factory %s returned NULL for %s", #v_factory, v_name); \
			return false; \
		} \
		v_var = (v_type *)ismm->VInterfaceMatch(_fn, v_name, 0); \
		if (!v_var) \
		{ \
			if (error && maxlen) \
				ke::SafeSprintf(error, maxlen, "Could not find interface: %s", v_name); \
			return false; \
		} \
	} while (0)

#undef GET_V_IFACE_CURRENT
#define GET_V_IFACE_CURRENT(v_factory, v_var, v_type, v_name) \
	do { \
		CreateInterfaceFn _fn = ismm->v_factory(); \
		if (!_fn) \
		{ \
			if (error && maxlen) \
				ke::SafeSprintf(error, maxlen, "Factory %s returned NULL for %s", #v_factory, v_name); \
			return false; \
		} \
		v_var = (v_type *)ismm->VInterfaceMatch(_fn, v_name); \
		if (!v_var) \
		{ \
			if (error && maxlen) \
				ke::SafeSprintf(error, maxlen, "Could not find interface: %s", v_name); \
			return false; \
		} \
	} while (0)

bool SourceMod_Core::Load"""
        text = text.replace('bool SourceMod_Core::Load', macro_patch, 1)
        sm_api.write_text(text)
        print('==> Patched GET_V_IFACE macros in core/sourcemm_api.cpp')
PYIFACE

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

# Boot traces are a local diagnostic aid and must never enter release packages.
if [[ "${CSS34_DEBUG_TRACE:-0}" == "1" ]]; then
  bash "$script_dir/apply-sm-boot-trace.sh" "$sourcemod_dir"
fi

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

# Every Linux module links libstdc++ statically and hides it. --exclude-libs,ALL
# stays on logic.so and non-SDK extensions only.
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYHIDE'
from pathlib import Path
import os
path = Path(os.environ['SOURCEMOD_DIR']) / 'AMBuildScript'
text = path.read_text()
marker = 'css34: hide static libstdc++'
if marker in text:
    print('==> static libstdc++ hide flags already present')
else:
    old_sm13 = "    cxx.linkflags += ['-static-libstdc++']\n    cxx.linkflags += ['-Wl,--exclude-libs=libstdc++.a']\n"
    old = "    cxx.linkflags += ['-static-libstdc++']\n"
    new = "    cxx.linkflags += ['-static-libstdc++', '-Wl,--exclude-libs=libstdc++.a:libsupc++.a']  # css34: hide static libstdc++\n"
    if old_sm13 in text:
        text = text.replace(old_sm13, new, 1)
    elif old in text:
        text = text.replace(old, new, 1)
    else:
        raise SystemExit('FAIL: static-libstdc++ linkflags anchor not found in AMBuildScript')
    path.write_text(text)
    print('==> Patched AMBuildScript to hide static libstdc++')
PYHIDE

SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYGCC'
from pathlib import Path
import os
path = Path(os.environ['SOURCEMOD_DIR']) / 'AMBuildScript'
text = path.read_text()
old_gcc = """    if cxx.family == 'gcc':
      cxx.linkflags += ['-static-libgcc']
"""
new_gcc = """    if cxx.family == 'gcc':
      cxx.linkflags += ['-lgcc_s']  # css34: libgcc_s stays dynamic
"""
if 'css34: libgcc_s stays dynamic' in text:
    print('==> configure_linux already keeps libgcc_s dynamic')
elif old_gcc not in text:
    raise SystemExit('FAIL: configure_linux -static-libgcc anchor not found')
else:
    path.write_text(text.replace(old_gcc, new_gcc, 1))
    print('==> Patched configure_linux to keep libgcc_s dynamic')
PYGCC

echo "==> SourceMod 1.12+ css34 patches applied (Metamod 1.12 / 2.ep1)"
