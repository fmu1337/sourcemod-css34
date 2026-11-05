#!/usr/bin/env python3
"""check-legacy-plugins.sh and the prebuilt testing/plugins/legacy-smx/ tree."""
import filecmp
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "testing/scripts/check-legacy-plugins.sh"
LEGACY = ROOT / "testing/plugins/legacy-smx"

PLUGINS_LIST = """[SM] Listing 30 plugins:
  01 "Admin Menu" (1.7.3-dev+5334) by AlliedModders LLC
  02 "Basic Commands" (1.7.3-dev+5334) by AlliedModders LLC
  03 "Fun Commands" (1.7.3-dev+5334) by AlliedModders LLC
  04 "Basic Chat" (1.11.0.6970) by AlliedModders LLC
  05 "Basic Comm Control" (1.11.0.6970) by AlliedModders LLC
  06 "Player Commands" (1.11.0.6970) by AlliedModders LLC
  07 "css34 legacy forward probe" (1.0.0) by sourcemod-css34
"""

PROBE = (
    "L 11/05/2026 - 10:00:00: [css34_legacy_forward_probe_sm17.smx] [css34_legacy_fwd] "
    "compiler=1.7.3-dev+5334 round=3 ok=12 fail=0 listeners=3 bad_args=0\n"
    "L 11/05/2026 - 10:00:00: [css34_legacy_forward_probe_sm111.smx] [css34_legacy_fwd] "
    "compiler=1.11.0.6970 round=3 ok=12 fail=0 listeners=3 bad_args=0\n"
    "L 11/05/2026 - 10:00:00: [css34_legacy_forward_probe.smx] [css34_legacy_fwd] "
    "compiler=1.13.0.7478 round=3 ok=12 fail=0 listeners=3 bad_args=0\n"
)


VARARGS = (
    "L x: [css34_legacy_fwd] compiler=1.7.3-dev+5334 varargs calls=6 runs=3 errors=3 last_error=4\n"
)


def run(botplay_log, sm_log, env=None):
    with tempfile.TemporaryDirectory() as tmp:
        b = pathlib.Path(tmp, "botplay.log")
        b.write_text(botplay_log)
        logs = []
        if sm_log is not None:
            s = pathlib.Path(tmp, "L20261105.log")
            s.write_text(sm_log)
            logs.append(str(s))
        r = subprocess.run(["bash", str(SCRIPT), str(b), *logs],
                           capture_output=True, text=True,
                           env={**os.environ, **(env or {})})
        return r.returncode, r.stdout + r.stderr


def expect(name, rc_want, botplay_log, sm_log, needle=None, env=None):
    rc, out = run(botplay_log, sm_log, env)
    ok = (rc == 0) == (rc_want == 0) and (needle is None or needle in out)
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        print(out)
    return ok


def main():
    results = []
    # The committed tree: checksums hold, probe source matches testing/plugins.
    r = subprocess.run(["sha256sum", "--quiet", "-c", "SHA256SUMS"], cwd=LEGACY,
                       capture_output=True, text=True)
    results.append(r.returncode == 0)
    print(("ok   " if r.returncode == 0 else "FAIL ") + "legacy-smx SHA256SUMS")
    probe = ROOT / "testing/plugins/css34_legacy_forward_probe.sp"
    for copy in sorted(LEGACY.glob("*/src/css34_legacy_forward_probe.sp")):
        same = filecmp.cmp(copy, probe, shallow=False)
        results.append(same)
        print(("ok   " if same else "FAIL ") + f"{copy.relative_to(ROOT)} matches probe source")
    for line in (LEGACY / "plugins.tsv").read_text().splitlines():
        if line and not line.startswith("#"):
            ver, _src, smx = line.split("\t")
            present = (LEGACY / ver / smx).is_file() and (LEGACY / ver / "SPCOMP_VERSION").is_file()
            results.append(present)
            print(("ok   " if present else "FAIL ") + f"{ver}/{smx} present")

    results.append(expect("clean session passes", 0, PLUGINS_LIST, PROBE))
    results.append(expect("<Error> plugin fails", 1,
                          PLUGINS_LIST + '  08 <Error> "x" (1.0) by y\n', PROBE, "<Error>"))
    results.append(expect("<Failed> plugin fails", 1,
                          PLUGINS_LIST + '  08 <Failed> "x" (1.0) by y\nErrors:\nx.smx: boom\n',
                          PROBE, "<Failed>"))
    results.append(expect("missing native fails", 1, PLUGINS_LIST,
                          PROBE + 'L x: [SM] Unable to load plugin "a.smx": Native "Foo" was not found\n',
                          "was not found"))
    results.append(expect("forward param error fails", 1, PLUGINS_LIST,
                          PROBE + "L x: [SM] Exception reported: Invalid parameter or parameter type\n",
                          "Invalid parameter"))
    results.append(expect("exception in legacy plugin fails", 1, PLUGINS_LIST,
                          PROBE + "L x: [SM] Exception reported: oops\nL x: [SM] Blaming: funcommands.smx\n",
                          "Blaming"))
    results.append(expect("probe fail counter fails", 1, PLUGINS_LIST,
                          PROBE.replace("ok=12 fail=0 listeners=3", "ok=11 fail=1 listeners=3", 1)))
    results.append(expect("missing 1.11 probe fails", 1, PLUGINS_LIST,
                          "".join(l + "\n" for l in PROBE.splitlines() if "1.11.0" not in l),
                          "spcomp 1.11.0.6970"))
    results.append(expect("too few listeners fails", 1, PLUGINS_LIST,
                          PROBE.replace("listeners=3", "listeners=2")))
    results.append(expect("old stock plugin not running fails", 1,
                          PLUGINS_LIST.replace('"Fun Commands" (1.7.3-dev+5334)', '"Fun Commands" (1.13.0.7478)'),
                          PROBE, "spcomp 1.7.3-dev+5334"))
    results.append(expect("no SM logs fails", 1, PLUGINS_LIST, None))
    results.append(expect("varargs errors are INFO by default", 0, PLUGINS_LIST,
                          PROBE + VARARGS, "INFO: varargs forward compiler=1.7.3-dev+5334"))
    results.append(expect("varargs errors fail when required", 1, PLUGINS_LIST,
                          PROBE + VARARGS, "varargs forward", {"LEGACY_FWD_REQUIRE_VARARGS": "1"}))
    results.append(expect("clean varargs pass when required", 0, PLUGINS_LIST,
                          PROBE + VARARGS.replace("runs=3 errors=3 last_error=4", "runs=6 errors=0 last_error=0"),
                          "OK: varargs forward", {"LEGACY_FWD_REQUIRE_VARARGS": "1"}))
    if not all(results):
        sys.exit(1)
    print("check-legacy-plugins: all cases passed")


if __name__ == "__main__":
    main()
