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
    "core-legacy/CPlugin.cpp": (
        "\t\t\t\t\t\t\tif (g_bIsBridgedAsVsp)\n\t\t\t\t\t\t\t{\n"
        "\t\t\t\t\t\t\t\t(*event).event->OnVSPListening(g_pRealVspCallbacks);\n\t\t\t\t\t\t\t}\n"),
    "core-legacy/sourcemm.cpp": (
        "\tConCommandBaseMgr::OneTimeInit(x);\n\n\tif (g_GameDll.pGameClients)\n\t{\n"
        "\t\tSH_ADD_HOOK_STATICFUNC(IServerGameClients, ClientCommand, g_GameDll.pGameClients, h, false);\n\t}\n"
        "bool GameInit_handler()\n{\n\tif (g_bGameInit)\n\t\tRETURN_META_VALUE(MRES_IGNORED, true);\n}\n"
        "void LevelShutdown_handler(void)\n{\n\tif (!bInFirstLevel)\n\t{\n\t}\n}\n"),
    "core-legacy/concommands.cpp": (
        "bool SMConVarAccessor::RegisterConCommandBase(ConCommandBase *pCommand)\n{\n"
        "\tm_RegisteredCommands.push_back(pCommand);\n\treturn true;\n}\n"),
    "core-legacy/CSmmAPI.cpp": (
        "void CSmmAPI::LoadAsVSP()\n{\n\tsize_t len;\n}\n"
        "void CSmmAPI::EnableVSPListener()\n{\n\tif (g_bGameInit && !m_VSP && !g_bIsBridgedAsVsp)\n"
        "\t{\n\t\tLoadAsVSP();\n\t}\n\tm_VSP = true;\n}\n"),
}
MODERN = {
    "core/AMBuilder": "  binary.sources += [\n    'metamod_oslink.cpp',\n    'metamod_plugins.cpp',\n    'metamod_util.cpp',\n  ]\n",
    "core/metamod_plugins.cpp": (
        '#include "metamod_plugins.h"\n#include "metamod_util.h"\n\n'
        "\t\t\tif (pl->m_API != NULL)\n\t\t\t{\n"
        "\t\t\t\tint api = pl->m_API->GetApiVersion();\n\t\t\t\tif (api < PLAPI_MIN_VERSION)\n"
        "\t\t\t\t{\n\t\t\t\t}\n\t\t\t}\n"
        "bool CPluginManager::_Unload(CPluginManager::CPlugin *pl, bool force, char *error, size_t maxlen)\n{\n"
        "\tif (pl->m_API && pl->m_Lib)\n\t{\n"
        "\t\tif (pl->m_API->Unload(error, maxlen) || force)\n\t\t{\n"
        "\t\t\t//Make sure to detach it from sourcehook!\n"
        "\t\t\tg_SourceHook.UnloadPlugin(pl->m_Id, new Unloader(pl, true));\n"
        "\t\t\treturn true;\n\t\t}\n\t}\n\treturn false;\n}\n"),
    "core/metamod.cpp": (
        '#include "metamod_plugins.h"\n#include "metamod_util.h"\n#include "metamod_console.h"\n'
        "void\nmm_UnloadMetamod()\n{\n\t/* Unload plugins */\n\tg_PluginMngr.UnloadAll();\n\n"
        "\tprovider->Notify_DLLShutdown_Pre();\n\n\tg_SourceHook.CompleteShutdown();\n}\n"
        "void MetamodSource::NotifyVSPListening(IServerPluginCallbacks *callbacks, int version)\n{\n"
        "\tif (version != -1)\n\t\tvsp_version = version;\n\t\n"
        "\tvsp_callbacks = callbacks;\n\tITER_EVENT(OnVSPListening, (callbacks));\n}\n"),
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
        self.assertIn("css34_nested_request_vsp();\n\t\treturn;", (root / "core-legacy/CSmmAPI.cpp").read_text())
        self.assertIn("if (g_bIsBridgedAsVsp || (g_bCss34Nested && g_pRealVspCallbacks))",
                      (root / "core-legacy/CPlugin.cpp").read_text())
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
        # Forced unloads reach the legacy core; the proxy goes before SourceHook
        # may delete the plugin record.
        self.assertIn("if (css34_UnloadPlugin(pl, force, error, maxlen) || force)", text)
        self.assertLess(text.index("css34_ReleaseOldPlugin(pl);"), text.index("g_SourceHook.UnloadPlugin("))
        metamod = (root / "core/metamod.cpp").read_text()
        self.assertLess(metamod.index("g_PluginMngr.UnloadAll();"), metamod.index("css34_ShutdownOldCore();"))
        self.assertLess(metamod.index("css34_ShutdownOldCore();"), metamod.index("g_SourceHook.CompleteShutdown();"))
        self.assertIn("css34_OldVspListening(callbacks, vsp_version);", metamod)
        self.assertEqual(self.run_patch("modern", root).returncode, 0)
        self.assertEqual(text, (root / "core/metamod_plugins.cpp").read_text())
        self.assertEqual(metamod, (root / "core/metamod.cpp").read_text())

    def test_plapi_range_is_the_legacy_cores(self):
        header = (ROOT / "builder/patches/mm-oldbridge/css34_old_plugins.h").read_text()
        self.assertIn("#define CSS34_OLD_PLAPI_MIN 7\n", header)
        self.assertIn("#define CSS34_OLD_PLAPI_MAX 11\n", header)

    def test_both_sides_speak_the_same_bridge_api(self):
        nested = (ROOT / "builder/patches/mm-oldbridge/css34_nested.cpp").read_text()
        modern = (ROOT / "builder/patches/mm-oldbridge/css34_old_plugins.cpp").read_text()
        self.assertIn("#define CSS34_OLD_BRIDGE_API 2\n", nested)
        self.assertIn("#define CSS34_OLD_BRIDGE_API 2\n", modern)
        for name in ("css34_old_set_vsp_request", "css34_old_vsp", "css34_old_shutdown"):
            self.assertIn("SMM_API void " + name + "(", nested)
            self.assertIn('"' + name + '"', modern)

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
