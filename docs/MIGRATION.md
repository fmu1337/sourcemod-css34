# Moving a server from SourceMod 1.7 / 1.8 / 1.11 to `sm13-latest`

Field-tested on 2026-11-05 on four CS:S v34 servers that run `1.13.0.7478-mm1.12.0-r7`: a DM server (was SM 1.11.0.6522,
108 plugins, 13 extensions), Zombie Riot (was SM 1.8), an RPG DM server (was 1.7.3), and a test server under FEX on ARM.
No plugin had to be edited or recompiled: old `.smx` files load on 1.13.

## What changes in the tree

| Old tree | `sm13-latest` package | What to do |
|---|---|---|
| `addons/metamod/bin/server_i486.so` + `metamod.1.ep1.so` (MM 1.10 or older) | `server_i486.so`, `metamod.2.ep1.so`, **and** `metamod.1.ep1.so` (MM 1.10.7, the legacy-plugin bridge) | Replace all of `addons/metamod/bin/` with the package's. |
| `addons/metamod.vdf` from MM 1.10 (`"file" "../cstrike/addons/metamod/bin/server"`) | the same file | Keep it (or take the package's: same content). |
| `addons/metamod/metaplugins.ini` | an empty template | **Keep yours.** Old Metamod plugins (PLAPI 7–12) listed there run through the bundled `metamod.1.ep1` (README, "Compatibility"). SourceMod itself is loaded by `addons/metamod/sourcemod.vdf`; if an old tree also lists `addons/sourcemod/bin/sourcemod_mm` in `metaplugins.ini`, remove that line. |
| `addons/sourcemod/bin/sourcemod.1.ep1.so`, `sourcemod_mm_i486.so`, `sourcepawn.jit.x86.so`, … | `sourcemod.2.ep1.so`, `sourcemod_mm_i486.so`, `sourcemod.logic.so` | Replace the three files with the package's. Leftovers such as `sourcemod.1.ep1.so` or an old `sourcepawn.jit.x86.so` are not loaded by 1.13. |
| Stock extensions `sdktools.ext.1.ep1.so`, `sdkhooks.ext.1.ep1.so`, `game.cstrike.ext.1.ep1.so` | `*.ext.2.ep1.so` | Install the package's `*.2.ep1.so`. The old `*.1.ep1.so` files are ignored and can be deleted. |
| Third-party extensions | — | See below: they need a build for SourceMod 1.13. |
| `gamedata/`, `translations/` | complete CS:S v34 set | Overwrite the stock files; keep your own files (e.g. `cssdm.games.txt`). |
| `configs/`, `data/`, `plugins/` | stock plugins and default configs | Keep your configs; add only missing files; refresh only the stock plugins you have enabled. |

### Which file SourceMod 1.13 loads for an extension

For `foo.ext` on this engine (`gamesuffix` `2.ep1`), `core/logic/ExtensionSys.cpp` tries, in order:

1. `extensions/foo.ext.2.ep1.so`
2. `extensions/auto.2.ep1/foo.ext.so`
3. `extensions/foo.ext.so`

It never looks at `foo.ext.1.ep1.so`. So a third-party extension that exists only as `*.ext.1.ep1.so` shows up as
`could not be found` (with `autoload`) or as a `<FAILED>` line in `sm exts list`. Renaming the file does not help:
a binary built for SM 1.7–1.12 also fails the API check (`Extension version is too old to load (8, max is 9)`, see
[EXTENSIONS.md](EXTENSIONS.md)). It needs a build with SourceMod 1.13 headers, installed as `foo.ext.so` or
`foo.ext.2.ep1.so`. When both names exist, `.2.ep1.so` wins, so delete the stale copy.

## Order that worked

1. Check the package: `sha256sum -c --ignore-missing SHA256SUMS.linux` in the download directory (the file also
   lists the fixed-name copies of the same files).
2. With the server **stopped**, back up `cstrike/addons` and `cstrike/cfg` (one `tar czf`).
3. Copy over only stock files:
   - Metamod `bin/*` and SourceMod `bin/*`;
   - the stock extensions you already had under any name (`x.ext.so`, `x.ext.1.ep1.so`, `x.ext.2.ep1.so`);
   - `gamedata/`, `translations/` and `scripting/`;
   - missing `configs/` files;
   - stock plugins that are enabled now.

   Never overwrite your own plugins, configs or `plugins/disabled/`.
4. Put in the 1.13 builds of your third-party extensions, and disable `autoload` for the ones that have none yet.
5. Start with the same command line. Compare `sm exts list` and `sm plugins list` with the listing from before the
   change: same plugin count, no new `<Failed>` / `<Error>`, no new `<FAILED>` extension. On any difference, stop the
   server and unpack the backup.

It is worth scripting in two parts: one for the backup and stock-file copy, one for the move itself (A2S check for
zero players, baseline listing, upgrade, overlay of own extensions, comparison and automatic rollback).

## After the move

- MySQL HeatWave / 8.4: set `ssl_mode` in `databases.cfg` (README, "MySQL HeatWave / MySQL 8.4"); it also
  works with `"ssl_mode" "required"` through ProxySQL.
- `ShowHudText` draws on ClientMod; the stock v34 client may not show it. `SDKHook_GetMaxHealth` is not
  supported on v34; read `m_iMaxHealth` instead ([CHANGES.md](CHANGES.md), "Ours, not in upstream").
- A leftover `extensions/updater.ext.so` / `webternet.ext.so` is never loaded and can be deleted.
- Extensions to drop rather than port (their job is done elsewhere on these servers): `memoryhack` (`noroundend` from
  `fmu1337/blockroundend_v34` uses gamedata + `StoreToAddress`), `dosprotect` and `serversecure_files` (both covered
  by ProtectCMDS `FilterPacket` / `IsValidFileForTransfer`).
