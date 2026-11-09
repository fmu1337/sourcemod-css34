# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) + [Metamod:Source](https://www.sourcemm.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy).

All packages are built from source: no rom4s/reference `.so` is spliced in. Smoke asserts SDK Hooks load and the css34 `OnTakeDamage` gamedata (linux **61**). Botplay hooks `SDKHook_OnTakeDamage` and logs hits.

Docs: [docs/README.md](docs/README.md) (index — current reference vs. history). Known doc/project inconsistencies and simplification proposals: [docs/REVIEW_2026-10.md](docs/REVIEW_2026-10.md).

## What to install

Use a **line pointer**: one fixed URL per line that always serves the newest build of that line that passed the public-URL smoke test.

```
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/mmsource-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/sourcemod-css34-linux.tar.gz
```

<!-- lines-install:begin -->
| `<line>` | SourceMod | Metamod | Role |
|----------|-----------|---------|------|
| `sm13-latest` | 1.13.0.7478 | 1.12.0 git1229 | **Default / recommended** |
| `sm12-latest` | 1.12.0.7260 | 1.12.0 git1229 | Latest 1.12 |
| `sm13-mm20-khook` | 1.13.0.7565 (KHook branch + master) | 2.0.0 git1472 (KHook) | Frozen outside CI; archived builder, ships `dhooks.ext` |
| `sm13-mm20` | 1.13.0.7404 | 2.0.0 git1407 (last SourceHook MM 2.0) | Retired outside CI |
| `sm11-oldstable` | 1.11.0.6970 | 1.12.0 git1227 | OldStable, frozen: dual-core; MM 1.12 default, MM 1.10.7 as mmsource-legacy |
<!-- lines-install:end -->

`sm11-oldstable` (SM 1.11.0.6970, dual-core) serves frozen MM 1.12 (both Metamod cores, legacy-plugin bridge) as
`mmsource-css34-linux.tar.gz` and MM 1.10.7 as `mmsource-legacy-css34-linux.tar.gz` — see
[SourceMod 1.11: choosing Metamod](#sourcemod-111-choosing-metamod). The line is **frozen** (T2.7,
[docs/FREEZE.md](docs/FREEZE.md)): its pointer serves `1.11.0.6970-mm1.12.0-dual-r3` for good, `builder/lines.json`
records the sha256 of every file of that release, CI no longer builds it, and it is rebuilt only from the tag
`sm11-freeze` and the input archive `sm11-freeze-inputs` (`--network none`). `frozen-verify.yml` re-checks the
published files and smokes the pointer every week.

