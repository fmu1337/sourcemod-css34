#!/usr/bin/env python3
"""Validate the complete, self-contained CS:S v34 gamedata contract.

With --source, also reject new direct gamedata lookups in the SourceMod core
and built-in extensions until they are either supplied by this v34 contract or
explicitly classified as unavailable on the legacy engine.

With --allow-custom, <name>.games/custom/*.txt files are SourceMod gamedata
overrides (CGameConfig::Reparse reads them after the shipped files and their
keys replace the shipped values): they are not "unexpected" files, and the
required and forbidden entries are checked on the shipped file plus the
overrides of its directory. Only a frozen line's hotfix (hotfixes/<line>/,
docs/MAINTAINING.md) adds such files; packages never ship them.
"""

from pathlib import Path
import re
import sys


FILES = {
    'core.games/blacklist.plugins.txt',
    'core.games/common.games.txt',
    'core.games/engine.ep1.txt',
    'core.games/master.games.txt',
    'funcommands.games.txt',
    'sdkhooks.games/common.games.txt',
    'sdkhooks.games/game.cstrike.txt',
    'sdkhooks.games/master.games.txt',
    'sdktools.games/common.games.txt',
    'sdktools.games/engine.ep1.txt',
    'sdktools.games/game.cstrike.txt',
    'sdktools.games/master.games.txt',
    'sm-cstrike.games/game.cstrike.txt',
    'sm-cstrike.games/master.games.txt',
}

REQUIRED = {
    'core.games/common.games.txt': (
        '"GetDataDescMap"', '"HudRadioMenuMsg"', '"HudTextMsg"',
        '"GameExtension"', '"MenuItemSound"', '"m_lifeState"',
    ),
    'core.games/master.games.txt': (
        '"common.games.txt"', '"engine.ep1.txt"', '"engine"\t"original"',
    ),
    'sdkhooks.games/master.games.txt': ('"common.games.txt"', '"game.cstrike.txt"'),
    'sdktools.games/common.games.txt': (
        '"m_iFrags"', '"m_iScore"', '"m_iHealth"', '"m_lifeState"',
    ),
    'sdktools.games/master.games.txt': (
        '"common.games.txt"', '"engine.ep1.txt"', '"game.cstrike.txt"',
        '"engine"\t"original"', '"game"\t\t"cstrike"',
    ),
    'funcommands.games.txt': (
        '"SpriteBeam"', '"SoundBlip"', '"SoundFreeze"',
        '"TeamUnknownBeaconColor"',
    ),
}

# These SDKHooks entries were present in the historical 1.12.0.7245 package,
# but do not describe the CSS v34 server vtable.  VPhysicsUpdate slot 131 is
# GetAttackDamageScale on v34; GetMaxHealth is non-virtual and therefore must
# not be used as a vtable offset (CCSPlayer slot 107, the old offset, is
# CBaseEntity::NetworkStateChanged_m_iMaxHealth(); docs/CHANGES.md).
REQUIRED_PATTERNS = {
    # The v34 client expects a leading byte in HintText (SM 1.7.3, rom4s 1.11);
    # core reads this key only from the "cstrike" section.
    'core.games/common.games.txt': (
        r'"cstrike"\s*\{\s*"Keys"\s*\{[^}]*"HintTextPreByte"\s*"yes"',
    ),
    'sdkhooks.games/game.cstrike.txt': (
        r'"VPhysicsUpdate"\s*\{[^}]*"windows"\s*"142"[^}]*"linux"\s*"143"',
    ),
}

FORBIDDEN = {
    'sdkhooks.games/game.cstrike.txt': ('"GetMaxHealth"',),
}

# These names are looked up conditionally or in CS:GO-only code. Keeping this
# list explicit prevents an upstream addition from silently inheriting a
# current-engine entry through the package build.
UNSUPPORTED_SOURCE_KEYS = {
    'CCSPlayerInventoryOffset',
    'ChatSayText',
    'ClanTagOffset',
    'EntInfosPtr',
    'EntityFactoryCallOffset',
    'EntityFactoryCaller',
    'EntityFactoryFinder',
    'EntityFactoryOffset',
    'EntityListenersPtr',
    'GetItemDefintionByName',
    'GetItemInLoadout',
    'ItemDefHashOffset',
    'LoadoutSlotOffset',
    'MTUPatchSize',
    'MaxMTU',
    'PriceKey',
    'RadioMenuClosesOnInvalidSlot',
    'RadioMenuMaxPageItems',
    'ResourceEntityClassname',
    'SetClanTag',
    'Weapon_',
    # CSGO/Blade/MCV string-table workaround; the KHook line retains this
    # lookup even though the CSS v34 package cannot use the detour.
    'WriteBaselines',
}

