#!/usr/bin/env python3
"""Hotfixes for frozen lines (docs/MAINTAINING.md, "The frozen line").

hotfixes/<line>/ holds files a server copies over cstrike/ on top of a frozen
line's packages. These tests check that:
  * only frozen lines in builder/lines.json have a hotfixes/ directory;
  * every file is a SourceMod gamedata override under gamedata/<name>.games/custom/
    (read after the shipped files, so the frozen packages stay as published);
  * every key a core.games override sets has the same value in the cstrike Keys of
    builder/assets/gamedata/core.games/common.games.txt, so a hotfix carries
    exactly what the active lines ship.
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOTFIXES = ROOT / "hotfixes"
CORE_COMMON = ROOT / "builder" / "assets" / "gamedata" / "core.games" / "common.games.txt"
GAMEDATA = Path("addons") / "sourcemod" / "gamedata"


def tokens(text: str):
    """Tokens of a SourceMod SMC / KeyValues file: quoted strings, { and }."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                raise ValueError("unterminated comment")
            i = j + 2
        elif c in "{}":
            yield c
            i += 1
        elif c == '"':
            j = text.find('"', i + 1)
            if j < 0:
                raise ValueError("unterminated string")
            yield ("s", text[i + 1:j])
            i = j + 1
        else:
            raise ValueError("unexpected character {!r} at offset {}".format(c, i))


def parse(text: str) -> list:
    """Nested [(name, value or list)] in file order (duplicate sections are kept)."""
    stack = [[]]
    pending = None
    for tok in tokens(text):
        if tok == "{":
            if pending is None:
                raise ValueError("section without a name")
            node = []
            stack[-1].append((pending, node))
            stack.append(node)
            pending = None
        elif tok == "}":
            if pending is not None or len(stack) == 1:
                raise ValueError("unbalanced }")
            stack.pop()
        elif pending is None:
            pending = tok[1]
        else:
            stack[-1].append((pending, tok[1]))
            pending = None
    if pending is not None or len(stack) != 1:
        raise ValueError("unbalanced file")
    return stack[0]


def sections(node: list, name: str) -> list:
    return [v for k, v in node if k == name and isinstance(v, list)]


def cstrike_keys(text: str) -> dict:
    keys = {}
    for games in sections(parse(text), "Games"):
        for game in sections(games, "cstrike"):
            for block in sections(game, "Keys"):
                keys.update({k: v for k, v in block if isinstance(v, str)})
    return keys


def lines_json() -> dict:
    return json.loads((ROOT / "builder" / "lines.json").read_text(encoding="utf-8"))


def hotfix_files():
    return sorted(p for p in HOTFIXES.rglob("*") if p.is_file())


class FrozenHotfixTests(unittest.TestCase):
    def test_parser_reads_shipped_core_gamedata(self):
        keys = cstrike_keys(CORE_COMMON.read_text(encoding="utf-8"))
        self.assertEqual(keys.get("GameExtension"), "game.cstrike")
        self.assertEqual(keys.get("HintTextPreByte"), "yes")

    def test_only_frozen_lines_have_hotfixes(self):
        lines = lines_json()["lines"]
        self.assertTrue(HOTFIXES.is_dir(), "hotfixes/ is missing")
        for entry in sorted(HOTFIXES.iterdir()):
            with self.subTest(line=entry.name):
                self.assertTrue(entry.is_dir(), "hotfixes/ holds one directory per line")
                self.assertIn(entry.name, lines, "unknown line")
                self.assertEqual(lines[entry.name]["status"], "frozen",
                                 "an active line ships its fix in its packages, not as a hotfix")

    def test_hotfixes_are_custom_gamedata_overrides(self):
        files = hotfix_files()
        self.assertTrue(files, "hotfixes/ has no files")
        for path in files:
            rel = path.relative_to(HOTFIXES)
            with self.subTest(file=str(rel)):
                inner = Path(*rel.parts[1:])
                self.assertEqual(inner.parts[:3], GAMEDATA.parts, "not under addons/sourcemod/gamedata/")
                self.assertEqual(len(inner.parts), 6, "expected gamedata/<name>.games/custom/<file>.txt")
                self.assertTrue(inner.parts[3].endswith(".games"))
                self.assertEqual(inner.parts[4], "custom")
                self.assertEqual(path.suffix, ".txt", "SourceMod reads only .txt from custom/")
                tree = parse(path.read_text(encoding="utf-8"))
                self.assertEqual([k for k, _ in tree], ["Games"])

    def test_core_overrides_match_active_gamedata(self):
        shipped = cstrike_keys(CORE_COMMON.read_text(encoding="utf-8"))
        found = 0
        for path in hotfix_files():
            if path.parent.parent.name != "core.games":
                continue
            keys = cstrike_keys(path.read_text(encoding="utf-8"))
            with self.subTest(file=str(path.relative_to(ROOT))):
                self.assertTrue(keys, "sets no cstrike Keys")
                for key, value in keys.items():
                    found += 1
                    self.assertEqual(shipped.get(key), value,
                                     "{} differs from {}".format(key, CORE_COMMON.relative_to(ROOT)))
        self.assertGreater(found, 0)

    def test_sm11_hinttext_prebyte(self):
        path = (HOTFIXES / "sm11-oldstable" / GAMEDATA / "core.games" / "custom"
                / "css34-hinttext-prebyte.txt")
        self.assertEqual(cstrike_keys(path.read_text(encoding="utf-8")), {"HintTextPreByte": "yes"})

    def test_parser_rejects_broken_files(self):
        for text in ('"Games" {', '"Games" { } }', '"a" "b" "c"', '"Games" { /* x }', "Games { }"):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    parse(text)


if __name__ == "__main__":
    unittest.main()
