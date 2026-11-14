#!/usr/bin/env python3
"""builder/deps_cache.py: when a built dependency prefix may be reused.

The CI deps cache (ci.yml build-linux, .github/actions/build-linux input
deps-cache) restores deps/zlib, deps/openssl, the MariaDB connector and the
MySQL SDK; checkout-deps.sh reuses one only when its stamp records the inputs
digest of this build. Covers the digest inputs, every refusal, the CLI exit
codes, and that release.yml and the freeze path stay cache-free.
"""
from pathlib import Path
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'builder/deps_cache.py'
spec = importlib.util.spec_from_file_location('deps_cache', SCRIPT)
dc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dc)

IMAGE = 'quay.io/pypa/manylinux2014_i686@sha256:' + '0' * 64
SM = 'b34de51b8c7f' + '0' * 28
CLEAN_ENV = {}


def copy_inputs(dest: Path) -> None:
    for rel in dc.INPUT_FILES:
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, dest / rel)


class Digest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        copy_inputs(self.root)
        self.base = dc.compute_digest(self.root, IMAGE, '/workspace/deps')

    def tearDown(self):
        self.tmp.cleanup()

    def test_stable(self):
        self.assertEqual(self.base, dc.compute_digest(self.root, IMAGE, '/workspace/deps'))
        self.assertRegex(self.base, r'^[0-9a-f]{64}$')

    def test_every_input_file_changes_it(self):
        for rel in dc.INPUT_FILES:
            with self.subTest(rel=rel):
                path = self.root / rel
                orig = path.read_bytes()
                path.write_bytes(orig + b'\n')
                try:
                    self.assertNotEqual(self.base, dc.compute_digest(self.root, IMAGE, '/workspace/deps'))
                finally:
                    path.write_bytes(orig)

    def test_image_and_deps_dir_change_it(self):
        self.assertNotEqual(self.base, dc.compute_digest(self.root, IMAGE[:-1] + '1', '/workspace/deps'))
        self.assertNotEqual(self.base, dc.compute_digest(self.root, IMAGE, '/other/deps'))

    def test_missing_input_fails(self):
        (self.root / dc.INPUT_FILES[0]).unlink()
        with self.assertRaises(SystemExit):
            dc.compute_digest(self.root, IMAGE, '/workspace/deps')

    def test_inputs_cover_the_builders_of_the_prefixes(self):
        # Every script checkout-deps.sh runs to fetch, patch or build a prefix.
        for rel in ('builder/checkout-deps.sh', 'builder/fetch-pinned.sh',
                    'builder/patches/patch-openssl-getentropy.py', 'builder/docker/build.sh'):
            self.assertIn(rel, dc.INPUT_FILES)
        deps = (ROOT / 'builder/checkout-deps.sh').read_text()
        for helper in re.findall(r'\$BUILDER_DIR/([\w./-]+\.(?:sh|py))', deps.split('clone_repo()')[0]):
            self.assertIn('builder/' + helper, dc.INPUT_FILES, helper)


class Image(unittest.TestCase):
    def test_default_image_is_build_sh_image(self):
        old = os.environ.pop('ML2014_IMAGE', None)
        try:
            image = dc.default_image(ROOT)
        finally:
            if old is not None:
                os.environ['ML2014_IMAGE'] = old
        self.assertRegex(image, r'^quay\.io/pypa/manylinux2014_i686@sha256:[0-9a-f]{64}$')
        self.assertIn(image, (ROOT / 'docs' / 'EXTENSIONS.md').read_text())

    def test_build_sh_passes_the_image_into_the_container(self):
        text = (ROOT / 'builder/docker/build.sh').read_text()
        self.assertIn('-e CSS34_BUILD_IMAGE="${IMAGE}"', text)

    def test_ml2014_override(self):
        old = os.environ.get('ML2014_IMAGE')
        os.environ['ML2014_IMAGE'] = 'example/image@sha256:' + 'a' * 64
        try:
            self.assertEqual(dc.default_image(ROOT), os.environ['ML2014_IMAGE'])
        finally:
            if old is None:
                del os.environ['ML2014_IMAGE']
            else:
                os.environ['ML2014_IMAGE'] = old


