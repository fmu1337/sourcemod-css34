#!/usr/bin/env bash
# KHook (Metamod 2.0 third_party/khook) recall fixes for Windows x86 (MSVC).
#
# A KHook::Recall re-enters the detour from a hook callback. On x86 the
# detour then:
#  - copies every register of the recall entry over the ones saved at the
#    original entry (BeginDetour), so the hooked function's caller gets the
#    callback's EBX / ESI / EDI back when the detour finally returns;
#  - returns to the recall site with a plain `ret` and with the registers
#    saved for the hooked call. MSVC __thiscall expects the callee to pop the
#    stack arguments, so ESP is off by their size and the recall site's
#    epilogue pops arguments into EBX / ESI / EDI (SourceMod's LevelInit hook
#    crashed srcds.exe on the first map load).
# GCC / Clang i386 member calls are caller-cleaned and the Linux build works,
# so only _WIN32 x86 changes:
#  - BeginDetour keeps the original entry's EBX / ESI / EDI (copies EAX / ECX
#    / EDX, which may carry parameters);
#  - KHook::Recall saves ESP / EBX / ESI / EDI around the recall call.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

khook_dir="${1:?khook directory required}"
if [[ ! -f "$khook_dir/src/detour.cpp" || ! -f "$khook_dir/include/khook.hpp" ]]; then
  echo "==> No KHook sources in $khook_dir; skipping KHook recall patch"
  exit 0
fi

KHOOK_DIR="$khook_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

root = Path(os.environ['KHOOK_DIR'])

def patch(rel, marker, old, new, what):
    path = root / rel
    data = path.read_bytes().decode('utf-8')
    crlf = '\r\n' in data
    text = data.replace('\r\n', '\n')
    if marker in text:
        print(f'==> KHook {what} already patched')
        return
    if text.count(old) != 1:
        raise SystemExit(f'KHook {what}: anchor not found in {rel}')
    text = text.replace(old, new)
    if crlf:
        text = text.replace('\n', '\r\n')
    path.write_bytes(text.encode('utf-8'))
    print(f'==> KHook {what} patched')

patch('src/detour.cpp', 'css34: keep the original entry',
'''		// Copy the registers
		memcpy(reinterpret_cast<void*>(loop->sp_saved_registers), reinterpret_cast<void*>(rsp_regs), regs_size);''',
'''		// Copy the registers
#if !defined(KHOOK_X64) && defined(_WIN32)
		// css34: keep the original entry's EBX / ESI / EDI (callee-saved, the
		// hooked function's caller gets them back), take EAX / ECX / EDX
		static_assert(reg_count == 8);
		memcpy(reinterpret_cast<void*>(loop->sp_saved_registers), reinterpret_cast<void*>(rsp_regs), sizeof(void*) * 5);
#else
		memcpy(reinterpret_cast<void*>(loop->sp_saved_registers), reinterpret_cast<void*>(rsp_regs), regs_size);
#endif''',
'BeginDetour recall registers (win32 x86)')

patch('include/khook.hpp', 'css34: KHook returns from a recall',
'''template<typename F, typename CLASS, typename ...ARGS>
inline void __MFP__Recall(void* addr, F f, CLASS&& this_ptr, ARGS&&... args) {
	F dummy_func = nullptr;
	::KHook::FillMFP(&dummy_func, addr);
	(this_ptr->*dummy_func)(std::forward<ARGS>(args)...);
}''',
'''#if defined(_MSC_VER) && defined(_M_IX86)
// css34: KHook returns from a recall with a plain `ret` (a __thiscall callee
// pops its stack arguments) and with the hooked call's EBX / ESI / EDI
#define KHOOK_CSS34_RECALL_SAVE \\
	std::uintptr_t css34_esp, css34_ebx, css34_esi, css34_edi; \\
	__asm { mov css34_esp, esp } \\
	__asm { mov css34_ebx, ebx } \\
	__asm { mov css34_esi, esi } \\
	__asm { mov css34_edi, edi }
#define KHOOK_CSS34_RECALL_RESTORE \\
	__asm { mov esp, css34_esp } \\
	__asm { mov ebx, css34_ebx } \\
	__asm { mov esi, css34_esi } \\
	__asm { mov edi, css34_edi }
#else
#define KHOOK_CSS34_RECALL_SAVE
#define KHOOK_CSS34_RECALL_RESTORE
#endif

template<typename F, typename CLASS, typename ...ARGS>
inline void __MFP__Recall(void* addr, F f, CLASS&& this_ptr, ARGS&&... args) {
	F dummy_func = nullptr;
	::KHook::FillMFP(&dummy_func, addr);
	KHOOK_CSS34_RECALL_SAVE
	(this_ptr->*dummy_func)(std::forward<ARGS>(args)...);
	KHOOK_CSS34_RECALL_RESTORE
}''',
'Recall register / stack restore (MSVC x86)')

patch('include/khook.hpp', 'css34: free-function recall',
'''		F function = (decltype(f))addr;
		(*function)(std::forward<ARGS>(args)...);''',
'''		F function = (decltype(f))addr;
		// css34: free-function recall, same restore as __MFP__Recall
		KHOOK_CSS34_RECALL_SAVE
		(*function)(std::forward<ARGS>(args)...);
		KHOOK_CSS34_RECALL_RESTORE''',
'free-function Recall restore (MSVC x86)')
PY
