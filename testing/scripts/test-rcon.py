#!/usr/bin/env python3
"""Exercise RCON auth and command replies through a server on a custom port."""
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import threading
import unittest

SCRIPT = Path(__file__).with_name('rcon.py')


def packet(request_id, kind, body=''):
    payload = struct.pack('<ii', request_id, kind) + body.encode() + b'\0\0'
    return struct.pack('<i', len(payload)) + payload


def receive(conn):
    def read(size):
        data = b''
        while len(data) < size:
            chunk = conn.recv(size - len(data))
            if not chunk:
                raise EOFError('client disconnected')
            data += chunk
        return data
    size, = struct.unpack('<i', read(4))
    data = read(size)
    return (*struct.unpack('<ii', data[:8]), data[8:-2].decode())


class RconPort(unittest.TestCase):
    def test_custom_port_auth_and_command(self):
        errors = []
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen()
            server.settimeout(10)

            def serve():
                try:
                    with server.accept()[0] as conn:
                        conn.settimeout(10)
                        self.assertEqual(receive(conn), (1, 3, 'secret'))
                        conn.sendall(packet(1, 2))
                        request_id, kind, command = receive(conn)
                        self.assertEqual((kind, command), (2, 'echo probe'))
                        marker_id, kind, body = receive(conn)
                        self.assertEqual((kind, body), (0, ''))
                        conn.sendall(packet(request_id, 0, 'probe') + packet(marker_id, 0))
                except Exception as exc:
                    errors.append(exc)

            worker = threading.Thread(target=serve, daemon=True)
            worker.start()
            result = subprocess.run(
                [sys.executable, str(SCRIPT), '127.0.0.1', 'secret', 'echo probe'],
                env={**os.environ, 'RCON_PORT': str(server.getsockname()[1])},
                capture_output=True, text=True, timeout=15)
            worker.join(timeout=12)
        self.assertFalse(worker.is_alive(), 'mock server did not finish')
        self.assertEqual(errors, [])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('>>> echo probe\nprobe', result.stdout)


if __name__ == '__main__':
    unittest.main()
