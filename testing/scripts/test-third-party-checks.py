#!/usr/bin/env python3
"""Host tests for the third-party extension tooling (builder/third-party/,
testing/scripts/check-third-party.sh); GCC and binutils, no game server."""
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / 'testing/scripts/check-third-party.sh'
ENV = ROOT / 'builder/third-party/socket.env'
LINES = ROOT / 'builder/lines.json'


def env_value(name):
    m = re.search(r'^{}="([^"]*)"$'.format(name), ENV.read_text(), re.M)
    return m.group(1) if m else None


class SocketPins(unittest.TestCase):
    def test_pins_are_exact(self):
        self.assertRegex(env_value('SOCKET_COMMIT'), r'^[0-9a-f]{40}$')
        self.assertRegex(env_value('SOCKET_TREE_SHA256'), r'^[0-9a-f]{64}$')
        self.assertRegex(env_value('SOCKET_BOOST_SHA256'), r'^[0-9a-f]{64}$')
        self.assertTrue(env_value('SOCKET_BOOST_URL').startswith('https://'))

    def test_lines_are_buildable(self):
        import json
        lines = json.loads(LINES.read_text())['lines']
        for line in env_value('SOCKET_LINES').split():
            self.assertIn(line, lines)
            self.assertNotEqual(lines[line].get('status'), 'frozen', line)

    def test_boost_goes_through_fetch_pinned(self):
        script = (ROOT / 'builder/third-party/socket.sh').read_text()
        self.assertIn('fetch_pinned "$SOCKET_BOOST_URL"', script)
        self.assertNotRegex(script, r'curl |wget ')

    def test_asset_name(self):
        out = subprocess.run(
            ['bash', '-c', 'source "$1"; socket_asset_name sm13-latest', '_', str(ENV)],
            check=True, capture_output=True, text=True).stdout.strip()
        self.assertEqual(out, 'socket-{}-git{}-sm13-latest-linux.tar.gz'.format(
            env_value('SOCKET_VERSION'), env_value('SOCKET_COMMIT')[:7]))


class CheckThirdParty(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def archive(self, compiler, source, suffix):
        tree = self.root / 'tree'
        ext = tree / 'addons/sourcemod/extensions'
        ext.mkdir(parents=True)
        src = self.root / ('ext' + suffix)
        src.write_text(source)
        so = ext / 'socket.ext.so'
        subprocess.run([compiler, '-shared', '-fPIC', str(src), '-o', str(so)], check=True)
        out = self.root / 'socket.tar.gz'
        with tarfile.open(out, 'w:gz') as tar:
            tar.add(tree / 'addons', arcname='addons')
        return out

    def check(self, archive):
        return subprocess.run(['bash', str(CHECK), str(archive)], capture_output=True, text=True)

    def test_host_elf_rejected(self):
        # A host (x86-64) build, no manifest, no GetSMExtAPI: every rule must report.
        result = self.check(self.archive('gcc', 'int probe(void) { return 1; }\n', '.c'))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('is not a 32-bit i386 ELF', result.stderr)
        self.assertIn('does not export GetSMExtAPI', result.stderr)
        self.assertIn('exports more than GetSMExtAPI', result.stderr)
        self.assertIn('manifest', result.stderr)

    def test_dynamic_libstdcxx_rejected(self):
        source = ('#include <string>\n'
                  'extern "C" __attribute__((visibility("default"))) void *GetSMExtAPI() {\n'
                  '  static std::string s("x"); return &s; }\n')
        result = self.check(self.archive('g++', source, '.cpp'))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('NEEDED libstdc++.so.6', result.stderr)

    def test_missing_archive_fails(self):
        self.assertNotEqual(self.check(self.root / 'missing.tar.gz').returncode, 0)


if __name__ == '__main__':
    unittest.main()
