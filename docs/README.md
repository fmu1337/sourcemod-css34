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
| [SM13_LATEST.md](SM13_LATEST.md) | `sm13-latest` (default line) |
| [SM13_MM20.md](SM13_MM20.md) | `sm13-mm20` (frozen on MM 2.0 git1407) |
| [MM20_KHOOK.md](MM20_KHOOK.md) | `sm13-mm20-khook`: KHook SourceMod + Metamod 2.0, DHooks x86, Windows |
| [PATCH_STRATEGY.md](PATCH_STRATEGY.md) | How the patch sets are laid out today and how to upgrade SM (status section on top; the rest is history) |
| [JULES_DAILY_VERSION_BUMP.md](JULES_DAILY_VERSION_BUMP.md) | Every place a pin is copied to; daily bump prompt |
| [UPSTREAM_REPORTS.md](UPSTREAM_REPORTS.md) | Draft bug reports for SourceMod / Metamod / KHook |
| [REVIEW_2026-10.md](REVIEW_2026-10.md) | Doc / project inconsistencies found on 2026-10-13 and simplification proposals |
| [../testing/docs/bufferfix.md](../testing/docs/bufferfix.md) | memcpy→memmove ELF rewrite of the v34 server |
| [../testing/docs/srcds-params.md](../testing/docs/srcds-params.md) | v34 `srcds` launch flags |

## History

| Doc | What it records |
|-----|-----------------|
| [BYTE_MATCH.md](BYTE_MATCH.md) | Why byte-identical `.so` vs rom4s 6572 is not a goal (still valid) |
| [SDKHOOKS_EP1_RELEASE_BLOCKERS.md](SDKHOOKS_EP1_RELEASE_BLOCKERS.md) | 2026-07 field report: PLAPI 11 vs MM 1.11 mix, SDKHooks vtables on the 6572 tag |
| [V34_COMPARISON_v1.11.6572_vs_v1.12.7239.md](V34_COMPARISON_v1.11.6572_vs_v1.12.7239.md) | What changed for v34 between SM 6572 and 7239 (first 1.12 port, PR #23) |
| [v34-variant-6522-notes.md](v34-variant-6522-notes.md) | myarena SM 6522 bundle, forum notes (myarena, HLmod / FrozDark) |
