#!/usr/bin/env python3
"""Execute the production generated DHooks builder with the SM 1.11 API."""
import ast
from pathlib import Path
import re
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[2]


def generated_builder():
    source = (ROOT / "builder/patches/apply-sourcemod.sh").read_text()
    for match in re.finditer(r"<<'(PY\w*)'\n(.*?)\n\1(?:\n|$)", source, re.S):
        tree = ast.parse(match[2])
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and any(
                    isinstance(t, ast.Name) and t.id == "dhooks_code" for t in node.targets):
                return ast.literal_eval(node.value)
    raise AssertionError("DHooks generator missing")


class TestDHooksBuilder(unittest.TestCase):
    def test_sm11_object_sdk_supported_architectures_and_sources(self):
        built = []
        sdk = SimpleNamespace(name="episode1", ext="2.ep1")
        class SM11:
            sdks = {"ep1": SimpleNamespace(name="ep1", ext="1.ep1"), "episode1": sdk}
            extensions = []
            def HL2Library(self, builder, cxx, name, actual_sdk):
                self_test.assertIs(actual_sdk, sdk)
                compiler = SimpleNamespace(target=cxx.target, defines=[], cflags=[],
                    cxxincludes=[], includes=[], like=lambda family: family == "gcc")
                binary = SimpleNamespace(compiler=compiler, sources=[], name=name)
                built.append(binary)
                return binary
        self_test = self
        targets = [SimpleNamespace(target=SimpleNamespace(platform=p, arch=a))
                   for p, a in (("linux", "x86"), ("windows", "x86"),
                                ("linux", "x86_64"), ("windows", "x86_64"), ("mac", "x86"))]
        sm = SM11()
        builder = SimpleNamespace(targets=targets, sourcePath="/source", Add=lambda binary: binary)
        exec(compile(generated_builder(), "dhooks/AMBuilder", "exec"), {"SM": sm, "builder": builder})
        self.assertEqual(len(built), 2)
        self.assertEqual(sm.extensions, built)
        for binary in built:
            self.assertEqual(binary.name, "dhooks.ext.2.ep1")
            self.assertIn("../../public/asm/asm.c", binary.sources)
            self.assertIn("../../public/libudis86/decode.c", binary.sources)
            self.assertIn("../../sourcepawn/vm/x86/assembler-x86.cpp", binary.sources)
            suffix = "x86MsThiscall.cpp" if binary.compiler.target.platform == "windows" else "x86GccThiscall.cpp"
            self.assertIn("DynamicHooks/conventions/" + suffix, binary.sources)

    def test_missing_episode1_fails(self):
        with self.assertRaisesRegex(Exception, "requires the episode1 SDK"):
            exec(compile(generated_builder(), "dhooks/AMBuilder", "exec"),
                 {"SM": SimpleNamespace(sdks={}), "builder": SimpleNamespace(targets=[])})


if __name__ == "__main__":
    unittest.main()
