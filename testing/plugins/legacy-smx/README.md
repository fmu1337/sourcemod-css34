# Plugins built by old compilers

Production servers run `.smx` files built by spcomp 1.7 – 1.11 and never
recompile them. Botplay (`testing/scripts/botplay-test.sh`) loads these prebuilt
files as they are, next to the current packages:

| Compiler (SourceMod release) | Plugins | Installed as |
|---|---|---|
| spcomp 1.7.3-dev+5334 (`sourcemod-1.7.3-git5334-linux.tar.gz`) | stock `adminmenu`, `basecommands`, `funcommands` | replace the package's copies |
| spcomp 1.7.3-dev+5334 | `css34_legacy_forward_probe` | `css34_legacy_forward_probe_sm17.smx` |
| spcomp 1.11.0.6970 (`sourcemod-1.11.0-git6970-linux.tar.gz`) | stock `basechat`, `basecomm`, `playercommands` | replace the package's copies |
| spcomp 1.11.0.6970 | `css34_legacy_forward_probe` | `css34_legacy_forward_probe_sm111.smx` |

The table is `plugins.tsv`. Each `<compiler>/` directory holds the `.smx`, the
exact sources it was built from (`src/`), and `SPCOMP_VERSION`; `SHA256SUMS`
covers all of them. The stock plugins replace the package's own copies because
two copies of `adminmenu` cannot both register its natives. The new 1.13 plugins
then call natives of the 1.7.3 `adminmenu`, so the setup also tests mixed
plugin versions.

`css34_legacy_forward_probe.sp` lives in `testing/plugins/`, so
`compile-botplay-plugins.sh` also builds it with the package's spcomp. All three
copies listen to each other's global forward, which has mixed parameter types.
Each copy also calls a private forward and one of its own functions every round.
Copies built with pre-1.13 includes also call a `Param_VarArgs` forward and log
the result. That check is informational only: 1.13 has no varargs forwards.

`install-botplay-plugins.sh` checks `SHA256SUMS` and that the probe sources here
match `testing/plugins/css34_legacy_forward_probe.sp`. `INSTALL_LEGACY_SMX=0`
skips them. `check-legacy-plugins.sh` (run from `botplay-test.sh`) fails the
session on any of these:

- a `<Failed>` / `<Error>` plugin;
- `Native "…" was not found`, `Unable to load plugin`, `Failed to load plugin`,
  `Invalid parameter or parameter type`, `Maximum number of parameters reached`
  in the SourceMod logs;
- an exception blamed on a legacy plugin;
- a legacy stock plugin that is not running;
- a probe copy that does not report, reports a failure, or sees fewer than three
  listeners.

`LEGACY_FWD_REQUIRE_VARARGS=1` also requires varargs forward calls to run.
`python3 testing/scripts/test-check-legacy-plugins.py` tests the gate.

Rebuild after changing the probe or `plugins.tsv` (needs Docker, runs spcomp in
`i386/debian:11`):

```bash
testing/scripts/build-legacy-smx.sh
```
