"""Minimal Source RCON client: rcon.py HOST PASSWORD CMD... ("sleep N" pauses)."""
import socket, struct, sys, time
def pkt(i, t, body):
    b = struct.pack('<ii', i, t) + body.encode() + b'\x00\x00'
    return struct.pack('<i', len(b)) + b
def recv_pkt(s):
    hdr = b''
    while len(hdr) < 4:
        c = s.recv(4 - len(hdr))
        if not c: raise EOFError
        hdr += c
    n = struct.unpack('<i', hdr)[0]; d = b''
    while len(d) < n:
        c = s.recv(n - len(d))
        if not c: raise EOFError
        d += c
    i, t = struct.unpack('<ii', d[:8]); return i, t, d[8:-2].decode(errors='replace').replace('\x00', '')
host, pw = sys.argv[1], sys.argv[2]
s = socket.create_connection((host, 27015), timeout=10)
s.sendall(pkt(1, 3, pw))
while True:
    i, t, _ = recv_pkt(s)
    if t == 2: break
if i == -1: print('AUTH FAILED'); sys.exit(1)
for n, cmd in enumerate(sys.argv[3:], start=10):
    if cmd.startswith('sleep '):
        time.sleep(float(cmd.split()[1])); continue
    s.sendall(pkt(n, 2, cmd)); s.sendall(pkt(n + 1000, 0, ''))
    out = ''
    try:
        while True:
            i, t, b = recv_pkt(s)
            if i == n + 1000: break
            out += b
    except socket.timeout:
        # changelevel / quit can keep the server busy past the socket timeout
        print(f'>>> {cmd}\n(no reply)', flush=True)
        break
    print(f'>>> {cmd}\n{out}', flush=True)
