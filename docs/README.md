# docs/ index

**Reference** docs describe how the repository works today and are kept in sync with the code. Older
history (field reports, version comparisons, the patch-strategy debate) is in git history only.

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

The MM 2.0 lines `sm13-mm20` (retired) and `sm13-mm20-khook` (frozen) are built only from the
[`archive/khook`](https://github.com/fmu1337/sourcemod-css34/tree/archive/khook) branch, and their docs live
there: [SM13_MM20.md](https://github.com/fmu1337/sourcemod-css34/blob/archive/khook/docs/SM13_MM20.md),
[MM20_KHOOK.md](https://github.com/fmu1337/sourcemod-css34/blob/archive/khook/docs/MM20_KHOOK.md) (KHook
SourceMod + Metamod 2.0, DHooks x86, Windows).

## History

| Doc | What it records |
|-----|-----------------|
| [archive/ROADMAP.md](archive/ROADMAP.md) | The work plan of epic #73 (done): owner decisions D1–D7 and the task IDs `Tn.m` cited in code and commits |
