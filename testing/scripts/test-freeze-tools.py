#!/usr/bin/env python3
"""T2.7 freeze tools: fetch_pinned (builder/fetch-pinned.sh),
testing/scripts/compare-package-abi.py and testing/scripts/verify-frozen-line.py.
Needs bash, curl, git, gcc and binutils."""
from __future__ import annotations

import hashlib
import io
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FETCH = ROOT / "builder/fetch-pinned.sh"
COMPARE = ROOT / "testing/scripts/compare-package-abi.py"


def sh(script: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", "-c", f"set -euo pipefail; source {FETCH}; {script}"],
                          capture_output=True, text=True, env={"PATH": "/usr/bin:/bin", **(env or {})})


class FetchPinnedTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.src = self.dir / "src" / "dep-1.0.tar.gz"
        self.src.parent.mkdir()
        self.src.write_bytes(b"pinned bytes")
        self.sha = hashlib.sha256(b"pinned bytes").hexdigest()
        self.url = f"file://{self.src}"

    def test_online_download_is_verified_and_recorded(self):
        save = self.dir / "save"
        res = sh(f'fetch_pinned "{self.url}" "{self.dir}/out" {self.sha}', {"CSS34_SAVE_DOWNLOADS": str(save)})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual((self.dir / "out").read_bytes(), b"pinned bytes")
        self.assertEqual((save / "dep-1.0.tar.gz").read_bytes(), b"pinned bytes")

    def test_name_argument_names_the_archived_file(self):
        save = self.dir / "save"
        res = sh(f'fetch_pinned "{self.url}" "{self.dir}/out" {self.sha} hl2sdk-css-x-userid.h',
                 {"CSS34_SAVE_DOWNLOADS": str(save)})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue((save / "hl2sdk-css-x-userid.h").is_file())

    def test_sha_mismatch_fails_closed(self):
        res = sh(f'fetch_pinned "{self.url}" "{self.dir}/out" {"0" * 64}')
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("sha256 mismatch", res.stderr)
        self.assertFalse((self.dir / "out").exists())

    def test_offline_takes_the_archive_and_never_the_url(self):
        dl = self.dir / "dl"
        dl.mkdir()
        (dl / "dep-1.0.tar.gz").write_bytes(b"pinned bytes")
        env = {"CSS34_OFFLINE": "1", "CSS34_DOWNLOADS": str(dl)}
        res = sh(f'fetch_pinned "https://invalid.example/dep-1.0.tar.gz" "{self.dir}/out" {self.sha}', env)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual((self.dir / "out").read_bytes(), b"pinned bytes")

    def test_offline_without_the_file_fails(self):
        env = {"CSS34_OFFLINE": "1", "CSS34_DOWNLOADS": str(self.dir)}
        res = sh(f'fetch_pinned "{self.url}" "{self.dir}/out" {self.sha}', env)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("offline build", res.stderr)

    def test_archived_file_is_still_verified(self):
        dl = self.dir / "dl"
        dl.mkdir()
        (dl / "dep-1.0.tar.gz").write_bytes(b"tampered")
        res = sh(f'fetch_pinned "{self.url}" "{self.dir}/out" {self.sha}', {"CSS34_DOWNLOADS": str(dl)})
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("sha256 mismatch", res.stderr)

    def test_build_wheels_come_from_the_archive_offline(self):
        dl = self.dir / "dl"
        dl.mkdir()
        res = sh("css34_fetch_build_wheels " + str(self.dir / "deps"), {"CSS34_OFFLINE": "1", "CSS34_DOWNLOADS": str(dl)})
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("setuptools-80.9.0-py3-none-any.whl is not in CSS34_DOWNLOADS", res.stderr)


class CompareAbiTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def lib(self, name: str, source: str) -> bytes:
        c = self.dir / f"{name}.c"
        so = self.dir / f"{name}.so"
        c.write_text(source)
        subprocess.run(["gcc", "-shared", "-fPIC", "-o", str(so), str(c)], check=True)
        return so.read_bytes()

    def package(self, name: str, files: dict[str, bytes]) -> Path:
        path = self.dir / name
        with tarfile.open(path, "w:gz") as tf:
            for member, data in files.items():
                info = tarfile.TarInfo(member)
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
        return path

    def compare(self, a: Path, b: Path) -> subprocess.CompletedProcess:
        return subprocess.run(["python3", str(COMPARE), str(a), str(b)], capture_output=True, text=True)

    def manifest(self, **over) -> bytes:
        m = {"sm_version": "1.11.0.6970", "build_date": "2026-11-02T00:00:00Z", "css34_pack_commit": "a"}
        m.update(over)
        return json.dumps(m).encode()

    def test_same_exports_pass_even_when_bytes_differ(self):
        so1 = self.lib("a", "int api(void) { return 1; }\n")
        so2 = self.lib("b", "int api(void) { return 2; }\n")
        a = self.package("a.tar.gz", {"addons/bin/x.so": so1, "addons/css34-package.json": self.manifest(),
                                      "addons/p.smx": b"1"})
        b = self.package("b.tar.gz", {"addons/bin/x.so": so2,
                                      "addons/css34-package.json": self.manifest(build_date="later", css34_pack_commit="b"),
                                      "addons/p.smx": b"2"})
        res = self.compare(a, b)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("NOTE: bytes differ (not an ABI gate): addons/p.smx", res.stdout)

    def test_extra_export_fails(self):
        a = self.package("a.tar.gz", {"x.so": self.lib("a", "int api(void) { return 1; }\n")})
        b = self.package("b.tar.gz", {"x.so": self.lib("b", "int api(void) { return 1; }\nint more(void) { return 0; }\n")})
        res = self.compare(a, b)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("x.so: exports differ", res.stderr)
        self.assertIn("more", res.stderr)

    def test_file_sets_and_manifest_fields_must_match(self):
        so = self.lib("a", "int api(void) { return 1; }\n")
        a = self.package("a.tar.gz", {"x.so": so, "y.txt": b"y", "css34-package.json": self.manifest()})
        b = self.package("b.tar.gz", {"x.so": so, "css34-package.json": self.manifest(sm_version="1.11.0.6971")})
        res = self.compare(a, b)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("only in a.tar.gz: y.txt", res.stderr)
        self.assertIn("sm_version", res.stderr)

    def test_needed_must_match(self):
        a = self.package("a.tar.gz", {"x.so": self.lib("a", "int api(void) { return 1; }\n")})
        c = self.dir / "c.c"
        c.write_text("int api(void) { return 1; }\n")
        so = self.dir / "c.so"
        subprocess.run(["gcc", "-shared", "-fPIC", "-o", str(so), str(c), "-Wl,--no-as-needed", "-lm"], check=True)
        b = self.package("b.tar.gz", {"x.so": so.read_bytes()})
        res = self.compare(a, b)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("NEEDED/SONAME", res.stderr)


