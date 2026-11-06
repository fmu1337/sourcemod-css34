#!/usr/bin/env python3
"""Host tests for the third-party extension tooling (builder/third-party/,
testing/scripts/check-third-party.sh); GCC and binutils, no game server."""
from pathlib import Path
import json
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
        lines = json.loads(LINES.read_text())['lines']
        for line in env_value('SOCKET_LINES').split():
            self.assertIn(line, lines)
            self.assertNotEqual(lines[line].get('status'), 'frozen', line)

    def test_boost_goes_through_fetch_pinned(self):
        script = (ROOT / 'builder/third-party/socket.sh').read_text()
        self.assertIn('fetch_pinned "$SOCKET_BOOST_URL"', script)
        self.assertNotRegex(script, r'curl |wget ')

    def test_linux_build_bundles_it(self):
        script = (ROOT / 'builder/run/linux.sh').read_text()
        self.assertIn('bash "$BUILDER_DIR/third-party/socket.sh"', script)
        self.assertIn('SOCKET_INSTALL_DIR="$PACKAGE_DIR"', script)
        # Installed into the package tree before package.sh archives it.
        self.assertLess(script.index('third-party/socket.sh'),
                        script.index('bash "$BUILDER_DIR/package.sh"'))


class CheckThirdParty(unittest.TestCase):
    """check-third-party.sh on hand-made SourceMod package tarballs."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.tree = self.root / 'tree'
        self.sm = self.tree / 'addons/sourcemod'
        (self.sm / 'extensions').mkdir(parents=True)

    def package(self, line='sm12-latest', manifest=True, listed=True,
                compiler='gcc', source='int probe(void) { return 1; }\n', suffix='.c'):
        commit = env_value('SOCKET_COMMIT')
        pkg = {'line': line, 'sm_commit': 'a' * 40, 'extension_api': 11, 'extension_api_min': 9}
        files = []
        if source is not None:
            src = self.root / ('ext' + suffix)
            src.write_text(source)
            subprocess.run([compiler, '-shared', '-fPIC', str(src), '-o',
                            str(self.sm / 'extensions/socket.ext.so')], check=True)
            files.append('addons/sourcemod/extensions/socket.ext.so')
        if manifest:
            lic = self.sm / 'licenses/socket'
            lic.mkdir(parents=True)
            (lic / 'css34-socket.json').write_text(json.dumps({
                'name': 'Socket', 'version': env_value('SOCKET_VERSION'), 'source': 'x',
                'source_commit': commit, 'source_tree_sha256': 'b' * 64, 'line': line,
                'sm_commit': 'a' * 40, 'extension_api': 11,
                'compiler': 'g++ (GCC) 10.2.1', 'files': files}))
        if listed:
            pkg['third_party'] = [{'name': 'Socket', 'version': env_value('SOCKET_VERSION'),
                                   'source': 'x', 'source_commit': commit}]
        (self.sm / 'css34-package.json').write_text(json.dumps(pkg))
        out = self.root / 'sm.tar.gz'
        with tarfile.open(out, 'w:gz') as tar:
            tar.add(self.tree / 'addons', arcname='addons')
        return out

    def check(self, archive):
        return subprocess.run(['bash', str(CHECK), str(archive)], capture_output=True, text=True)

    def test_package_without_third_party_passes(self):
        result = self.check(self.package(manifest=False, listed=False, source=None))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_socket_line_requires_socket(self):
        line = env_value('SOCKET_LINES').split()[0]
        result = self.check(self.package(line=line, manifest=False, listed=False, source=None))
        self.assertEqual(result.returncode, 1)
        self.assertIn('bundle the Socket extension', result.stderr)

    def test_host_elf_rejected(self):
        # A host (x86-64) build without GetSMExtAPI: the ELF rules must report.
        result = self.check(self.package())
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('is not a 32-bit i386 ELF', result.stderr)
        self.assertIn('does not export GetSMExtAPI', result.stderr)
        self.assertIn('exports more than GetSMExtAPI', result.stderr)

    def test_dynamic_libstdcxx_rejected(self):
        source = ('#include <string>\n'
                  'extern "C" __attribute__((visibility("default"))) void *GetSMExtAPI() {\n'
                  '  static std::string s("x"); return &s; }\n')
        result = self.check(self.package(compiler='g++', source=source, suffix='.cpp'))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('NEEDED libstdc++.so.6', result.stderr)

    def test_unlisted_manifest_rejected(self):
        result = self.check(self.package(listed=False))
        self.assertEqual(result.returncode, 1)
        self.assertIn('third_party does not list Socket', result.stderr)

    def test_missing_archive_fails(self):
        self.assertNotEqual(self.check(self.root / 'missing.tar.gz').returncode, 0)


if __name__ == '__main__':
    unittest.main()