class Reuse(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.prefix = Path(self.tmp.name) / 'openssl'
        (self.prefix / 'lib').mkdir(parents=True)
        (self.prefix / 'lib/libssl.a').write_bytes(b'!<arch>\n')
        self.digest = 'ab' * 32

    def tearDown(self):
        self.tmp.cleanup()

    def decide(self, files=('lib/libssl.a',), env=None, digest=None):
        return dc.reuse_decision(self.prefix, digest or self.digest, list(files),
                                 CLEAN_ENV if env is None else env)

    def test_missing_prefix(self):
        shutil.rmtree(self.prefix)
        self.assertEqual(self.decide(), (False, 'not present'))

    def test_no_stamp(self):
        self.assertEqual(self.decide(), (False, 'no stamp'))

    def test_matching_stamp_reuses(self):
        dc.write_stamp(self.prefix, self.digest)
        reuse, _ = self.decide()
        self.assertTrue(reuse)

    def test_other_digest_rebuilds(self):
        dc.write_stamp(self.prefix, self.digest)
        reuse, reason = self.decide(digest='cd' * 32)
        self.assertFalse(reuse)
        self.assertIn('stamp digest', reason)

    def test_missing_required_file_rebuilds(self):
        dc.write_stamp(self.prefix, self.digest)
        self.assertEqual(self.decide(files=('lib/libssl.a', 'lib/libcrypto.a')),
                         (False, 'missing lib/libcrypto.a'))

    def test_stamp_of_another_prefix_rebuilds(self):
        dc.write_stamp(self.prefix, self.digest)
        other = self.prefix.parent / 'zlib'
        other.mkdir()
        shutil.copy2(self.prefix / dc.STAMP_NAME, other / dc.STAMP_NAME)
        reuse, reason = dc.reuse_decision(other, self.digest, [], CLEAN_ENV)
        self.assertFalse(reuse)
        self.assertIn('prefix', reason)

    def test_corrupt_stamps_rebuild(self):
        for text in ('not json', '[]', '{}', json.dumps({'digest': None})):
            with self.subTest(text=text):
                (self.prefix / dc.STAMP_NAME).write_text(text)
                self.assertFalse(self.decide()[0])

    def test_legacy_version_stamp_rebuilds(self):
        # The pre-cache stamps named only the version (.css34-openssl-3.5.9-...).
        (self.prefix / '.css34-openssl-3.5.9-linux-syscall-v1').touch()
        self.assertEqual(self.decide(), (False, 'no stamp'))

    def test_freeze_and_forced_builds_never_reuse(self):
        dc.write_stamp(self.prefix, self.digest)
        for env in ({'CSS34_OFFLINE': '1'}, {'CSS34_SAVE_DOWNLOADS': '/save'},
                    {'CSS34_DEPS_REBUILD': '1'}):
            with self.subTest(env=env):
                self.assertFalse(self.decide(env=env)[0])
        self.assertTrue(self.decide(env={'CSS34_OFFLINE': '0', 'CSS34_DEPS_REBUILD': '0'})[0])

    def test_cli_exit_codes(self):
        env = {k: v for k, v in os.environ.items()
               if k not in ('CSS34_OFFLINE', 'CSS34_SAVE_DOWNLOADS', 'CSS34_DEPS_REBUILD')}
        run = lambda *a: subprocess.run([sys.executable, str(SCRIPT), *a], env=env,
                                        capture_output=True, text=True)
        self.assertEqual(run('check', str(self.prefix), self.digest, 'lib/libssl.a').returncode, 1)
        self.assertEqual(run('stamp', str(self.prefix), self.digest).returncode, 0)
        ok = run('check', str(self.prefix), self.digest, 'lib/libssl.a')
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertIn('reusing openssl', ok.stderr)
        self.assertEqual(run('check', str(self.prefix), 'ef' * 32).returncode, 1)
        env['CSS34_OFFLINE'] = '1'
        self.assertEqual(run('check', str(self.prefix), self.digest).returncode, 1)


class Key(unittest.TestCase):
    def test_key_shape(self):
        key = dc.cache_key('sm13-latest', SM, 'ab' * 32)
        self.assertEqual(key, f'css34-deps-v{dc.SCHEMA}-sm13-latest-smb34de51b8c7f-' + 'ab' * 32)

    def test_key_rejects_bad_input(self):
        for line, sm in (('sm13 latest', SM), ('sm13-latest', 'abc'), ('x', SM.upper())):
            with self.subTest(line=line, sm=sm), self.assertRaises(SystemExit):
                dc.cache_key(line, sm, 'ab' * 32)

    def test_cli_key_equals_container_digest(self):
        # The CI key embeds the digest the builder computes inside build.sh's
        # container (same image, /workspace/deps): a hit restores prefixes the
        # builder will reuse.
        out = subprocess.run([sys.executable, str(SCRIPT), 'key', '--line', 'sm13-latest',
                              '--sm-commit', SM], capture_output=True, text=True, check=True,
                             env={k: v for k, v in os.environ.items()
                                  if k not in ('ML2014_IMAGE', 'CSS34_BUILD_IMAGE')}).stdout.strip()
        digest = dc.compute_digest(ROOT, dc.default_image(ROOT), '/workspace/deps')
        self.assertTrue(out.endswith('-' + digest), out)


class Wiring(unittest.TestCase):
    def test_prefixes_match_checkout_deps(self):
        deps = (ROOT / 'builder/checkout-deps.sh').read_text()
        version = re.search(r'^MARIADB_CONNECTOR_VERSION=(\S+)$', deps, re.M).group(1)
        self.assertIn(f'mariadb-connector-c-{version}-x86', dc.PREFIXES)
        self.assertIn('MARIADB_DIR="$DEPS/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-x86"', deps)
        for name in ('zlib', 'openssl', 'mysql-5.5'):
            self.assertIn(f'"$DEPS/{name}"', deps)
        # Each prefix is checked and stamped; no version-only stamp is left.
        self.assertEqual(deps.count('deps_reusable "'), 4)
        self.assertEqual(deps.count('deps_stamp "'), 4)
        self.assertNotIn('touch "$stamp"\n}', deps.split('install_build_perl')[0])
        self.assertNotIn('.css34-openssl-', deps)
        self.assertNotIn('.css34-zlib-', deps)
        self.assertNotIn('.css34-src-', deps)

    def test_paths_cli(self):
        out = subprocess.run([sys.executable, str(SCRIPT), 'paths'], capture_output=True,
                             text=True, check=True).stdout.split()
        self.assertEqual(out, ['deps/' + p for p in dc.PREFIXES])

    def test_only_ci_build_linux_uses_the_cache(self):
        action = (ROOT / '.github/actions/build-linux/action.yml').read_text()
        self.assertIn("default: 'false'", action)
        self.assertIn('builder/deps_cache.py key', action)
        self.assertIn('builder/deps_cache.py paths', action)
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertEqual(ci.count("deps-cache: 'true'"), 1)
        for wf in (ROOT / '.github/workflows').glob('*.yml'):
            if wf.name == 'ci.yml':
                continue
            text = wf.read_text()
            self.assertNotIn('deps-cache', text, wf.name)
            self.assertNotIn('css34-deps-', text, wf.name)
        for script in (ROOT / 'builder/freeze').glob('*.sh'):
            self.assertNotIn('deps_cache', script.read_text(), script.name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
