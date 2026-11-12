#!/usr/bin/env python3
"""Prebuilt test images: install-deps.sh no-op marker and pull-test-image.sh fallback."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DEPS = ROOT / "testing/scripts/install-deps.sh"
PULL = ROOT / "testing/scripts/pull-test-image.sh"

FAKE_DOCKER = """#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
case "$1" in
  login) cat >/dev/null; exit "${LOGIN_RC:-0}" ;;
  pull) for a in "$@"; do last="$a"; done
        case " ${FAIL_PULL:-} " in *" $last "*) exit 1 ;; esac
        exit 0 ;;
esac
exit 2
"""


class InstallDepsMarkerTest(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.temp)
        self.marker = self.temp / "marker"
        # No package manager may run: a fake PATH fails every apt/yum/dnf call loudly.
        self.bin = self.temp / "bin"
        self.bin.mkdir()
        for tool in ("apt-get", "apt-cache", "dpkg", "yum", "dnf"):
            path = self.bin / tool
            path.write_text("#!/bin/sh\necho PACKAGE-MANAGER-CALLED >&2\nexit 99\n")
            path.chmod(0o755)

    def run_deps(self, **env):
        full = dict(os.environ, CSS34_DEPS_MARKER_FILE=str(self.marker),
                    PATH=str(self.bin) + os.pathsep + os.environ["PATH"], **env)
        return subprocess.run(["bash", str(DEPS)], env=full, capture_output=True, text=True)

    def test_matching_marker_is_a_noop(self):
        digest = hashlib.sha256(DEPS.read_bytes()).hexdigest()
        self.marker.write_text(digest + "\n")
        result = self.run_deps()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("nothing to install", result.stdout)
        self.assertIn(digest[:12], result.stdout)
        self.assertNotIn("PACKAGE-MANAGER-CALLED", result.stderr)

    def test_marker_needs_the_same_script(self):
        # Only the guard is exercised: a mismatching marker must not short-circuit.
        # (Running the install path would touch this host's package manager.)
        text = DEPS.read_text()
        self.assertIn('if [[ "$(cat "${DEPS_MARKER}")" == "${hash}" ]]; then', text)
        self.assertIn('"${CSS34_DEPS_FORCE:-0}" != 1', text)
        self.assertIn('printf \'%s\\n\' "${hash}" >"${DEPS_MARKER}"', text)


class PullTestImageTest(unittest.TestCase):
    PREBUILT = "ghcr.io/fmu1337/css34-test@sha256:" + "ab" * 32
    BASE = "debian:11@sha256:" + "cd" * 32

    def setUp(self):
        self.temp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.temp)
        docker = self.temp / "docker"
        docker.write_text(FAKE_DOCKER)
        docker.chmod(0o755)
        self.log = self.temp / "docker.log"

    def pull(self, *args, **env):
        full = dict(os.environ, PATH=str(self.temp) + os.pathsep + os.environ["PATH"],
                    DOCKER_LOG=str(self.log), CSS34_PULL_RETRY_SECS="0")
        full.pop("GHCR_TOKEN", None)
        full.update(env)
        result = subprocess.run(["bash", str(PULL)] + list(args), env=full, capture_output=True, text=True)
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return result, calls

    def test_prebuilt_image_is_used(self):
        result, calls = self.pull(self.PREBUILT, self.BASE, GHCR_TOKEN="t")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.PREBUILT)
        self.assertTrue(calls[0].startswith("login ghcr.io"))
        self.assertEqual(calls[1:], ["pull --platform linux/amd64 " + self.PREBUILT])

    def test_pull_failure_falls_back_to_base(self):
        result, calls = self.pull(self.PREBUILT, self.BASE, FAIL_PULL=self.PREBUILT, LOGIN_RC="1",
                                  GHCR_TOKEN="t")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.BASE)
        self.assertIn("falling back to " + self.BASE, result.stderr)
        self.assertEqual(calls[-1], "pull --platform linux/amd64 " + self.BASE)

    def test_base_only_row_never_logs_in(self):
        result, calls = self.pull(self.BASE, self.BASE, GHCR_TOKEN="t")
        self.assertEqual(result.stdout.strip(), self.BASE)
        self.assertEqual(calls, ["pull --platform linux/amd64 " + self.BASE])

    def test_unpullable_base_fails(self):
        result, _ = self.pull(self.BASE, self.BASE, FAIL_PULL=self.BASE)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