LOOKUP = re.compile(r'Get(?:KeyValue|Offset|MemSig|Address)\("([^"]+)"')
SOURCE_DIRS = ('core', 'extensions/sdktools', 'extensions/sdkhooks', 'extensions/cstrike')


def source_keys(source: Path) -> set[str]:
    keys = set()
    for rel in SOURCE_DIRS:
        directory = source / rel
        if not directory.is_dir():
            raise ValueError(f'missing SourceMod source directory: {directory}')
        for path in directory.rglob('*'):
            if path.suffix in ('.cpp', '.h'):
                keys.update(LOOKUP.findall(path.read_text(encoding='latin-1')))
    return keys


CUSTOM = re.compile(r'^(?:[^/]+\.games/)?custom/[^/]+\.txt$')


def custom_overrides(root: Path, rel: str, actual: set[str]) -> list[str]:
    """Override files SourceMod parses after <rel>: <rel's dir>/custom/*.txt."""
    parent = rel.rsplit('/', 1)[0] + '/' if '/' in rel else ''
    return sorted(name for name in actual
                  if CUSTOM.match(name) and name.startswith(parent + 'custom/'))


def effective_text(root: Path, rel: str, overrides: list[str]) -> str:
    texts = [(root / rel).read_text(encoding='latin-1')]
    texts += [(root / name).read_text(encoding='latin-1') for name in overrides]
    return '\n'.join(texts)


def main() -> int:
    usage = f'usage: {Path(sys.argv[0]).name} <gamedata-dir> [--source <sourcemod-dir>] [--allow-custom]'
    args = sys.argv[1:]
    allow_custom = '--allow-custom' in args
    args = [arg for arg in args if arg != '--allow-custom']
    if len(args) not in (1, 3) or (len(args) == 3 and args[1] != '--source'):
        print(usage, file=sys.stderr)
        return 2
    root = Path(args[0])
    actual = {path.relative_to(root).as_posix() for path in root.rglob('*') if path.is_file()}
    custom = {name for name in actual if CUSTOM.match(name)} if allow_custom else set()
    if custom:
        print('OK: custom gamedata overrides: ' + ', '.join(sorted(custom)))
    actual -= custom
    failed = False
    missing = sorted(FILES - actual)
    extra = sorted(actual - FILES)
    if missing:
        print('FAIL: missing CSS v34 gamedata: ' + ', '.join(missing), file=sys.stderr)
        failed = True
    if extra:
        print('FAIL: unexpected upstream gamedata: ' + ', '.join(extra), file=sys.stderr)
        failed = True
    for rel, needles in REQUIRED.items():
        path = root / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding='latin-1')
        absent = [needle for needle in needles if needle not in text]
        if absent:
            print(f'FAIL: {rel} is missing ' + ', '.join(absent), file=sys.stderr)
            failed = True
    for rel, patterns in REQUIRED_PATTERNS.items():
        path = root / rel
        if not path.is_file():
            continue
        text = effective_text(root, rel, custom_overrides(root, rel, custom))
        absent = [pattern for pattern in patterns if not re.search(pattern, text, re.DOTALL)]
        if absent:
            print(f'FAIL: {rel} has incorrect CSS v34 entries: ' + ', '.join(absent), file=sys.stderr)
            failed = True
    for rel, needles in FORBIDDEN.items():
        path = root / rel
        if not path.is_file():
            continue
        text = effective_text(root, rel, custom_overrides(root, rel, custom))
        present = [needle for needle in needles if needle in text]
        if present:
            print(f'FAIL: {rel} contains unsupported CSS v34 entries: ' + ', '.join(present), file=sys.stderr)
            failed = True
    if len(args) == 3:
        try:
            referenced = source_keys(Path(args[2]))
        except ValueError as exc:
            print(f'FAIL: {exc}', file=sys.stderr)
            return 1
        all_data = '\n'.join(path.read_text(encoding='latin-1') for path in root.rglob('*.txt'))
        uncovered = sorted(
            key for key in referenced
            if key not in UNSUPPORTED_SOURCE_KEYS and f'"{key}"' not in all_data
        )
        if uncovered:
            print('FAIL: unclassified SourceMod gamedata lookups: ' + ', '.join(uncovered), file=sys.stderr)
            failed = True
    if failed:
        return 1
    print(f'OK: self-contained CSS v34 gamedata ({len(FILES)} files)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
