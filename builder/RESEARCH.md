# Research: recovering `rom4s/sourcemod-css34-builder`

Goal: recover the original build orchestrator used to produce
`sourcemod-1.11.0-git6572-css34-linux.tar.gz` (release tag `v1.11.0.6572`).

Without rom4s contact, recovery must come from public archives, mirrors, or
reverse-engineering from release artifacts and Travis configuration.

## Executive summary

| Question | Finding |
|---|---|
| Deleted or private? | **Almost certainly deleted.** GitHub API returns 404 for repo, all 20 known commit SHAs, and `git clone`. No fork or mirror exists under that name. Private repos also 404 anonymously, but full commit purge + zero mirrors strongly suggests deletion. |
| Can we recover source code? | **Not from public archives today.** Only one Wayback snapshot (2020-10-19). It captured GitHub HTML shells, not `raw.githubusercontent.com` blobs or commit diffs. |
| What *was* recovered? | Repo metadata, directory layout, 4 root-level file names, ~4 visible commit messages, 17-commit count, language stats (Python 97.6%). |
| Best remaining paths | (1) Manual Wayback browser extraction of Oct 2020 pages, (2) Travis CI log recovery if someone has an account/archive, (3) infer `build.py` behaviour from release binary diffs + our bash reconstruction. |

## Original build pipeline (v1.11.0.6572)

From `.travis.yml` at tag `v1.11.0.6572` on `rom4s/sourcemod-css34`:

```yaml
dist: trusty          # Ubuntu 14.04
python: "3.6"         # Python 3.6.8 via pythonz
# clang-9 from bitbucket.org/rom4s/other.get/downloads/clang-9-ubuntu-14.04-m.tar.xz
script:
  - git clone 'https://github.com/rom4s/sourcemod-css34-builder' builder
  - builder/run/linux.sh
```

Windows job cloned the same repo and ran `builder\run\windows.bat`.

Compiler/toolchain setup lived in the **main** repo Travis config (with a
`TODO: move this to builder` comment). The builder repo supplied orchestration,
patches, and thin `run/` entrypoints.

## Recovered repository structure (Wayback, 2020-10-19)

```
sourcemod-css34-builder/
├── LICENSE
├── build.py          # Python orchestrator (NOT in our in-repo reconstruction)
├── config.json       # Build configuration (pins, paths, flags?)
├── patches/          # Added in "New patch for 1.11" (2020-05-21)
└── run/              # linux.sh, windows.bat (Travis entrypoints)
```

Description (archived main page): **"Builder & patches for SourceMod for CS:S v34"**

Language breakdown (archived): **Python 97.6%**, Shell 1.0%, Batchfile (remainder).

Stats (archived): **17 commits**, 0 forks, 1 watcher.

### Known commits (from archived file-list / tree-commit fragment)

| SHA (short) | Date (UTC) | Message |
|---|---|---|
| `b17cf4bd` | 2020-02-07 | Initial commit (LICENSE) |
| `2a489ec3` | 2020-02-09 | Update build.py — *"We need decode it..."* |
| `1f577717` | 2020-02-09 | run/ — *"Update windows.bat — Travis set env CXX=g++, remote it."* |
| `f544bbea` | 2020-05-21 | New patch for 1.11 (config.json + patches/) |

The archived main page reports **17 commits** total; only the four above have
recoverable messages. The other 13 commits are not available in any public
archive checked.

## Sources checked

### GitHub

| Check | Result |
|---|---|
| `GET /repos/rom4s/sourcemod-css34-builder` | 404 Not Found |
| `git clone` | `remote: Repository not found` |
| Commit API for all known SHAs | 404 for every SHA |
| `search/repositories?q=sourcemod-css34-builder` | 0 results |
| Forks of `sourcemod-css34` (`fmu1337`, `prod-broke-again`, `blueboy-tm`) | No `sourcemod-css34-builder` copy |
| `rom4s` public repos (14) | Builder not listed |
| `rom4s-bot` repos | 0 public repos |
| `rom4s` public gists (1) | Unrelated C++ fiddle snippet |

### Internet Archive (Wayback Machine)

| URL pattern | Captures |
|---|---|
| `github.com/rom4s/sourcemod-css34-builder` | **1** (2020-10-19) |
| `.../file-list/master` | 1 — **file names recovered** |
| `.../tree-commit/f544bbea...` | 1 — commit message only |
| `raw.githubusercontent.com/rom4s/sourcemod-css34-builder/*` | **0** |
| `.../blob/master/build.py` (and config.json) | Archived as Wayback wrapper HTML, **no source lines** |
| `.../commit/*` (diff pages) | Archived as empty JS shells, **no diff hunks** |

CDX index: ~50 GitHub chrome URLs (issues, graphs, chunk JS), but **no patch
file contents**.

### Other archives

