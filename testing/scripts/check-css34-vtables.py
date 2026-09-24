#!/usr/bin/env python3
"""Check css34 SDKTools / SDKHooks gamedata vtable offsets against server_i486.so.

Usage: check-css34-vtables.py <server_i486.so> <gamedata dir> [--dump CLASS]

Reads the CCSPlayer (and CWeaponCSBase) vtables straight from the v34 server
binary, which still ships symbols, and verifies every "linux" offset in
sdktools.games/game.cstrike.txt and sdkhooks.games/game.cstrike.txt whose
method is virtual on v34. Offsets for methods that are not virtual on v34
(e.g. GetMaxHealth) are reported as failures because SM would hook or call an
unrelated slot. Pure python3 stdlib (no pyelftools) so it runs on CI hosts.
"""
import re
import struct
import subprocess
import sys

# gamedata key -> (vtable symbol, C++ method name)
CHECKS = {
    'sdktools.games/game.cstrike.txt': {
        'SetOwnerEntity': ('_ZTV9CCSPlayer', 'SetOwnerEntity'),
        'GiveNamedItem': ('_ZTV9CCSPlayer', 'GiveNamedItem'),
        'RemovePlayerItem': ('_ZTV9CCSPlayer', 'RemovePlayerItem'),
        'Weapon_GetSlot': ('_ZTV9CCSPlayer', 'Weapon_GetSlot'),
        'Ignite': ('_ZTV9CCSPlayer', 'Ignite'),
        'Extinguish': ('_ZTV9CCSPlayer', 'Extinguish'),
        'Teleport': ('_ZTV9CCSPlayer', 'Teleport'),
        'CommitSuicide': ('_ZTV9CCSPlayer', 'CommitSuicide'),
        'GetVelocity': ('_ZTV9CCSPlayer', 'GetVelocity'),
        'EyeAngles': ('_ZTV9CCSPlayer', 'EyeAngles'),
        'AcceptInput': ('_ZTV9CCSPlayer', 'AcceptInput'),
        'DispatchKeyValue': ('_ZTV9CCSPlayer', 'KeyValue(char const*, char const*)'),
        'DispatchKeyValueFloat': ('_ZTV9CCSPlayer', 'KeyValue(char const*, float)'),
        'DispatchKeyValueVector': ('_ZTV9CCSPlayer', 'KeyValue(char const*, Vector)'),
        'SetEntityModel': ('_ZTV9CCSPlayer', 'SetModel'),
        'WeaponEquip': ('_ZTV9CCSPlayer', 'Weapon_Equip'),
        'Activate': ('_ZTV9CCSPlayer', 'Activate'),
        'PlayerRunCmd': ('_ZTV9CCSPlayer', 'PlayerRunCommand'),
        'GiveAmmo': ('_ZTV9CCSPlayer', 'GiveAmmo'),
        'GetAttachment': ('_ZTV9CCSPlayer', 'GetAttachment(int, matrix3x4_t&)'),
    },
    'sdkhooks.games/game.cstrike.txt': {
        'Blocked': ('_ZTV9CCSPlayer', 'Blocked'),
        'EndTouch': ('_ZTV9CCSPlayer', 'EndTouch'),
        'FireBullets': ('_ZTV9CCSPlayer', 'FireBullets'),
        'GetMaxHealth': ('_ZTV9CCSPlayer', 'GetMaxHealth'),
        'GroundEntChanged': ('_ZTV9CCSPlayer', 'NetworkStateChanged_m_hGroundEntity'),
        'OnTakeDamage': ('_ZTV9CCSPlayer', 'OnTakeDamage'),
        'OnTakeDamage_Alive': ('_ZTV9CCSPlayer', 'OnTakeDamage_Alive'),
        'PreThink': ('_ZTV9CCSPlayer', 'PreThink'),
        'PostThink': ('_ZTV9CCSPlayer', 'PostThink'),
        'Reload': ('_ZTV13CWeaponCSBase', 'Reload'),
        'SetTransmit': ('_ZTV9CCSPlayer', 'SetTransmit'),
        'ShouldCollide': ('_ZTV9CCSPlayer', 'ShouldCollide'),
        'Spawn': ('_ZTV9CCSPlayer', 'Spawn'),
        'StartTouch': ('_ZTV9CCSPlayer', 'StartTouch'),
        'Think': ('_ZTV9CCSPlayer', 'Think'),
        'Touch': ('_ZTV9CCSPlayer', 'Touch'),
        'TraceAttack': ('_ZTV9CCSPlayer', 'TraceAttack'),
        'Use': ('_ZTV9CCSPlayer', 'Use'),
        'VPhysicsUpdate': ('_ZTV9CCSPlayer', 'VPhysicsUpdate'),
        'Weapon_CanSwitchTo': ('_ZTV9CCSPlayer', 'Weapon_CanSwitchTo'),
        'Weapon_CanUse': ('_ZTV9CCSPlayer', 'Weapon_CanUse'),
        'Weapon_Drop': ('_ZTV9CCSPlayer', 'Weapon_Drop'),
        'Weapon_Equip': ('_ZTV9CCSPlayer', 'Weapon_Equip'),
        'Weapon_Switch': ('_ZTV9CCSPlayer', 'Weapon_Switch'),
    },
}


