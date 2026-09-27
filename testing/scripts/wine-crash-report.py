"""Map the access violations in a Wine log (WINEDEBUG=+seh,+loaddll) to module + RVA,
and symbolize them with llvm-symbolizer when a .pdb sits next to the .dll.

usage: wine-crash-report.py WINE_LOG SERVER_DIR
"""
import re, shutil, subprocess, sys
from pathlib import Path, PureWindowsPath

log, server = Path(sys.argv[1]), Path(sys.argv[2])
text = log.read_text(errors='replace').splitlines()
mods = []  # (base, path)
for line in text:
    m = re.search(r'Loaded L"(.+?)" at ([0-9A-Fa-f]+): (?:native|builtin)', line)
    if m:
        mods.append((int(m.group(2), 16), m.group(1).replace('\\\\', '\\')))
mods.sort()

def local_path(win):
    # z:\tmp\... -> /tmp/...
    p = PureWindowsPath(win)
    if p.drive.lower() == 'z:':
        return Path('/', *p.parts[1:])
    return None

def image_base(path):
    try:
        out = subprocess.run(['objdump', '-p', str(path)], capture_output=True, text=True).stdout
        m = re.search(r'ImageBase\s+([0-9a-fA-F]+)', out)
        return int(m.group(1), 16) if m else None
    except OSError:
        return None

def image_size(path):
    try:
        out = subprocess.run(['objdump', '-p', str(path)], capture_output=True, text=True).stdout
        m = re.search(r'SizeOfImage\s+([0-9a-fA-F]+)', out)
        return int(m.group(1), 16) if m else None
    except OSError:
        return None

symbolizer = next((s for s in ('llvm-symbolizer', 'llvm-symbolizer-14', 'llvm-symbolizer-15') if shutil.which(s)), None)

def describe(addr):
    owner = None
    for base, path in mods:
        if base <= addr:
            owner = (base, path)
    if owner is None:
        return f'{addr:08x} (no module)'
    base, path = owner
    rva = addr - base
    lp = local_path(path)
    size = image_size(lp) if lp and lp.exists() else None
    if size is not None and rva >= size:
        return f'{addr:08x} (not in a known module)'
    desc = f'{addr:08x} {PureWindowsPath(path).name}+0x{rva:x}'

    if lp and lp.exists() and lp.with_suffix('.pdb').exists() and symbolizer:
        ib = image_base(lp)
        if ib is not None:
            r = subprocess.run([symbolizer, '--obj', str(lp), '--functions=linkage', '--inlining', hex(ib + rva)],
                               capture_output=True, text=True)
            sym = ' | '.join(l.strip() for l in r.stdout.splitlines() if l.strip())
            desc += f'  {sym}'
    return desc

seen = 0
for i, line in enumerate(text):
    m = re.search(r'dispatch_exception code=(c0000005|c000001d|c0000096|80000003) .*addr=([0-9A-Fa-f]+)', line)
    if not m:
        continue
    seen += 1
    print(f'== exception {m.group(1)} at {describe(int(m.group(2), 16))}')
    for extra in text[i + 1:i + 5]:
        if 'dispatch_exception' in extra:
            print('   ' + extra.split('dispatch_exception', 1)[1].strip())
    handlers = []
    for extra in text[i + 1:i + 200]:
        h = re.search(r'calling handler at ([0-9A-Fa-f]+)', extra)
        if h and h.group(1) not in handlers:
            handlers.append(h.group(1))
        if 'dispatch_exception code=' in extra:
            break
    for h in handlers:
        print(f'   handler {describe(int(h, 16))}')
    if seen >= 5:
        break
if not seen:
    print('no access violation in the Wine log')
