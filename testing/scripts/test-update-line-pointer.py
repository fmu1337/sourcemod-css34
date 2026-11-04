#!/usr/bin/env python3
"""builder/scripts/update-line-pointer.sh end to end against a fake `gh` (state in a JSON file).

Checks what a pointer move publishes: the stable package names, SHA256SUMS, VERSIONS.txt
(versions, original asset names, sha256), lines.json and lines-index, and a title and notes
that say what the pointer serves now; a failed candidate keeps the packages and says so.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "builder/scripts/update-line-pointer.sh"

FAKE_GH = r'''#!/usr/bin/env python3
import json, os, re, shutil, sys
state_path = os.path.join(os.environ["FAKE"], "state.json")
store = os.path.join(os.environ["FAKE"], "store")
st = json.load(open(state_path))
args = sys.argv[1:]
open(os.path.join(os.environ["FAKE"], "calls.log"), "a").write("gh " + " ".join(args) + "\n")

def save():
    json.dump(st, open(state_path, "w"), indent=1)

def opt(name, default=None):
    for i, a in enumerate(args):
        if a == name and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default

rels = st["releases"]
if args[:2] == ["release", "view"]:
    tag = args[2]
    if tag not in rels:
        sys.exit(1)
    q = opt("-q")
    if q == ".isDraft":
        print("false")
    elif q == ".assets[].name":
        print("\n".join(rels[tag]["assets"]))
    sys.exit(0)
if args[:2] == ["release", "create"]:
    rels[args[2]] = {"title": opt("--title"), "notes": opt("--notes"), "assets": {}}
    save(); sys.exit(0)
if args[:2] == ["release", "edit"]:
    rel = rels[args[2]]
    if opt("--title") is not None:
        rel["title"] = opt("--title")
    if opt("--notes-file") is not None:
        rel["notes"] = open(opt("--notes-file")).read()
    save(); sys.exit(0)
if args[:2] == ["release", "upload"]:
    rel = rels[args[2]]
    for path in [a for a in args[3:] if os.path.isfile(a)]:
        st["next_id"] += 1
        name = os.path.basename(path)
        shutil.copy(path, os.path.join(store, str(st["next_id"])))
        rel["assets"][name] = st["next_id"]
    save(); sys.exit(0)
if args[:2] == ["release", "download"]:
    rel = rels[args[2]]
    name, out = opt("-p"), opt("-D")
    shutil.copy(os.path.join(store, str(rel["assets"][name])), os.path.join(out, name))
    sys.exit(0)
if args[0] == "api":
    if args[1] == "-X":
        method, path = args[2], args[3]
        aid = int(path.rsplit("/", 1)[1])
        for rel in rels.values():
            for name, i in list(rel["assets"].items()):
                if i == aid:
                    del rel["assets"][name]
                    if method == "PATCH":
                        rel["assets"][opt("-f").split("=", 1)[1]] = aid
        save(); sys.exit(0)
    m = re.match(r"repos/[^/]+/[^/]+/releases/tags/(.+)$", args[1])
    if m:
        name = re.search(r'select\(\.name == "([^"]+)"\)', opt("-q")).group(1)
        aid = rels.get(m.group(1), {"assets": {}})["assets"].get(name)
        if aid:
            print(aid)
        sys.exit(0)
    if args[1] == "--paginate":
        print("\n".join(t for t in rels if t.startswith("line-")))
        sys.exit(0)
print("unexpected gh " + " ".join(args), file=sys.stderr)
sys.exit(2)
'''


def package(path, member, manifest):
    data = json.dumps(manifest).encode()
    with tarfile.open(path, "w:gz") as tf:
        info = tarfile.TarInfo(member)
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))


MANIFEST = {
    "line": "sm13-latest", "sm_version": "1.13.0.7478", "sm_commit": "b34de51b" * 5,
    "mm_version": "1.12.0-git1229", "mm_commit": "4e031eb5" * 5, "extension_api": 11,
    "extension_api_min": 9, "metamod_binary": "metamod.2.ep1", "min_glibc": "2.17",
}


class UpdateLinePointerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.fake = self.tmp / "fake"
        (self.fake / "store").mkdir(parents=True)
        (self.fake / "state.json").write_text(json.dumps({"releases": {}, "next_id": 0}))
        bindir = self.tmp / "bin"
        bindir.mkdir()
        (bindir / "gh").write_text(FAKE_GH)
        (bindir / "sleep").write_text("#!/bin/sh\nexit 0\n")
        for tool in ("gh", "sleep"):
            (bindir / tool).chmod(0o755)
        self.sm = self.tmp / "sourcemod-1.13.0-git7478-css34-linux.tar.gz"
        self.mm = self.tmp / "mmsource-1.12.0-git1229-css34-linux.tar.gz"
        package(self.sm, "addons/sourcemod/css34-package.json", MANIFEST)
        package(self.mm, "addons/metamod/css34-package.json",
                {k: MANIFEST[k] for k in ("line", "mm_version", "mm_commit", "metamod_binary")})
        self.env = dict(os.environ, PATH="{}:{}".format(bindir, os.environ["PATH"]), FAKE=str(self.fake),
                        GITHUB_REPOSITORY="o/r", TARGET="0" * 40, GITHUB_RUN_ID="1")

    def run_pointer(self, tag, smoke="pass", src_time="100"):
        env = dict(self.env, SMOKE=smoke, SRC_TIME=src_time)
        return subprocess.run(["bash", str(SCRIPT), "sm13-latest", tag, str(self.sm), str(self.mm)],
                              cwd=ROOT, env=env, capture_output=True, text=True)

    def state(self):
        return json.loads((self.fake / "state.json").read_text())["releases"]

    def asset(self, tag, name):
        return (self.fake / "store" / str(self.state()[tag]["assets"][name])).read_bytes()

    def test_pass_publishes_stable_names_versions_and_notes(self):
        res = self.run_pointer("1.13.0.7478-mm1.12.0-r5")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        ptr = self.state()["line-sm13-latest"]
        self.assertEqual(sorted(ptr["assets"]), sorted([
            "sourcemod-css34-linux.tar.gz", "mmsource-css34-linux.tar.gz", "SHA256SUMS",
            "VERSIONS.txt", "lines.json"]))
        self.assertEqual(self.asset("line-sm13-latest", "sourcemod-css34-linux.tar.gz"), self.sm.read_bytes())
        versions = self.asset("line-sm13-latest", "VERSIONS.txt").decode()
        sm_sha = hashlib.sha256(self.sm.read_bytes()).hexdigest()
        for line in ("tag=1.13.0.7478-mm1.12.0-r5", "pointer=line-sm13-latest", "sm_version=1.13.0.7478",
                     "mm_version=1.12.0-git1229", "sm_linux=" + self.sm.name, "sm_linux_sha256=" + sm_sha,
                     "stable_sm_linux=sourcemod-css34-linux.tar.gz", "extension_api_min=9"):
            self.assertIn(line + "\n", versions)
        self.assertIn(sm_sha + "  sourcemod-css34-linux.tar.gz",
                      self.asset("line-sm13-latest", "SHA256SUMS").decode())
        self.assertEqual(ptr["title"], "line-sm13-latest → 1.13.0.7478-mm1.12.0-r5")
        self.assertIn("**Now serves [`1.13.0.7478-mm1.12.0-r5`]", ptr["notes"])
        self.assertIn(" UTC (smoke: pass)", ptr["notes"])
        self.assertIn("`{}`".format(sm_sha), ptr["notes"])
        self.assertIn("9–11", ptr["notes"])
        index = json.loads(self.asset("lines-index", "lines.json"))
        self.assertEqual(index["sm13-latest"]["tag"], "1.13.0.7478-mm1.12.0-r5")
        # no temporary upload names are left behind
        self.assertFalse([n for n in ptr["assets"] if ".next-" in n])

    def test_failed_candidate_keeps_packages_and_says_so(self):
        self.assertEqual(self.run_pointer("1.13.0.7478-mm1.12.0-r5").returncode, 0)
        before = self.asset("line-sm13-latest", "sourcemod-css34-linux.tar.gz")
        package(self.sm, "addons/sourcemod/css34-package.json", dict(MANIFEST, sm_version="1.13.0.9999"))
        res = self.run_pointer("1.13.0.7478-mm1.12.0-r6", smoke="fail", src_time="200")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        ptr = self.state()["line-sm13-latest"]
        self.assertEqual(self.asset("line-sm13-latest", "sourcemod-css34-linux.tar.gz"), before)
        self.assertEqual(ptr["title"], "line-sm13-latest → 1.13.0.7478-mm1.12.0-r5")
        self.assertIn("Last candidate [`1.13.0.7478-mm1.12.0-r6`]", ptr["notes"])
        self.assertIn("sourcemod-css34-linux.tar.gz", ptr["notes"], "sha256 table kept on a failed run")
        self.assertIn("tag=1.13.0.7478-mm1.12.0-r5\n", self.asset("line-sm13-latest", "VERSIONS.txt").decode())

    def test_first_run_that_fails_has_no_packages(self):
        res = self.run_pointer("1.13.0.7478-mm1.12.0-r5", smoke="fail")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        ptr = self.state()["line-sm13-latest"]
        self.assertEqual(sorted(ptr["assets"]), ["lines.json"])
        self.assertEqual(ptr["title"], "line-sm13-latest (no passing build yet)")


class ReleaseVersionsTest(unittest.TestCase):
    """builder/scripts/release-versions.py on a tag release with Windows zips."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def run_versions(self, mm_manifest):
        import zipfile
        sm = self.tmp / "sourcemod-1.13.0-git7478-css34-linux.tar.gz"
        mm = self.tmp / "mmsource-1.12.0-git1229-css34-linux.tar.gz"
        smw = self.tmp / "sourcemod-1.13.0-git7478-css34-windows.zip"
        package(sm, "addons/sourcemod/css34-package.json", MANIFEST)
        package(mm, "addons/metamod/css34-package.json", mm_manifest)
        with zipfile.ZipFile(smw, "w") as zf:
            zf.writestr("addons/sourcemod/css34-package.json",
                        json.dumps(dict(MANIFEST, msvc_toolset="14.44.35207", windows_sdk="10.0.26100.0")))
        res = subprocess.run(["python3", str(ROOT / "builder/scripts/release-versions.py"), "--repo", "o/r",
                              "--tag", "1.13.0.7478-mm1.12.0-r6", "--sm-linux", str(sm), "--mm-linux", str(mm),
                              "--sm-windows", str(smw)], capture_output=True, text=True)
        return res, sm

    def test_tag_release(self):
        res, sm = self.run_versions(dict(MANIFEST, metamod_binaries=["metamod.1.ep1", "metamod.2.ep1"],
                                         legacy_bridge=True))
        self.assertEqual(res.returncode, 0, res.stderr)
        values = dict(line.split("=", 1) for line in res.stdout.splitlines() if not line.startswith("#"))
        self.assertEqual(values["tag"], "1.13.0.7478-mm1.12.0-r6")
        self.assertNotIn("pointer", values)
        self.assertEqual(values["sm_linux"], sm.name)
        self.assertEqual(values["sm_linux_sha256"], hashlib.sha256(sm.read_bytes()).hexdigest())
        self.assertEqual(values["stable_mm_linux"], "mmsource-css34-linux.tar.gz")
        self.assertEqual(values["stable_sm_windows"], "sourcemod-css34-windows.zip")
        self.assertEqual(values["msvc_toolset"], "14.44.35207")
        self.assertEqual(values["metamod_binaries"], "metamod.1.ep1,metamod.2.ep1")
        self.assertEqual(values["legacy_bridge"], "true")
        self.assertNotIn("mm_windows", values)
        # sourceable by sh
        out = subprocess.run(["sh", "-c", ". /dev/stdin; echo \"$sm_version $extension_api_min\""],
                             input=res.stdout, capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), "1.13.0.7478 9")

    def test_sm_and_mm_packages_must_agree(self):
        res, _ = self.run_versions(dict(MANIFEST, mm_version="1.12.0-git1228"))
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("disagree on mm_version", res.stderr)


if __name__ == "__main__":
    unittest.main()