class VerifyFrozenLineTest(unittest.TestCase):
    """testing/scripts/verify-frozen-line.py on a fake release tree served over file://."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.base = self.dir / "download"
        git = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]
        self.repo = self.dir / "repo"
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        (self.repo / "f").write_text("x")
        subprocess.run(git + ["-C", str(self.repo), "add", "f"], check=True)
        subprocess.run(git + ["-C", str(self.repo), "commit", "-qm", "freeze"], check=True)
        subprocess.run(git + ["-C", str(self.repo), "tag", "-a", "-m", "f", "sm11-freeze"], check=True)
        self.commit = subprocess.run(["git", "-C", str(self.repo), "rev-parse", "HEAD"],
                                     capture_output=True, text=True, check=True).stdout.strip()
        self.assets = {"sm.tar.gz": b"sm", "mm.tar.gz": b"mm", "win.zip": b"win"}
        self.write("T", self.assets)
        ptr = {"sourcemod-css34-linux.tar.gz": b"sm", "mmsource-css34-linux.tar.gz": b"mm"}
        self.write("line-L", ptr, {"lines.json": json.dumps({"L": {"tag": "T", "smoke": "pass"}}).encode()})
        self.manifest(self.commit)

    def write(self, release, files, extra=None):
        d = self.base / release
        d.mkdir(parents=True, exist_ok=True)
        for name, data in {**files, **(extra or {})}.items():
            (d / name).write_bytes(data)
        (d / "SHA256SUMS").write_text("".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n"
                                              for name, data in files.items()))

    def manifest(self, commit, line="L"):
        archived = {"build-image.tar.zst": b"img", "git-a-b.tar.zst": b"git"}
        m = {"line": line, "builder_commit": commit,
             "assets": {n: hashlib.sha256(d).hexdigest() for n, d in archived.items()}}
        self.write("R", {**archived, "MANIFEST.json": json.dumps(m).encode()})

    def verify(self) -> subprocess.CompletedProcess:
        assets = {n: hashlib.sha256(d).hexdigest() for n, d in self.assets.items()}
        pointer = {"sourcemod-css34-linux.tar.gz": "sm.tar.gz", "mmsource-css34-linux.tar.gz": "mm.tar.gz"}
        return subprocess.run(["python3", str(ROOT / "testing/scripts/verify-frozen-line.py"),
                               "--base", f"file://{self.base}", "--repo-git", str(self.repo),
                               "--line", "L", "--tag", "T", "--freeze-tag", "sm11-freeze",
                               "--inputs-release", "R", "--assets", json.dumps(assets),
                               "--pointer-assets", json.dumps(pointer)], capture_output=True, text=True)

    def test_matching_files_pass(self):
        res = self.verify()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("R was collected at sm11-freeze", res.stdout)

    def test_pointer_file_that_differs_from_its_asset_fails(self):
        (self.base / "line-L" / "mmsource-css34-linux.tar.gz").write_bytes(b"other")
        res = self.verify()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("line-L/mmsource-css34-linux.tar.gz downloads as", res.stderr)

    def test_release_asset_changed_after_freeze_fails(self):
        self.assets["win.zip"] = b"rebuilt"
        res = self.verify()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("T/SHA256SUMS lists win.zip", res.stderr)

    def test_pointer_moved_to_another_tag_fails(self):
        (self.base / "line-L" / "lines.json").write_text(json.dumps({"L": {"tag": "T-r9", "smoke": "pass"}}))
        self.assertIn("line-L serves 'T-r9'", self.verify().stderr)

    def test_inputs_collected_elsewhere_fail(self):
        self.manifest("0" * 40)
        res = self.verify()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("sm11-freeze is " + self.commit, res.stderr)

    def test_missing_inputs_release_fails(self):
        import shutil
        shutil.rmtree(self.base / "R")
        self.assertIn("R: ", self.verify().stderr)


if __name__ == "__main__":
    unittest.main()