class Elf32:
    def __init__(self, path):
        self.data = open(path, 'rb').read()
        d = self.data
        if d[:4] != b'\x7fELF' or d[4] != 1:
            raise SystemExit(f'{path}: not a 32-bit ELF')
        (self.shoff,) = struct.unpack_from('<I', d, 0x20)
        self.shentsize, self.shnum, self.shstrndx = struct.unpack_from('<HHH', d, 0x2E)
        (phoff,) = struct.unpack_from('<I', d, 0x1C)
        phentsize, phnum = struct.unpack_from('<HH', d, 0x2A)
        self.sections = [self._sh(i) for i in range(self.shnum)]
        self.loads = []
        for i in range(phnum):
            p_type, p_offset, p_vaddr, _, p_filesz = struct.unpack_from('<IIIII', d, phoff + i * phentsize)
            if p_type == 1:
                self.loads.append((p_vaddr, p_offset, p_filesz))

    def _sh(self, i):
        f = struct.unpack_from('<IIIIIIIIII', self.data, self.shoff + i * self.shentsize)
        return dict(name=f[0], type=f[1], addr=f[3], offset=f[4], size=f[5], link=f[6], entsize=f[9])

    def strz(self, off):
        end = self.data.index(b'\0', off)
        return self.data[off:end].decode('latin-1')

    def symbols(self, sec):
        strtab = self.sections[sec['link']]['offset']
        out = []
        for i in range(sec['size'] // 16):
            name, value, size, info, _, _ = struct.unpack_from('<IIIBBH', self.data, sec['offset'] + i * 16)
            out.append((self.strz(strtab + name) if name else '', value, size, info & 0xF))
        return out

    def read(self, va, n):
        for vaddr, off, filesz in self.loads:
            if vaddr <= va and va + n <= vaddr + filesz:
                return self.data[off + va - vaddr: off + va - vaddr + n]
        raise ValueError(f'address {va:#x} not in a PT_LOAD segment')


def load_vtables(path, wanted):
    elf = Elf32(path)
    syms, funcs, symtabs = {}, {}, {}
    for idx, sec in enumerate(elf.sections):
        if sec['type'] in (2, 11):  # SYMTAB, DYNSYM
            table = elf.symbols(sec)
            symtabs[idx] = table
            for name, value, size, typ in table:
                if name:
                    syms.setdefault(name, (value, size))
                    if typ == 2 and value:
                        funcs.setdefault(value, name)
    relocs = {}
    for sec in elf.sections:
        if sec['type'] == 9:  # REL
            table = symtabs.get(sec['link'], [])
            for i in range(sec['size'] // 8):
                r_off, r_info = struct.unpack_from('<II', elf.data, sec['offset'] + i * 8)
                symidx = r_info >> 8
                if symidx and symidx < len(table):
                    relocs[r_off] = table[symidx][0]
    mangled = {}
    for vt in wanted:
        if vt not in syms:
            raise SystemExit(f'{path}: vtable symbol {vt} not found')
        addr, size = syms[vt]
        raw = elf.read(addr, size)
        entries = []
        for i in range(size // 4):
            (val,) = struct.unpack_from('<I', raw, i * 4)
            entries.append(relocs.get(addr + i * 4) or funcs.get(val, ''))
        mangled[vt] = entries[2:]  # skip offset-to-top + typeinfo
    flat = [n for v in mangled.values() for n in v]
    demangled = subprocess.run(['c++filt'], input='\n'.join(flat), capture_output=True, text=True).stdout.split('\n')
    out, pos = {}, 0
    for vt, entries in mangled.items():
        out[vt] = demangled[pos:pos + len(entries)]
        pos += len(entries)
    return out


def gamedata_offsets(path):
    text = open(path, encoding='latin-1').read()
    offsets = {}
    block = re.search(r'"Offsets"\s*\{(.*?)\n\t\t\}', text, re.S)
    if not block:
        return offsets
    for key, body in re.findall(r'"(\w+)"\s*\{([^{}]*)\}', block.group(1)):
        kv = dict(re.findall(r'"([^"]+)"\s*"([^"]*)"', body))
        if kv.get('linux', '').isdigit():
            offsets[key] = int(kv['linux'])
    return offsets


def main():
    args = sys.argv[1:]
    if len(args) >= 3 and args[1] == '--dump':
        vt = args[2]
        for i, n in enumerate(load_vtables(args[0], [vt])[vt]):
            print(i, n)
        return 0
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    server_so, gamedata = args
    vtables = load_vtables(server_so, {vt for f in CHECKS.values() for vt, _ in f.values()})
    failures = 0
    for rel, checks in CHECKS.items():
        offsets = gamedata_offsets(f'{gamedata}/{rel}')
        for key, (vt, method) in checks.items():
            if key not in offsets:
                continue
            pat = re.compile(r'::' + re.escape(method) + ('' if '(' in method else r'\('))
            slots = [i for i, n in enumerate(vtables[vt]) if pat.search(n)]
            got = offsets[key]
            if got in slots:
                print(f'OK: {rel} {key} linux={got}')
            elif not slots:
                print(f'FAIL: {rel} {key} linux={got}: {method} is not virtual on v34 (slot {got} is {vtables[vt][got] if got < len(vtables[vt]) else "out of range"})')
                failures += 1
            else:
                print(f'FAIL: {rel} {key} linux={got}, v34 vtable slot is {slots} ({vtables[vt][slots[0]]})')
                failures += 1
    if failures:
        print(f'css34 vtable check FAILED ({failures})')
        return 1
    print('css34 vtable check PASSED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
