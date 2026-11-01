#!/usr/bin/env python3
"""apply-mmsource-oldbridge.sh on minimal Metamod trees (T2.9 legacy-plugin bridge).

The fixtures hold the exact upstream lines the patch anchors on (MM 1.10
core-legacy at 80e8ff0, MM 1.12 core at 75dd7b26 / cb477558).
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "builder/patches/apply-mmsource-oldbridge.sh"

LEGACY = {
    "core-legacy/AMBuilder": (
        "if 'episode1' in MMS.sdks:\n  sdk = MMS.sdks['episode1']\n"
        "  binary = MMS.HL2Library(builder, name, sdk)\n  binary.sources += [\n"
        "    'gamedll_bridge.cpp',\n    'vsp_bridge.cpp',\n    'sourcehook/sourcehook.cpp',\n  ]\n"
        "  nodes = builder.Add(binary)\n  MMS.binaries += [nodes]\n"),
    "core-legacy/sourcemm.h": "extern int g_GameDllVersion;\n\nextern bool g_bGameInit;\nextern bool g_bLevelChanged;\n",
    "core-legacy/sourcemm.cpp": (
        "\tConCommandBaseMgr::OneTimeInit(x);\n\n\tif (g_GameDll.pGameClients)\n\t{\n"
        "\t\tSH_ADD_HOOK_STATICFUNC(IServerGameClients, ClientCommand, g_GameDll.pGameClients, h, false);\n\t}\n"
        "bool GameInit_handler()\n{\n\tif (g_bGameInit)\n\t\tRETURN_META_VALUE(MRES_IGNORED, true);\n}\n"
        "void LevelShutdown_handler(void)\n{\n\tif (!bInFirstLevel)\n\t{\n\t}\n}\n"),
    "core-legacy/concommands.cpp": (
        "bool SMConVarAccessor::RegisterConCommandBase(ConCommandBase *pCommand)\n{\n"
        "\tm_RegisteredCommands.push_back(pCommand);\n\treturn true;\n}\n"),
    "core-legacy/CSmmAPI.cpp": "void CSmmAPI::LoadAsVSP()\n{\n\tsize_t len;\n}\n",
}
MODERN = {
    "core/AMBuilder": "  binary.sources += [\n    'metamod_oslink.cpp',\n    'metamod_plugins.cpp',\n    'metamod_util.cpp',\n  ]\n",
    "core/metamod_plugins.cpp": (
        '#include "metamod_plugins.h"\n#include "metamod_util.h"\n\n'
        "\t\t\tif (pl->m_API != NULL)\n\t\t\t{\n"
        "\t\t\t\tint api = pl->m_API->GetApiVersion();\n\t\t\t\tif (api < PLAPI_MIN_VERSION)\n"
        "\t\t\t\t{\n\t\t\t\t}\n\t\t\t}\n"),
}


class OldBridgePatchTest(unittest.TestCase):
    def tree(self, files):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        for rel, text in files.items():
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text)
        return root

    def run_patch(self, mode, root):
        return subprocess.run(["bash", str(SCRIPT), mode, str(root)], capture_output=True, text=True)

    def test_legacy_patch_applies_once_and_adds_the_probe(self):
        root = self.tree(LEGACY)
        res = self.run_patch("legacy", root)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertTrue((root / "core-legacy/css34_nested.cpp").is_file())
        self.assertTrue((root / "core-legacy/css34_legacy_probe.cpp").is_file())
        ambuilder = (root / "core-legacy/AMBuilder").read_text()
        self.assertIn("'css34_nested.cpp'", ambuilder)
        self.assertIn("MMS.HL2Library(builder, 'css34_legacy_probe', sdk)", ambuilder)
        sourcemm = (root / "core-legacy/sourcemm.cpp").read_text()
        self.assertIn("else if (g_GameDll.pGameClients)", sourcemm)
        self.assertIn("if (!bInFirstLevel && !g_bCss34Nested)", sourcemm)
        self.assertIn("if (g_bCss34Nested)", (root / "core-legacy/concommands.cpp").read_text())
        before = {rel: (root / rel).read_text() for rel in LEGACY}
        res = self.run_patch("legacy", root)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(before, {rel: (root / rel).read_text() for rel in LEGACY})

    def test_modern_patch_routes_old_plugins_before_the_minimum_check(self):
        root = self.tree(MODERN)
        res = self.run_patch("modern", root)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        text = (root / "core/metamod_plugins.cpp").read_text()
        self.assertLess(text.index("css34_IsOldPluginApi(api)"), text.index("else if (api < PLAPI_MIN_VERSION)"))
        self.assertIn("'css34_old_plugins.cpp'", (root / "core/AMBuilder").read_text())
        self.assertTrue((root / "core/css34_old_plugins.h").is_file())
        self.assertEqual(self.run_patch("modern", root).returncode, 0)
        self.assertEqual(text, (root / "core/metamod_plugins.cpp").read_text())

    def test_missing_anchor_fails_closed(self):
        for files, mode, rel in ((LEGACY, "legacy", "core-legacy/CSmmAPI.cpp"),
                                 (MODERN, "modern", "core/metamod_plugins.cpp")):
            with self.subTest(mode=mode):
                broken = dict(files)
                broken[rel] = "/* upstream moved this code */\n"
                res = self.run_patch(mode, self.tree(broken))
                self.assertNotEqual(res.returncode, 0)
                self.assertIn("oldbridge anchor not found", res.stderr)

    def test_wrong_tree_or_mode_fails(self):
        self.assertNotEqual(self.run_patch("legacy", self.tree(MODERN)).returncode, 0)
        self.assertNotEqual(self.run_patch("modern", self.tree(LEGACY)).returncode, 0)
        self.assertNotEqual(self.run_patch("both", self.tree(LEGACY)).returncode, 0)


if __name__ == "__main__":
    unittest.main()
