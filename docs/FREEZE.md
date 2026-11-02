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
| `dl-<name>` | every pinned download (`builder/fetch-pinned.sh`): zlib, OpenSSL 1.1.1w, the MySQL 5.6 SDK, GeoLite2-Country, two hl2sdk `css` headers, and the setuptools wheel AMBuild is built with |
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

## Owner steps

1. Push the freeze tag: `git tag sm11-freeze <commit> && git push origin sm11-freeze`.
2. Run **Freeze inputs** on that tag with `publish: true`.
3. Make the ghcr package `css34-build-ml2014` public. It is created private on the
   first push.
4. Create the `frozen-release` environment with required reviewers. The second
   half of T2.7 makes frozen-line releases use it.
