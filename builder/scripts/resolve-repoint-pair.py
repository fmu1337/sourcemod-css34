#!/usr/bin/env python3
"""Resolve unambiguous compatible SourceMod + Metamod package pair in a release tag.

Usage:
    resolve-repoint-pair.py <base_tag> <tag_map_line> <lines_json_path> <check_dir> <sm_candidates...> ---MM--- <mm_candidates...>
"""

import json
import os
import re
import subprocess
import sys


def get_manifest(check_dir, filename, subpath):
    filepath = os.path.join(check_dir, filename)
    try:
        out = subprocess.check_output(["tar", "-xzOf", filepath, subpath], stderr=subprocess.DEVNULL)
        return json.loads(out.decode("utf-8"))
    except Exception:
        return None


def resolve_pair(base_tag, tag_map_line, lines_json_path, check_dir, sm_candidates, mm_candidates):
    sha_re = re.compile(r'^[0-9a-fA-F]{7,40}$')
    lines_data = json.load(open(lines_json_path, "r", encoding="utf-8"))

    sm_manifests = {}
    for sm_file in sm_candidates:
        m = get_manifest(check_dir, sm_file, "addons/sourcemod/css34-package.json")
        if m:
            sm_manifests[sm_file] = m

    mm_manifests = {}
    for mm_file in mm_candidates:
        m = get_manifest(check_dir, mm_file, "addons/metamod/css34-package.json")
        if m:
            mm_manifests[mm_file] = m

    valid_pairs = []

    for sm_file, sm in sm_manifests.items():
        for mm_file, mm in mm_manifests.items():
            req_fields = ["line", "sm_version", "sm_commit", "mm_version", "mm_commit", "metamod_binary"]
            err = False
            for f in req_fields:
                v_sm, v_mm = sm.get(f), mm.get(f)
                if not v_sm or not isinstance(v_sm, str) or v_sm in ("null", "custom", "unknown"):
                    err = True
                    break
                if not v_mm or not isinstance(v_mm, str) or v_mm in ("null", "custom", "unknown"):
                    err = True
                    break
                if v_sm != v_mm:
                    err = True
                    break
            if err:
                continue

            if not sha_re.match(str(sm["sm_commit"])) or not sha_re.match(str(sm["mm_commit"])):
                continue

            line = sm["line"]
            if tag_map_line and line != tag_map_line:
                continue

            if line not in lines_data.get("lines", {}):
                continue

            line_cfg = lines_data["lines"][line]
            mm_pin_name = line_cfg.get("metamod")
            if not mm_pin_name or mm_pin_name not in lines_data.get("pins", {}):
                continue

            mm_pin = lines_data["pins"][mm_pin_name]
            mode = mm_pin.get("mode")

            expected_mm_bin = "metamod.1.ep1" if mode == "1.10" else "metamod.2.ep1"
            if sm["metamod_binary"] != expected_mm_bin:
                continue

            if not sm["mm_version"].startswith(f"{mode}."):
                continue

            expected_sm_prefix = "1.11." if line == "sm11-oldstable" else ("1.12." if line == "sm12-latest" else "1.13.")
            if not sm["sm_version"].startswith(expected_sm_prefix):
                continue

            valid_pairs.append((line, sm_file, mm_file))

    if len(valid_pairs) == 0:
        sys.exit(f"No valid compatible SM+MM package pair found in release tag '{base_tag}'")
    elif len(valid_pairs) > 1:
        pairs_str = ", ".join(f"({l}: {s}, {m})" for l, s, m in valid_pairs)
        sys.exit(f"Ambiguous SM/MM package pairs found in release tag '{base_tag}': {pairs_str}")

    res = valid_pairs[0]
    return {"line": res[0], "sm_asset": res[1], "mm_asset": res[2]}


def main():
    if len(sys.argv) < 5:
        sys.exit("Usage: resolve-repoint-pair.py <base_tag> <tag_map_line> <lines_json_path> <check_dir> <sm_candidates...> ---MM--- <mm_candidates...>")

    base_tag, tag_map_line, lines_json_path, check_dir = sys.argv[1:5]
    args = sys.argv[5:]

    if "---MM---" not in args:
        sys.exit("Missing ---MM--- separator argument")

    sep_idx = args.index("---MM---")
    sm_candidates = args[:sep_idx]
    mm_candidates = args[sep_idx + 1:]

    result = resolve_pair(base_tag, tag_map_line, lines_json_path, check_dir, sm_candidates, mm_candidates)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