**sm11 hotfix (install it with the packages).** The frozen SourceMod 1.11 package lacks the gamedata key
`HintTextPreByte`, so the v34 client shows no `PrintHintText` / `sm_hsay` text (#175). The fix is a SourceMod
gamedata override in [`hotfixes/sm11-oldstable/`](hotfixes/sm11-oldstable), outside the frozen package:

```bash
cd /path/to/cstrike
mkdir -p addons/sourcemod/gamedata/core.games/custom
curl -fL -o addons/sourcemod/gamedata/core.games/custom/css34-hinttext-prebyte.txt \
  https://raw.githubusercontent.com/fmu1337/sourcemod-css34/master/hotfixes/sm11-oldstable/addons/sourcemod/gamedata/core.games/custom/css34-hinttext-prebyte.txt
```

Restart the server. The console then prints
`[SM] Parsed custom gamedata override file: core.games/custom/css34-hinttext-prebyte.txt`. The override works on both
Metamod packages of the line, and the other lines ship the key in their packages
([docs/FREEZE.md](docs/FREEZE.md#fixing-a-frozen-line)).
What each pointer serves right now (tag, commits, smoke result) is in
[`lines-index/lines.json`](https://github.com/fmu1337/sourcemod-css34/releases/download/lines-index/lines.json).

```bash
tar -xzf mmsource-css34-linux.tar.gz  -C /path/to/cstrike
tar -xzf sourcemod-css34-linux.tar.gz -C /path/to/cstrike
```

Always install MM and SM **from the same line** (same pointer or same tag). Windows packages are only
attached to the per-tag releases (pointers are Linux-only).

## Connecting to MySQL HeatWave / MySQL 8.4

`sm13-latest` connects to Oracle MySQL HeatWave and MySQL 8.4+ out of the box: `caching_sha2_password`,
TLS 1.2/1.3 (static OpenSSL 3.5 on Linux) and `utf8mb4`, configured per entry in
`addons/sourcemod/configs/databases.cfg`. No extra extension or ProxySQL is needed. The keys and values are
those of [fmu1337/sm-dbi-mysql](https://github.com/fmu1337/sm-dbi-mysql); the **default differs** (see below):

```
"Databases"
{
	"default"
	{
		"driver"	"mysql"
		"host"		"10.0.0.10"
		"database"	"sourcemod"
		"user"		"sm"
		"pass"		"..."
		"port"		"3306"
		"timeout"	"10"
		"ssl_mode"	"verify_ca"			// disabled (default) | preferred | required | verify_ca | verify_identity
		"ssl_ca"	"configs/mysql-ca.pem"	// CA certificate (PEM), relative to addons/sourcemod/
	}
}
```

- Without `ssl_mode` (or with `""`) the driver uses **`disabled`**: no TLS, exactly like stock SourceMod. A
  HeatWave / MySQL 8.4 account with `REQUIRE SSL` then refuses the login (`[1045]`).
- **For HeatWave** use at least `"ssl_mode" "required"`, better `"verify_ca"` with the DB system's CA file in
  `ssl_ca` (`verify_identity` if you connect by a host name the certificate lists).
- **Coming from sm-dbi-mysql:** its default is `preferred`. Entries that relied on that default (no `ssl_mode`
  key) must now say `"ssl_mode" "preferred"` or something stricter, otherwise they connect without TLS.
- `preferred`: TLS whenever the server offers it, plaintext otherwise; the certificate is **not** checked
  (protects against eavesdropping, not against an active man in the middle). `required`: TLS or no
  connection; certificate not checked. `verify_ca`: the certificate must chain to `ssl_ca`.
  `verify_identity`: additionally the `host` must match the certificate (for an IP address the certificate
  does not list, use `verify_ca`).
- An unknown `ssl_mode`, or a verify mode without a readable `ssl_ca`, fails the connect with a message
  (`[0]: ssl_mode ...`); nothing is silently downgraded. Plugins using `SQL_ConnectCustom` can pass the same
  keys in their KeyValues.
- `sm12-latest` cannot log in to MySQL 8.4 / HeatWave (its MySQL 5.6 client has no `caching_sha2_password`
  and only TLS 1.0/1.1); it ignores these keys. Windows packages build the same code with Schannel; that path is
  not tested by CI.

Details, the mapping onto MariaDB Connector/C and the CI cases: [docs/PATCHES.md](docs/PATCHES.md)
("sm13 MySQL TLS options").

## Version matrix (current pins)

<!-- lines-versions:begin -->
| Line (`CSS34_LINE`) | SourceMod | Metamod | Role |
|---------------------|-----------|---------|------|
| `sm11-oldstable` | **1.11.0.6970** (`f53cb134…`) | **1.12 git1227** (`75dd7b26…`) | OldStable, frozen ([docs](docs/FREEZE.md)): dual-core (1.ep1 + 2.ep1); MM 1.10.7 as mmsource-legacy |
| `sm12-latest` | **1.12.0.7260** (`3f746067…`) | **1.12 git1229** (`4e031eb5…`) | Latest 1.12 |
| `sm13-latest` | **1.13.0.7478** (`b34de51b…`) | **1.12 git1229** (`4e031eb5…`) | Latest 1.13 (default) |
| `sm13-mm20` | 1.13.0.7404 (`cdedec76…`) | 2.0 git1407 (last SourceHook MM 2.0) (`0084b86a…`) | Retired outside CI ([docs](docs/SM13_MM20.md)) |
| `sm13-mm20-khook` | **1.13.0.7565** (KHook branch + master) (`25954d4a…`) | **2.0 git1472 (KHook)** (`05c5c63a…`) | Frozen outside CI ([docs](docs/MM20_KHOOK.md)) |
<!-- lines-versions:end -->

`sm13-dev` (7404 + MM 1.12) is gone (T3.3): use `sm13-latest`. Its last tag, `1.13.0.7404-mm1.12.0`, is no
longer rebuildable from master.

Pins live in [`builder/lines.json`](builder/lines.json). `python3 builder/lines.py gen` writes
[`builder/versions.env`](builder/versions.env), [`builder/generated/ci-matrix.json`](builder/generated/ci-matrix.json),
[`builder/generated/tag-map.sh`](builder/generated/tag-map.sh), and the two tables above.
`python3 builder/lines.py check` fails when a generated file is stale, a line lists the same image twice,
or a known-bad tag is pinned on a line that publishes a pointer.
The manifest records line status and known-bad release tags; it is separate from the published pointer index.
Resolver: [`builder/resolve-version.sh`](builder/resolve-version.sh).
Bumps: `.github/workflows/upstream-bump.yml` opens a PR per lagging line every week and tags the line after
merge; by hand, see [docs/PATCH_STRATEGY.md](docs/PATCH_STRATEGY.md#апгрейд-новая-ревизия-той-же-major).

> `meta version` prints the Metamod build number from `lines.json` (`1.12.0-dev+1228`,
> or `1.10.7-dev+976` on `sm11-oldstable`) and `Build ID: <rev>:<commit prefix>`.
> `sm version` prints `<major>.<minor>.0.<SM_REV>` (for example `1.13.0.7478`).
> The clones stay shallow; `generate_headers.py` reads `MMS_GIT_REV` / `SOURCEMOD_GIT_REV`.

### What pairs with what

| | SM 1.11 dual-core (`1.ep1` + `2.ep1`) | SM 1.12 / 1.13 (`2.ep1`) |
|--|--|--|
| **MM 1.10** (`metamod.1.ep1`) | **matched** (`sm11-oldstable`, runs `sourcemod.1.ep1`) | no |
| **MM 1.11** (`metamod.2.ep1`) | no (myarena bundle; `11 < 14`) | not a release path |
| **MM 1.12** git1227 / git1228 | **matched** (`sm11-oldstable` git1227, runs `sourcemod.2.ep1`) | **matched** (`sm12-latest`, `sm13-latest`) |
| **MM 2.0** git1407 | no | experimental (`sm13-mm20`) |
| **MM 2.0** git1450+ (KHook, no SourceHook) | no | only the SM KHook branch (`sm13-mm20-khook`); SM `master` cannot run on it |

**Old Metamod plugins** (PLAPI 7–12, built for MM 1.4–1.10) run on every MM 1.12 package we build
(`sm11-oldstable`, `sm12-latest`, `sm13-latest`; since the `-r2` releases of 7257 / 7478): the package ships `metamod.2.ep1`
**and** the MM 1.10.7 legacy core `metamod.1.ep1`, and MM 1.12 hands such a plugin to it (legacy-plugin bridge,
#144; `bridge_metamod` in `builder/lines.json`). It loads the legacy core only when `metaplugins.ini` names an
old plugin, lists that plugin in `meta list` like any other (`meta unload` / `meta pause` work), and nothing has
to be deleted. SourceMod extensions that exist only as `*.ext.1.ep1` are a different matter: they need the
`1.ep1` SourceMod core, which only `sm11-oldstable` on MM 1.10.7 runs.

## Releases

A tag pins one SM + MM pair; never mix Metamod from one tag with SourceMod from another.
A rebuild of the same pins gets a `-r<N>` suffix (tags are never moved); `release.yml` maps
`<tag>-r<N>` to the same line as `<tag>`.

**Current builds** (what the line pointers serve; every asset in `SHA256SUMS`):

| Tag | Line | Built from | SourceMod | Metamod |
|-----|------|------------|-----------|---------|
| [`1.13.0.7478-mm1.12.0-r5`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7478-mm1.12.0-r5) | `sm13-latest` (GitHub Latest) | `5d59959` | 1.13.0-git7478 | 1.12.0 git1229 (+ legacy bridge, 1.10.7 git976) |
| [`1.12.0.7257-mm1.12.0-r4`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.12.0.7257-mm1.12.0-r4) | `sm12-latest` | `5d59959` | 1.12.0-git7257 | 1.12.0 git1229 (+ legacy bridge, 1.10.7 git976) |
| [`1.11.0.6970-mm1.12.0-dual-r3`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.11.0.6970-mm1.12.0-dual-r3) | `sm11-oldstable` (frozen) | `978ec55` | 1.11.0-git6970, both cores | 1.12.0 git1227 (+ legacy bridge); 1.10.7 git976 as `mmsource-legacy` |
| [`1.13.0.7565-mm2.0.0-khook-dhooks-r2`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7565-mm2.0.0-khook-dhooks-r2) | `sm13-mm20-khook` | `88713a7` | 1.13.0-git7565 (KHook branch + master), + `dhooks.ext` | 2.0.0 git1472 (KHook) |
| [`1.13.0.7404-mm2.0.0-r2`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.13.0.7404-mm2.0.0-r2) | `sm13-mm20` | `88713a7` | 1.13.0-git7404 | 2.0.0 git1407 |

The release page of each `line-<line>` pointer says what it serves now, since when, and the sha256 of
every file; GitHub's own date on that page is when the pointer was first created.

### Release retention

**Published releases are never deleted.** Other repositories' CI and install scripts link to their assets, so a
deleted release breaks them with a 404. When a line pointer moves to a new tag, `release.yml` puts a
*superseded by `<tag>`* note at the top of the older releases of that line
(`builder/scripts/supersede-releases.py`); their assets, tags and URLs stay. A broken build is marked with
`known_bad` in `builder/lines.json` (*Release Maintenance* → `mark-known-bad`: prerelease plus a banner) and
is not deleted either. *Release Maintenance* has no delete mode.

For anything that should keep working across releases, use a `line-<line>` pointer. A script that pins one tag
can use the fixed names every release since this change also carries (the same bytes as the revisioned
assets): `releases/download/<tag>/sourcemod-css34-linux.tar.gz`, `mmsource-css34-linux.tar.gz`,
`sourcemod-css34-windows.zip`, `mmsource-css34-windows.zip`, and `VERSIONS.txt`, a `key=value` file with the
exact SourceMod / Metamod versions and commits, extension API range, the revisioned asset names and their
sha256 (`builder/scripts/release-versions.py`). Each `line-<line>` pointer serves a `VERSIONS.txt` too.

**Deleted on 2026-11-03** (Release Maintenance `delete` mode, before this policy; the releases and their git
tags are gone and their URLs return 404): `1.13.0.7478-mm1.12.0`, `-r2`, `-r3`, `-r4`;
`1.12.0.7257-mm1.12.0`, `-r2`, `-r3`; `1.13.0.7472-mm1.12.0`; `1.12.0.7253-mm1.12.0`;
`1.13.0.7404-mm2.0.0`; `1.13.0.7565-mm2.0.0-khook`; `1.13.0.7565-mm2.0.0-khook-dhooks`. Use the tags above or
the line pointers instead.

**Known-bad** (`builder/lines.json` `known_bad`; never on a pointer):
[`1.11.0.6572-mm1.10.7`](https://github.com/fmu1337/sourcemod-css34/releases/tag/1.11.0.6572-mm1.10.7)
(still published, a prerelease: its Windows MM 1.10.7 zip serves the installer's `--sm rom4s` on Windows),
`1.11.0.6970-mm1.10.7`, `1.12.0.7239-mm1.12.0`, `1.12.0.7245-mm1.12.0`, `1.13.0.7394-mm1.12.0` (see
[Known-bad releases](#known-bad-releases)).

Asset names: `sourcemod-<ver>-git<rev>-css34-{linux.tar.gz|windows.zip}` and
`mmsource-<ver>-git<mmrev>-css34-{linux.tar.gz|windows.zip}` for packages built from this tree, plus the fixed
names above. Older Linux tags before `-r2` keep `mmsource-<ver>-dev-css34-linux.tar.gz`;
tags published before the Windows rename keep `mmsource-<ver>-dev-css34-windows.zip`.
Historical URLs in `testing/versions/matrix.json` intentionally retain those names.
The rename consumer audit and installer migration are in [docs/WINDOWS_ASSETS.md](docs/WINDOWS_ASSETS.md).

### SourceMod 1.11: choosing Metamod

`sm11-oldstable` (frozen) ships **one** SourceMod package with both cores (`sourcemod.1.ep1` / `sourcemod.2.ep1`,
`sdktools` / `sdkhooks` / `game.cstrike` for each) and **two** Metamod packages. Metamod picks the core:

| Metamod package | Runs | DHooks | Old Metamod plugins (PLAPI 7–12, built for MM 1.4–1.10) | SourceMod extensions that exist only as `*.ext.1.ep1` |
|--|--|--|--|--|
| `mmsource-1.12.0-git1227-css34-*` (default, D7; pointer `mmsource-css34-*`) | `metamod.2.ep1` → `sourcemod.2.ep1` | **yes** (`dhooks.ext.2.ep1`) | **yes**, through the bundled `metamod.1.ep1` legacy core (legacy-plugin bridge, #144) | no |
| `mmsource-1.10.7-git976-css34-*` (pointer `mmsource-legacy-css34-linux.tar.gz`) | `metamod.1.ep1` → `sourcemod.1.ep1` | no | yes, natively | yes |

The MM 1.12 package of this line ships `metamod.2.ep1` **and** `metamod.1.ep1` for old Metamod plugins
(see [What pairs with what](#what-pairs-with-what)).

Switch Metamod without touching SourceMod:

```bash
cd /path/to/cstrike
cp addons/metamod/metaplugins.ini /tmp/metaplugins.ini
rm -f addons/metamod/bin/server* addons/metamod/bin/metamod.*
tar -xzf mmsource-<other>-css34-linux.tar.gz
cp /tmp/metaplugins.ini addons/metamod/metaplugins.ini
```

Windows: the same with the `-windows.zip` packages (`bin\server.dll`, `bin\metamod.*.dll`).

`css34-package.json` describes what a package carries: SourceMod lists its `cores`
(`["1.ep1", "2.ep1"]` on this line); Metamod lists `metamod_binaries` and sets `legacy_bridge: true` when it
ships both cores (every MM 1.12 package with the bridge). `metamod_binary` names the Metamod build of the line's primary pin: `metamod.2.ep1` (MM 1.12)
for `sm11-oldstable` since D7.

### Installer contract (fmu1337/v34_server_base)

**Stable line pointers.** Each live line has one published release with a fixed tag and fixed asset names:

```
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/sourcemod-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/mmsource-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/SHA256SUMS
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/lines.json
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/VERSIONS.txt
```

`VERSIONS.txt` (`key=value`, sh-sourceable) names the tag the pointer serves, its versions and commits, the
original revisioned asset names and their sha256; every tag release carries one as well. The pointer's release
title and notes are rewritten on every move (`line-<line> → <tag>`, date, versions, sha256 table).

`<line>` ∈ `sm11-oldstable`, `sm12-latest`, `sm13-latest`, `sm13-mm20`, `sm13-mm20-khook`. A dual-core line
(`sm11-oldstable`) also serves `line-<line>/mmsource-legacy-css34-linux.tar.gz` (MM 1.10.7, the 1.ep1 core;
`mmsource_legacy_url` in its `lines.json` entry, smoked by `smoke-pointer` too). Both files use the same format,
`{line: {tag, sm_version, sm_commit, mm_version, mm_commit, extension_api, extension_api_min, metamod_binary, smoke, …}}`:

- `line-<line>/lines.json` holds only that line's entry (written by that line's runs only);
- `lines-index/lines.json` holds every line, rebuilt from all `line-*/lines.json`.

A pointer is created on the first tag release of its line. A line whose builds never passed smoke has a
pointer release with only `lines.json` (`"tag": null, "smoke": "fail"`).

A tag release is created as a **prerelease** with notes generated from the tag commit's pins
(`builder/scripts/release-notes.py`: SourceMod / Metamod / bridge pins, Linux image and Windows toolchain,
`min_glibc`, patch series, known-bad tags). `promote` makes it a full release only after `smoke-release`
installed the **public** tag URLs with a plain `tar -x` and booted `srcds` and `botplay-release` passed;
GitHub **Latest** is set explicitly, only for a tag of the default line (`lines.json` `default_line`). Windows
assets never hold back promotion, and `SHA256SUMS` is written last. `release.yml` switches a pointer only
after promotion; a red smoke leaves the release a prerelease and the pointer on the previous build
(`lines.json[line].candidate` records the failed tag). Pointer assets are replaced upload-first (`<name>.next-<run>` → delete old → rename),
so the URL serves the old file during a rebuild; the only gap is two back-to-back API calls. `smoke-pointer`
then re-runs the smoke against the pointer URLs.

Several lines may be tagged at once: pointer updates are serialized per line, and the shared
`lines-index/lines.json` is rebuilt from the per-line files and re-checked after upload, so parallel runs
cannot drop each other's entries. Two tags of the *same* line finishing out of order never move the pointer
back: an update whose tagged commit is older than the one served is skipped.

### Runbook: Pointer Repoint / Rollback

Line pointers (`line-<line>`) serve fixed URLs consumed by installers (such as `fmu1337/v34_server_base`).
Each line pointer serves the latest smoke-passed release tag for that build line.

If a published pointer needs to be repointed or rolled back to a specific tag (e.g. `1.12.0.7253-mm1.12.0`), perform a manual repoint dispatch:

1. Open **GitHub Actions** → **Release** workflow (`release.yml`).
2. Click **Run workflow** (`workflow_dispatch`).
3. Select the target branch (`master`).
4. In **Target release tag to repoint line pointer to**, enter the target release tag (e.g. `1.12.0.7253-mm1.12.0` or `1.13.0.7472-mm1.12.0`).
5. Run the workflow.

**What happens during a repoint dispatch:**
- `resolve-line` validates `repoint_tag` against `^[0-9][0-9A-Za-z.+-]*$`, resolves its line (from `tag-map.sh` or the release package's `css34-package.json`), verifies that the line publishes a pointer (`css34_line_has_pointer`) and is not `known_bad`, retrieves its target commit SHA and timestamp, and verifies the release assets exist on GitHub Releases for that tag.
- `release-pins`, `smoke-release`, and `botplay-release` execute public-URL smoke tests and centos:7 botplay tests across the line's OS matrix against `repoint_tag` with `SHA256SUMS` verification enabled.
- `promote` turns the tag into a full release if it was still a prerelease (a repoint never takes GitHub Latest).
- `line-pointer` updates the line pointer release (`line-<line>`) using `FORCE_REPOINT=1` (with the tag's commit SHA and timestamp) and rebuilds `lines-index/lines.json`.
- `smoke-pointer` verifies that the pointer URL serves a working, smoke-passed build.

**Releases never go back to draft.** `release.yml` only uploads into an existing release
(`--clobber`) and re-publishes it if it is a draft. Drafts that already exist can be re-published with
the *Release Maintenance* workflow (Actions → Release Maintenance → Run).

**Manifest in every package** (tags built after #69, i.e. the `-r2` tags and the pointers).
`addons/sourcemod/css34-package.json` and `addons/metamod/css34-package.json`:
`line, sm_version, sm_commit, mm_version, mm_commit, extension_api, extension_api_min, metamod_binary, build_date`.
Windows packages also record `msvc_toolset` and `windows_sdk` (the pinned `windows-2022` vcvars toolset and SDK).
`extension_api` / `extension_api_min` are `SMINTERFACE_EXTENSIONAPI_VERSION` / `_MIN` of the build
(SM 1.11/1.12 have no `_MIN` → `1`; 1.12.0.7253: 8; 1.13.0.7404: 9–9; 1.13.0.7472 / 7565: 9–11).

**Ready to run.** `tar -xzf mm.tgz -C cstrike && tar -xzf sm.tgz -C cstrike` is the whole install:
`addons/metamod/sourcemod.vdf`, executable `*.so` / `scripting/spcomp`, and on SM 1.12+
`configs/geoip/GeoLite2-Country.mmdb` (mode 0644 — older packages shipped it 0600, unreadable for a
non-root srcds). `testing/scripts/check-package.sh` enforces all of it.

**No gamedata auto-updater.** SourceMod's `updater.ext` would download upstream gamedata (no CS:S v34
entries) over the css34 files; `webternet.ext` (libcurl 7.19.2 without TLS, no natives) exists only
for it. Neither is built, the core never loads `updater.ext`, and `core.cfg` has no
`DisableAutoUpdate` / `AutoUpdateURL` keys (`no-gamedata-updater` patch, `docs/PATCHES.md`). Older
packages ship both with `"DisableAutoUpdate" "yes"`; when you install a new package over one, the
leftover `extensions/updater.ext.so` and `webternet.ext.so` are never loaded and can be deleted.

### Known-bad releases

- **`1.13.0.7394-mm1.12.0` and `1.12.0.7239-mm1.12.0`: SDKHooks broken.** The packages have no
  `gamedata/sdkhooks.games/game.cstrike.txt` and `master.games.txt` is upstream's (no `game.cstrike.txt` entry),
  so *every* SDKHooks offset is missing and `SDKHook()` throws `Hook type not supported on this game` for all
  types (SMAC `smac_wallhack` FarESP hits it first on `SDKHook_ThinkPost` / `SetTransmit`). Fixed in every
  build since (`package.sh` and `check-package.sh` require the css34 file); use `line-sm13-latest` /
  `line-sm12-latest`. Botplay's API probe `SDKHookEx`-checks the SMAC hook types, and `check-sm-logs.sh` fails
  on that message.
- **`1.11.0.6970-mm1.10.7` (`sm11-oldstable`): never on a line pointer.** Reported SIGABRT at startup
  without plugins on rom4s 4044 + bufferfix + `srcds_i686` on Ubuntu 24.04; its `sourcemod.2.ep1` was built
  against MM 1.10 headers (PLAPI 11, so MM 1.12 refuses it; `plapi-runtime` checked that until T3.3). The
  dual-core rebuild (`1.11.0.6970-mm1.12.0-dual`, manylinux2014, both cores gated on MM 1.10.7 and MM 1.12)
  replaces it; the old tag stays published (Linux assets only).
- **Windows assets of `1.13.0.7565-mm2.0.0-khook*`.** The first uploads crashed `srcds.exe` on the first map
  load (KHook recall on MSVC x86). Both tags now point at `b1f5192`, which carries the fix, and their assets
  were re-uploaded from it on 2026-10-12, but those exact files never went through the Wine smoke. Prefer
  `1.13.0.7565-mm2.0.0-khook-dhooks-r2`. Fix and Wine / native Windows smoke:
  [docs/MM20_KHOOK.md](docs/MM20_KHOOK.md#windows).

**Install traps**

- Our SM **1.11** packages carry both cores and run on MM 1.12 (2.ep1) or MM 1.10.7 (1.ep1). Older SM 1.11
  drops expect Metamod **1.10.x / `metamod.1.ep1` / PLAPI 11**: a leftover myarena `metamod.2.ep1.so`
  (MM 1.11) → `Older Metamod… (11 < 14)` — not a bad package, a mix. See
  [docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md](docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md).
- Installing over an old SourceMod: delete a flat `gamedata/sm-cstrike.games.txt` left from older drops
  (`[CSTRIKE] Could not locate HandleCommand_Buy`); ours lives in `gamedata/sm-cstrike.games/`.
- Historical community URLs (rom4s / myarena) for local compare: [`testing/versions/matrix.json`](testing/versions/matrix.json) (`reference` section).

### Memory use

SourceMod 1.11.0.6792 and newer (upstream `cab60f73`, "Bump handle limit to 1MB") size the handle table for
2^20 handles and zero all of it at startup: about **64 MB resident in every srcds**, with or without plugins.
Measured on CS:S v34 (`srcds_i686`, de_dust2, 32 slots, no players, `debian:13`), RSS after the map load:

| Build | Stock plugins | 102 plugins (1.11-compiled) |
|-------|---------------|-----------------------------|
| srcds without addons | 71 MB | — |
| rom4s 1.11.0.6572 + MM 1.10.6 | 82 MB | 91 MB |
| `1.12.0.7257-mm1.12.0-r4` | 147 MB | — |
| `1.13.0.7478-mm1.12.0-r5` | 156 MB | 158.5 MB |
| sm13 with `0010-handlesys-lazy-table` | **90 MB** | **93 MB** |

The sm13 / sm12 patch series allocate the table with `calloc` (`sourcemod/0010-handlesys-lazy-table`,
sm12 `0008`): the limit stays 2^20, and only the part in use becomes resident (about 64 bytes per live handle
plus its object; the table does not shrink after a peak). Builds tagged after that patch carry it.
Smaller differences: SourcePawn 1.13 keeps plugin memory in a mimalloc arena (128 MB of address space
reserved, not resident; about 0.25 MB resident per plugin compiled with the 1.13 `spcomp`, 0.01 MB per older
plugin), and all SM/MM binaries together map about 1.5 MB more than rom4s 1.11. The binaries are already built
with `--enable-optimize` and `strip --strip-unneeded`; there are no debug sections to strip.

## Build

Needs Docker. The build runs in pinned `quay.io/pypa/manylinux2014_i686` (glibc 2.17, GCC 10.2.1). SDKs, AMBuild, PIC zlib and, for sm13's MySQL extension, static OpenSSL 3.5 LTS and MariaDB Connector/C (built from pinned sources) go into `deps/`.

```bash
# Default line (pins: builder/lines.json):
CSS34_LINE=sm13-latest builder/docker/build.sh

# Other lines:
CSS34_LINE=sm12-latest     builder/docker/build.sh
# sm11-oldstable is frozen: rebuild it from its input archive (docs/FREEZE.md)
git checkout sm11-freeze && builder/freeze/build-offline.sh <sm11-freeze-inputs assets> <out>
```

MM 2.0 builds (`sm13-mm20`, `sm13-mm20-khook`) are archived outside CI in
[`archive/khook`](https://github.com/fmu1337/sourcemod-css34/tree/archive/khook).
Use that branch to reproduce them; master rejects those build selections. Existing
release assets, line IDs and pointer URLs remain available.

`builder/package-paths.sh` resolves exact Linux and Windows package names from the selected
line and revisions. Stale packages cannot silently replace the expected build.
No root package symlinks are created.

Packages land in `packages/`. `build.sh` builds in
manylinux2014 (glibc 2.17). `check-package.sh` fails the package if any ELF needs a
GLIBC newer than `GLIBC_FLOOR` (default 2.17). Both SM and MM package checks also
reject unversioned undefined dynamic imports outside the verified glibc 2.17,
libgcc_s and CS:S v34 engine allowlist. See [the patch inventory](docs/PATCHES.md).

`builder/run/linux.sh` uses `CC` / `CXX` from the environment. `build.sh` sets
them to devtoolset-10 `gcc` / `g++` inside the manylinux image.

Windows (x86, `windows-2022`, MSVC toolset 14.44, Windows SDK 10.0.26100.0; see `builder/windows-toolchain.env`):

```bash
CSS34_LINE=sm12-latest builder/run/windows.sh
CSS34_LINE=sm13-latest builder/run/windows.sh
```

## CI

- `.github/workflows/ci.yml` — the main CI workflow and unified gate (push to `master`, PRs, and a weekly schedule).
  Includes Linux builds, static ABI/import/Metamod checks, Windows builds on `windows-2022` (MSVC 14.44, SDK 10.0.26100.0) with a native Windows smoke, version-pin and tag-map consistency, host regression tests, server smoke, host checks and botplay stress. The weekly suite runs the old OS images and the Wine smoke (`wine-smoke`).
  Shared steps live in `.github/actions/` (`build-linux`, `build-windows`, `server-tree`), used by `ci.yml` and `release.yml`.
  Doc-only changes skip the build and server jobs; the unified `gate` job always evaluates and reports the result.
  Builds the **active** lines (`sm12-latest`, `sm13-latest`; frozen `sm11-oldstable` is checked by `frozen-verify.yml`) with `builder/docker/build.sh` + `check-package.sh` / `check-metamod-package.sh`;
  every PR smokes `centos:7`, `ubuntu:24.04` and `debian:13` for every active line, plus the ubuntu-22.04 host for
  `sm13-latest`, and one **botplay-stress** run per line on `debian:11`
  (SMAC + SDKHooks OnTakeDamage + SM API / cstrike / DHooks probes).
  `debian:11` smoke itself, plus `debian:8`/`9`/`10`, `ubuntu:14.04`/`16.04`/`18.04`, `rockylinux:9`, and botplay on `centos:7`,
  run on the weekly schedule, on `workflow_dispatch` with `suite=weekly`, and on release.
  Images are pinned by digest in `builder/lines.json`. Packages pass between jobs via
  **Actions cache**. Reference (rom4s / published-release) botplay, extra distros and bisect are
  `workflow_dispatch` opt-ins.
- `.github/workflows/release.yml` — tag-driven; tag (minus `-r<N>`) maps to `CSS34_LINE`; packages attach with
  `gh release upload` (**GitHub Releases**, not Actions artifacts) to a **prerelease** with generated notes;
  public-URL smoke on the weekly OS matrix and botplay on `centos:7`, then `promote` (full release, explicit
  Latest for the default line), line pointer, pointer smoke, `SHA256SUMS` last.
- `.github/workflows/upstream-bump.yml` — weekly bump PR per lagging line (`bump/<target>`), and after its merge
  the line's next tag (needs the owner's GitHub App: `vars.BUMP_APP_ID`, `secrets.BUMP_APP_KEY`).
- `.github/workflows/release-tag.yml` — manual: pushes a line's next tag (`-r<N>` rebuild) on a master commit
  with the same GitHub App, so `release.yml` starts; inputs `line`, `sha`, optional `expected_tag`.
- `.github/workflows/frozen-verify.yml` — weekly check of the frozen `sm11-oldstable` release files and pointer;
  `freeze-inputs.yml` builds a freeze input archive ([docs/FREEZE.md](docs/FREEZE.md)).
- `.github/workflows/release-maintenance.yml` — re-publish releases that ended up as drafts, mark `known_bad`
  releases, or (`mode: supersede`, optional `dry_run`) put the *superseded* note on the older releases of every
  line pointer. It deletes nothing ([Release retention](#release-retention)).

Failure logs remain downloadable for seven days after a run (`retention-days: 7`; CI uploads
no other artifacts, packages move between jobs through the Actions cache). Only PR runs
cancel an older run of the same workflow/ref. Botplay baseline comparisons are informational;
server crashes and API/ABI probes still fail the job.

```bash
git tag 1.13.0.<rev>-mm1.12.0-r<N> && git push origin 1.13.0.<rev>-mm1.12.0-r<N>   # rebuild sm13-latest
```

Or dispatch `release-tag.yml` (line, master commit, optional expected tag): it computes the next tag from
that commit's `builder/lines.json` and pushes it with the GitHub App.
New pins need a new base tag (`upstream-bump.yml` pushes it after a bump merge). `release.yml` reads the tag
map generated from `builder/lines.json`.

## Notes

- Docs index (current vs. history): [docs/README.md](docs/README.md).
- Patch layout and upgrade strategy: [docs/PATCH_STRATEGY.md](docs/PATCH_STRATEGY.md).
- SDKHooks EP1 / PLAPI traps: [docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md](docs/SDKHOOKS_EP1_RELEASE_BLOCKERS.md).
- Compatibility PASS/FAIL notes and historical URLs: [`testing/versions/matrix.json`](testing/versions/matrix.json). Live pins are [`builder/lines.json`](builder/lines.json).
- Smoke / botplay / Wine testing: [testing/README.md](testing/README.md).
