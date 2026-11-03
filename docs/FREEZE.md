# Freezing a line (T2.7)

A frozen line is rebuilt only from an archive of its inputs, never from the
network. `sm11-oldstable` (SourceMod 1.11.0.6970, MM 1.12 git1227 + MM 1.10.7
git976) is the first one.

## The input archive

`builder/freeze/collect-inputs.sh` builds the line online once and archives
every input of that build. `freeze-inputs.yml` publishes them as the assets of
the release `<prefix>-freeze-inputs` (`sm11-freeze-inputs`):

| Asset | Contents |
|-------|----------|
| `git-<owner>-<repo>.tar.zst` | a bare mirror holding the pinned commit(s) of each repository the build clones: SourceMod and its submodules (amtl, sourcepawn, googletest), the gitlink commit `git submodule update` checks out first, Metamod 1.10 and 1.12 (+ submodules), hl2sdk episode1, rom4s/hl2sdk-ep1c, AMBuild |
| `dl-<name>` | every pinned download (`builder/fetch-pinned.sh`): for sm11 zlib, OpenSSL 1.1.1w (as of its `sm11-freeze` tag), the MySQL 5.6 SDK, GeoLite2-Country, two hl2sdk `css` headers, and the setuptools wheel AMBuild is built with; a line with the MariaDB connector also has OpenSSL 3.5, its CentOS perl RPMs and the Connector/C source |
| `build-image.tar.zst` | `docker save` of the manylinux2014_i686 build image, tagged `css34-build-ml2014:<line>-freeze`; the same image is pushed to `ghcr.io/fmu1337/css34-build-ml2014:<line>-freeze` |
| `*.tar.gz` | the packages of that online build |
| `MANIFEST.json` | line, builder commit, image id / source / ghcr digest, repository → commits, Windows toolchain (`builder/windows-toolchain.env`), package sha256 + `css34-package.json`, sha256 of every asset |
| `SHA256SUMS` | all of the above |

Every download goes through `fetch_pinned URL DEST SHA256 [NAME]`:
`CSS34_SAVE_DOWNLOADS=DIR` records it, `CSS34_DOWNLOADS=DIR` serves it, and
`CSS34_OFFLINE=1` forbids the network. The sha256 is checked whatever the source.

## Offline rebuild

```bash
git checkout <MANIFEST.json builder_commit>   # tag sm11-freeze
builder/freeze/build-offline.sh <assets dir> <output dir>
```

`build-offline.sh` checks `SHA256SUMS`, loads the archived image (its id must
match `MANIFEST.json`), unpacks the mirrors and downloads, and runs
`builder/docker/build.sh` with `CSS34_INPUTS_DIR`. The container then gets
`--network none --pull never`. `git config url."file:///inputs/git/".insteadOf
https://github.com/` sends every clone, fetch and submodule to the mirrors, and pip
installs AMBuild with `--no-index --find-links deps/wheels` (in every build, so setuptools never comes unpinned from PyPI).

`testing/scripts/compare-package-abi.py REFERENCE REBUILD` is the acceptance
gate. The two packages must have the same files, the same exported dynamic
symbols (name, type, version), and the same `NEEDED` and `SONAME` for every ELF
file. `css34-package.json` must also match, apart from `build_date` and
`css34_pack_commit`. Byte differences are only reported, because compilers embed
dates. `freeze-inputs.yml` runs the rebuild against both the online build and
the line's published release, then probes the core PLAPI (1.ep1 = 11, 2.ep1 = 16).

## A frozen line

`builder/lines.json` marks the line `"status": "frozen"`, `"releasable": false`,
with a `frozen` block:

```json
"frozen": {
  "tag": "1.11.0.6970-mm1.12.0-dual-r3",
  "freeze_tag": "sm11-freeze",
  "inputs_release": "sm11-freeze-inputs",
  "assets": { "<release asset>": "<sha256>", "...": "..." }
}
```

- **CI** builds only active lines. The frozen line leaves every `ci.yml` matrix
  (Linux, Windows, smoke, botplay), and a `css34_line` dispatch for it is refused.
- **Releases**: a new tag of the line is refused on master (`css34_line_can_release`).
  The published release, its sha256 values and the pointer `line-<line>` stay as
  they are. `lines.py check` requires `frozen.tag` to be a build of the line's pins
  and never a known-bad tag.
- **Rebuilds** come only from `freeze_tag` and `inputs_release`
  (`build-offline.sh`, `--network none`). Publishing inputs (`freeze-inputs.yml`
  with `publish: true`) waits for approval in the protected `frozen-release`
  environment.
- **Weekly check**: `frozen-verify.yml` runs for every row of
  `python3 builder/lines.py frozen-gha`, one row per line and smoke image.
  - `testing/scripts/verify-frozen-line.py` checks the release assets and the
    pointer files against `frozen.assets` and requires the pointer to serve
    `frozen.tag` with `smoke: pass`.
  - It also requires the input archive's `MANIFEST.json` to name the line and the
    `freeze_tag` commit, and its listed assets to match `SHA256SUMS`.
  - `release-smoke.sh` then boots srcds from the pointer URLs on every Metamod
    build the pointer serves.
- **Master no longer carries the 1.11 build code** (T3.3): the SM 1.11 patcher,
  dual-core packaging and `secondary_metamod` builds live only at `freeze_tag`.
  The builder refuses SourceMod < 1.12 (`css34_require_buildable` in
  `resolve-version.sh`, which still resolves the line's pins for smoke
  expectations) and `resolve-metamod-pins.py` refuses the line; `lines.py check`
  allows `secondary_metamod` only on a frozen line.

## Owner steps

1. Push the freeze tag: `git tag sm11-freeze <commit> && git push origin sm11-freeze`.
2. Create the `frozen-release` environment with required reviewers.
3. Run **Freeze inputs** on that tag with `publish: true`, and approve it in
   `frozen-release`.
4. Make the ghcr package `css34-build-ml2014` public. It is created private on the
   first push.
5. Merge the freezing PR. `frozen-verify.yml` fails until steps 1–3 are done.
