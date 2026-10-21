# css34 source patch inventory

This is the initial T3.4 inventory; the remaining source patches still need to
be inventoried and migrated to git patch series.

## SM 1.12: entity-output map-end cleanup list type

- Introduced by css34 commit `bc2d291` (PR #126, T1.5 / #84).
- Implementation: `builder/patches/apply-sourcemod-v112.sh`, `PYOUT` block.
- Upstream: SourceMod #2589, cherry-picked as `e68dada2979eb3093d81d2e3766f741e7d431e4a`
  (SM 1.12.0.7257).
- Change: use `SourceHook::List<omg_hooks *>` in
  `EntityOutputManager::OnMapEnd`, matching the list stored in `OutputHookList`.
- Evidence without patch: GCC 10 fails with `'list' is not a member of 'std'`.
  Adding `<list>` alone would leave the cleanup interpreting a SourceHook list
  as a different container type. SM 1.13 already uses `std::list` consistently
  and is not rewritten.
- Drift policy: fail on missing/changed map-end anchors, unknown storage types,
  or malformed already-patched code; validate the consistent SM 1.13 layout.
- Validation: checker fixtures plus runtime entity-output probe across map
  changes; manylinux GCC 10 build and PR CI remain required.
- Upstream report candidate for **#101 / T3.6**: the 1.12-dev cherry-pick uses
  the wrong container type. Report against that branch with the compiler error
  and storage-type mismatch, rather than proposing a change to 1.13.