| Source | Result |
|---|---|
| Software Heritage (`origin` API) | No visit for this URL |
| Common Crawl (CC-MAIN-2024-10) | No captures |
| Travis CI API (`travis-ci.com`) | Repo/builds not found (Travis CI.com deprecated) |
| Travis pages on Wayback | No useful captures found |
| grep.app / Codeberg search | No hits |
| Bitbucket (`rom4s/*`) | `mmsdrop-1.10`, `other.get` downloads — **no builder repo** |
| CSDevs / HLmod forums | Release links only, no builder source |
| Release tarball strings | No embedded compiler/builder path metadata in `sourcemod.1.ep1.so` |

## Architectural difference vs our reconstruction

Commit `97012a9` in `fmu1337/sourcemod-css34` replaced the missing builder with
**bash-first** scripts:

| Original builder | Our `builder/` |
|---|---|
| `build.py` + `config.json` (Python 97.6%) | No `build.py`; logic in shell + inline Python heredocs |
| `patches/` (contents unknown) | `apply-sourcemod.sh`, `apply-hl2sdk-ep1c.sh` (reconstructed) |
| `run/linux.sh` (unknown contents) | `run/linux.sh`, `linux-repro.sh`, `linux-repro-trusty.sh` |
| Compiler install in Travis, not builder | `install-clang9.sh` in-repo |

The commit message on `2a489ec3` ("We need decode it...") suggests `build.py`
handled **decoding** of something — possibly base64-encoded patch blobs in
`config.json`, or UTF-8/locale handling for subprocess output. This is
speculation; the file itself was not recovered.

## Implications for byte-identical rebuild

Our trusty Docker repro (clang-9 + pinned deps) achieves:

- **0 / 20** byte-identical `.so` files
- **9 / 20** same-size `.so` files (but different SHA — e.g. `dbi.mysql.ext.so` ~6388 differing bytes)
- **867 / 907** non-binary package files match (with `ORIGINAL_TRANSLATIONS=1`)

The gap is consistent with **reconstructed patches ≠ original `patches/`** and
unknown `build.py` orchestration (configure flags, strip mode, ordering, extra
post-processing, translation bundling logic, etc.).

## Remaining recovery options (ranked)

### 1. Wayback manual extraction (low cost, low probability)

Open in a real browser (JS rendering):

- https://web.archive.org/web/20201019031204/https://github.com/rom4s/sourcemod-css34-builder
- https://web.archive.org/web/20201019031205/https://github.com/rom4s/sourcemod-css34-builder/file-list/master
- Individual commit pages for `f544bbea`, `2a489ec3`, `1f577717`

Sometimes the Wayback Machine renders diffs in-browser that automated fetch
misses. As of 2026-07-06 automated curl gets empty shells.

### 2. Travis CI build logs (medium probability if archived)

Search for archived logs from `rom4s/sourcemod-css34` on Travis **before**
Travis CI.com shutdown. A successful 2020 build log would show:

- Exact `git clone` output (builder commit SHA at build time)
- stdout from `builder/run/linux.sh` / `build.py`
- `configure.py` flags and `ambuild` output

### 3. Community mirrors (low probability)

Ask on CSDevs / alliedmodders / Russian CSS v34 communities whether anyone
cloned `sourcemod-css34-builder` locally in 2020–2022. Zero public GitHub forks
were found, but private local clones may exist.

### 4. Binary reverse-engineering (high effort, partial)

Compare original vs repro `.so` files:

- `readelf -S`, `objdump -d` for code section size diffs
- Symbol tables / debug sections (original may have been strip-debug)
- String diffs for embedded paths, version macros, `#ifdef` branches

This can narrow which **source patches** differ without recovering `build.py`.

### 5. Infer `config.json` schema from `build.py` usage (if partial recovery)

If even a fragment of `build.py` is found, the `config.json` schema likely
pinned the same revisions we already inferred (`pins.env`):

- SourceMod `832519ab` (git rev 6572)
- hl2sdk episode1 `ebb52ad`, hl2sdk-ep1c `fd7c497`
- MMS `6c8495f`, AMBuild `0db7a7d`

## Conclusion

`rom4s/sourcemod-css34-builder` is **gone from GitHub** with no public mirror.
The Internet Archive preserved **repository metadata and file names** from a
single October 2020 snapshot, but **not file contents**. Recovery of the exact
original build without rom4s cooperation is **unlikely** from online sources
alone; the practical path forward is continuing to **narrow binary diffs** with
our trusty repro environment and treating the bash `builder/` as a best-effort
reimplementation of an unknown Python-driven system.

## References

- Archived repo page: https://web.archive.org/web/20201019031204/https://github.com/rom4s/sourcemod-css34-builder
- Archived file list: https://web.archive.org/web/20201019031205/https://github.com/rom4s/sourcemod-css34-builder/file-list/master
- Original Travis config: https://raw.githubusercontent.com/rom4s/sourcemod-css34/v1.11.0.6572/.travis.yml
- Release assets: https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572
- In-repo replacement: commit `97012a9` ("Replace the missing rom4s/sourcemod-css34-builder with in-repo scripts")
