#!/usr/bin/env python3
"""Run switch-metamod.sh against synthetic Metamod packages and server trees."""
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "testing/scripts/switch-metamod.sh"


def make_package(path, binary, ini="; stock metaplugins.ini\n"):
    files = {
        "addons/metamod/bin/" + binary: b"\x7fELF fake",
        "addons/metamod/bin/server.so": b"loader",
        "addons/metamod/bin/server_i486.so": b"loader",
        "addons/metamod/metaplugins.ini": ini.encode(),
        "addons/metamod/css34-package.json": b"{}",
        "addons/metamod.vdf": b'"Plugin" { "file" "../cstrike/addons/metamod/bin/server" }',
    }
    with tarfile.open(path, "w:gz") as tar:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


class SwitchMetamodTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.server = root / "srv"
        self.mm = self.server / "cstrike/addons/metamod"
        self.legacy = root / "mmsource-1.10.7-git976-css34-linux.tar.gz"
        self.modern = root / "mmsource-1.12.0-git1227-css34-linux.tar.gz"
        make_package(self.legacy, "metamod.1.ep1.so")
        make_package(self.modern, "metamod.2.ep1.so")
        (self.server / "cstrike").mkdir(parents=True)
        with tarfile.open(self.legacy) as tar:
            tar.extractall(self.server / "cstrike", filter="data")
        (self.mm / "sourcemod.vdf").write_text('"Metamod Plugin" { "file" "addons/sourcemod/bin/sourcemod_mm" }\n')

    def switch(self, package):
        return subprocess.run(["bash", str(SCRIPT), str(package)], capture_output=True, text=True,
                              env={"SERVER_DIR": str(self.server), "PATH": "/usr/bin:/bin"})

    def binaries(self):
        return sorted(p.name for p in (self.mm / "bin").glob("metamod.*.ep1.so"))

    def test_switch_both_ways_keeps_operator_files(self):
        vdf = (self.mm / "sourcemod.vdf").read_text()
        res = self.switch(self.modern)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.binaries(), ["metamod.2.ep1.so"])
        ini = (self.mm / "metaplugins.ini").read_text()
        self.assertIn("css34 switch-metamod: operator entry kept", ini)
        self.assertEqual((self.mm / "sourcemod.vdf").read_text(), vdf)
        res = self.switch(self.legacy)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.binaries(), ["metamod.1.ep1.so"])
        self.assertEqual((self.mm / "metaplugins.ini").read_text().count("operator entry kept"), 2)

    def test_refuses_without_sourcemod_or_with_a_bad_package(self):
        bad = Path(self.tmp.name) / "mmsource-broken.tar.gz"
        with tarfile.open(bad, "w:gz") as tar:
            info = tarfile.TarInfo("addons/metamod/README.txt")
            tar.addfile(info, io.BytesIO(b""))
        res = self.switch(bad)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("ships no addons/metamod/bin/metamod", res.stderr)
        self.assertEqual(self.binaries(), ["metamod.1.ep1.so"])
        (self.mm / "sourcemod.vdf").unlink()
        res = self.switch(self.modern)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("SourceMod is not installed", res.stderr)
        res = self.switch(Path(self.tmp.name) / "missing.tar.gz")
        self.assertNotEqual(res.returncode, 0)

    def test_bridge_package_with_both_cores_and_switching_back(self):
        # sm11's MM 1.12 package ships metamod.1.ep1 for the legacy-plugin bridge.
        dual = Path(self.tmp.name) / "mmsource-1.12.0-git1227-dual-css34-linux.tar.gz"
        make_package(dual, "metamod.2.ep1.so")
        with tarfile.open(dual) as tar:
            members = {m.name: tar.extractfile(m).read() for m in tar.getmembers() if m.isfile()}
        members["addons/metamod/bin/metamod.1.ep1.so"] = b"\x7fELF legacy core"
        with tarfile.open(dual, "w:gz") as tar:
            for name, data in members.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
        res = self.switch(dual)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.binaries(), ["metamod.1.ep1.so", "metamod.2.ep1.so"])
        # Back to MM 1.10.7: the 2.ep1 core must not stay behind.
        res = self.switch(self.legacy)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.binaries(), ["metamod.1.ep1.so"])

if __name__ == "__main__":
    unittest.main()
