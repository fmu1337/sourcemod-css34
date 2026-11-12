# docs/ index

Two kinds of documents live here. **Reference** docs describe how the repository works today and are
kept in sync with the code; **history** docs record decisions, experiments and field reports. A history
doc carries a status note at the top saying what is still true.

## Reference (current)

| Doc | What it covers |
|-----|----------------|
| [../README.md](../README.md) | What to install, line pointers, pins, releases, known-bad tags, build, CI |
| [../AGENTS.md](../AGENTS.md) | Environment notes for agents (Docker, build / smoke commands) |
| [../testing/README.md](../testing/README.md) | Smoke, botplay, Wine / native Windows tests |
| [EXTENSIONS.md](EXTENSIONS.md) | Building third-party SourceMod extensions for these packages: extension API per line (1.13 needs a rebuild), the verified build recipe, third-party extensions running on 1.13 (ProtectCMDS, navfile_blocker, cssdm, socket), `undefined symbol: Msg` |
| [MIGRATION.md](MIGRATION.md) | Moving a server from SourceMod 1.7 / 1.8 / 1.11 to `sm13-latest`: which old files stay, `*.ext.1.ep1.so`, `metamod.vdf` / `metaplugins.ini`, a tested order with rollback |
| [FREEZE.md](FREEZE.md) | Freezing a line (T2.7): the input archive, `--network none` rebuild, ABI comparison |
| [PATCH_STRATEGY.md](PATCH_STRATEGY.md) | The patch model (one git patch series per line / MM pin, `lines.json`) and how pins are bumped (weekly bump PRs, by hand) |
| [PATCHES.md](PATCHES.md) | Every patch of every series: what it changes and what breaks without it |
| [upstream-reports/](upstream-reports/README.md) | Draft bug reports for SourceMod / Metamod / KHook, one file per report (the owner submits them) |
| [../testing/docs/bufferfix.md](../testing/docs/bufferfix.md) | memcpy→memmove ELF rewrite of the v34 server |
| [../testing/docs/srcds-params.md](../testing/docs/srcds-params.md) | v34 `srcds` launch flags |

The MM 2.0 lines `sm13-mm20` (retired) and `sm13-mm20-khook` (frozen) are built only from the
[`archive/khook`](https://github.com/fmu1337/sourcemod-css34/tree/archive/khook) branch, and their docs live
there: [SM13_MM20.md](https://github.com/fmu1337/sourcemod-css34/blob/archive/khook/docs/SM13_MM20.md),
[MM20_KHOOK.md](https://github.com/fmu1337/sourcemod-css34/blob/archive/khook/docs/MM20_KHOOK.md) (KHook
SourceMod + Metamod 2.0, DHooks x86, Windows).

## History

| Doc | What it records |
|-----|-----------------|
| [archive/ROADMAP.md](archive/ROADMAP.md) | The work plan of epic #73 (done): owner decisions D1–D7 and the task IDs `Tn.m` cited in code and commits |
| [archive/PATCH_STRATEGY_HISTORY.md](archive/PATCH_STRATEGY_HISTORY.md) | The 2026-07 single-pin vs layered-patches debate, upgrade traps of the SM 1.11 era (6572 / 6588 / 6970), the 2026-10-13 status snapshot |
| [archive/BYTE_MATCH.md](archive/BYTE_MATCH.md) | Why byte-identical `.so` vs rom4s 6572 is not a goal (still valid) |
| [SDKHOOKS_EP1_RELEASE_BLOCKERS.md](SDKHOOKS_EP1_RELEASE_BLOCKERS.md) | 2026-07 field report: PLAPI 11 vs MM 1.11 mix, SDKHooks vtables on the 6572 tag |
| [archive/V34_COMPARISON_v1.11.6572_vs_v1.12.7239.md](archive/V34_COMPARISON_v1.11.6572_vs_v1.12.7239.md) | What changed for v34 between SM 6572 and 7239 (first 1.12 port, PR #23) |
| [archive/v34-variant-6522-notes.md](archive/v34-variant-6522-notes.md) | myarena SM 6522 bundle, forum notes (myarena, HLmod / FrozDark) |
