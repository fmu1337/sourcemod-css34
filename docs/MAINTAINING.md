# Maintaining

How pins, patches, releases, pointers, the frozen line and CI work. What we patch and why:
[CHANGES.md](CHANGES.md).

## Pins

`builder/lines.json` is the only source of pins (SourceMod / Metamod commits and revs, line status,
`known_bad` tags, smoke images). `python3 builder/lines.py gen` writes `builder/versions.env`,
`builder/generated/ci-matrix.json`, `builder/generated/tag-map.sh` and the README line table;
`python3 builder/lines.py check` fails on any stale generated file (CI runs it on every PR).

## Patch series

Each buildable line has `builder/patches/series/<line>/` and the Metamod 1.12 pin has
`builder/patches/series/MM_112/`: `<repo>/NNNN-*.patch` per repository (`sourcemod` / `metamod`, or a
submodule such as `sourcepawn`, `hl2sdk-manifests`), applied by `builder/patches/apply-series.sh` with
`git apply --index`. `series.json` holds the upstream commit and the tree each repository must have
afterwards; any other result fails the build. Our own code stays a script: the legacy-plugin bridge
(`apply-mmsource-oldbridge.sh`, `builder/patches/mm-oldbridge/`) and the MM 1.10 core it uses.

- After a pin change: `builder/scripts/patch-series.sh refresh <line | MM_112>` rebases the series
  (`git apply --3way`); on a conflict, fix the `.patch` and refresh again. Then `lines.py gen` and `check`.
- Edit a patch: change the checked-out tree, regenerate with `patch-series.sh refresh`.
- Before a bump: `builder/scripts/check-patch-drift.sh --sm-commit <rev> --line <line>` (or
  `--range old..new`, `--mm-commit`) names the first patch that no longer applies.
- New line: an entry in `lines.json`, its own series, a target in `upstream-bump.py`, and any gamedata
  `check-css34-gamedata.py` asks for.

## Bumps

`.github/workflows/upstream-bump.yml` runs weekly: one PR per lagging target (`bump/sm12-latest`,
`bump/sm13-latest`, `bump/MM_112`) via `builder/scripts/upstream-bump.py` (moves the pin, refreshes the
series, runs `gen` / `check` and the gamedata check, lists upstream commits and risky paths). CI builds,
smokes and botplays the PR. The owner merges; the workflow then pushes the line's next tag. It needs
the owner's GitHub App (`vars.BUMP_APP_ID`, `secrets.BUMP_APP_KEY`).

With `secrets.JULES_API_KEY`, Jules reviews a bump PR read-only (once per target commit) and, when a
bump does not apply, opens its own minimal-fix PR. Nothing Jules produces merges automatically.

## Releases

- **Tags.** `1.<maj>.0.<SM rev>-mm<MM ver>`; a rebuild of the same pins gets `-r<N>`; tags never move.
  Push them through `release-tag.yml` (dispatch: `line`, master `sha`, optional `expected_tag`; it computes
  the next tag and refuses frozen / retired lines, known-bad tags and already tagged commits), or let
  `upstream-bump.yml` do it after a bump merge.
- **`release.yml`** builds the tag into a **prerelease** with generated notes, smokes the public URLs on
  the weekly OS matrix and runs botplay, then promotes it (GitHub *Latest* only for the default line),
  moves `line-<line>` and smokes the pointer. A red smoke leaves the prerelease and the old pointer.
  Windows assets never hold back promotion; `SHA256SUMS` is written last.
- **Assets.** `sourcemod-<ver>-git<rev>-css34-{linux.tar.gz|windows.zip}`,
  `mmsource-<ver>-git<mmrev>-css34-…`, the same files under fixed names
  (`sourcemod-css34-linux.tar.gz`, …), `VERSIONS.txt` (`key=value`: versions, commits, asset names,
  sha256) and `SHA256SUMS`. Every package carries `addons/{sourcemod,metamod}/css34-package.json`.
- **Never delete a release.** Other repositories link to the assets (12 deleted on 2026-11-03 broke
  them). After a pointer move, older releases of the line get a *superseded* note
  (`supersede-releases.py`). A broken build gets `known_bad` in `lines.json` and *Release Maintenance* →
  `mark-known-bad` (prerelease + banner). *Release Maintenance* also re-publishes drafts; it has no delete.
- **Repoint / roll back a pointer:** Actions → *Release* → *Run workflow* on `master` with the target tag.
  It checks the tag (line, not known-bad, assets present), smokes it, promotes it if needed (never
  *Latest*) and moves the pointer with `FORCE_REPOINT=1`.

## Pointers (installer contract, `fmu1337/v34_server_base`)

```
releases/download/line-<line>/{sourcemod,mmsource}-css34-linux.tar.gz
releases/download/line-<line>/{SHA256SUMS,lines.json,VERSIONS.txt}
releases/download/lines-index/lines.json      # all lines
```

`lines.json` is `{line: {tag, sm_version, sm_commit, mm_version, mm_commit, extension_api,
extension_api_min, metamod_binary, smoke, …}}`. `line-sm11-oldstable` also serves
`mmsource-legacy-css34-linux.tar.gz` (MM 1.10.7). Pointers are Linux-only. Assets are replaced
upload-first, updates are serialized per line, and an older tag never moves a pointer back.

## The frozen line (`sm11-oldstable`)

SM 1.11.0.6970 dual-core, MM 1.12 git1227 + MM 1.10.7. Its pointer serves `1.11.0.6970-mm1.12.0-dual-r3`
for good; `lines.json` `frozen` records the sha256 of every asset. Master no longer has its build code:

- **Rebuild** only from the tag `sm11-freeze` and the release `sm11-freeze-inputs` (git mirrors, pinned
  downloads, the saved build image, `MANIFEST.json`):
  `git checkout sm11-freeze && builder/freeze/build-offline.sh <assets> <out>` (`--network none`).
  `testing/scripts/compare-package-abi.py` must find the same files, exports, `NEEDED` and `SONAME`.
- **Weekly** `frozen-verify.yml` checks the published files against `frozen.assets` and smokes the
  pointer on both Metamod builds, with the hotfix installed.
- **A text-only fix** (gamedata) goes to `hotfixes/<line>/` as a SourceMod
  `gamedata/<name>.games/custom/*.txt` override; the packages stay untouched. Current one:
  `HintTextPreByte` (#175).
- **A binary fix** needs a refreeze: branch from `sm11-freeze`, build a new `-rN`, new freeze tag and
  input archive (`freeze-inputs.yml`, approval in the `frozen-release` environment), then a master PR
  that changes only the `frozen` block.

## CI

- `ci.yml` (PRs, master, weekly): Linux builds in manylinux2014 with static ABI / glibc / import checks,
  Windows builds on `windows-2022` with native smoke, smoke on `centos:7`, `ubuntu:24.04`, `debian:13`
  for every active line, one botplay per line, host tests. Weekly suite: old OS images, botplay on
  `centos:7`, Wine smoke. Doc-only PRs skip build and server jobs; the `gate` job is the required check.
- `release.yml`, `release-tag.yml`, `upstream-bump.yml`: above. `frozen-verify.yml`, `freeze-inputs.yml`:
  the frozen line. `test-images.yml`: prebuilt smoke images (`ghcr.io/fmu1337/css34-test`).
- Packages move between jobs through the Actions cache; failure logs are kept 7 days.
- After workflow edits run `actionlint` (`testing/scripts/install-actionlint.sh`) and
  `bash testing/scripts/run-host-tests.sh`.
