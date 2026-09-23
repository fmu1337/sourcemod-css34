# CS:S v34 ΓÇö ╨╖╨░╨╝╨╡╤é╨║╨╕ ╨┐╨╛ ╨▓╨░╤Ç╨╕╨░╨╜╤é╤â SM 6522

╨í╤Ç╨░╨▓╨╜╨╡╨╜╨╕╨╡ ╨░╤Ç╤à╨╕╨▓╨░ `mms-1.11.0-1130_sourcemod-1.11.0-6522-css_v34-linux-up-git6541-10.05.2020-fix-gamedata-12.10.2020.zip` ╤ü ╤é╨╡╨║╤â╤ë╨╡╨╣ ╤ü╨▒╨╛╤Ç╨║╨╛╨╣ (SM **6572**).

╨ö╨░╤é╨░ ╨░╨╜╨░╨╗╨╕╨╖╨░: 2026-07-12.

## ╨ÿ╨┤╨╡╨╜╤é╨╕╤ä╨╕╨║╨░╤å╨╕╤Å ╨┐╨░╨║╨╡╤é╨░

| | ╨É╤Ç╤à╨╕╨▓ 6522 | ╨¥╨░╤ê builder |
|---|---|---|
| SourceMod | 1.11.0-6522 (git6541) | 1.11.0-6572 |
| Metamod | 1.11.0-1130 (╨▓ ╨║╨╛╨╝╨┐╨╗╨╡╨║╤é╨╡) | ╨╜╨╡ ╨▓╤à╨╛╨┤╨╕╤é |
| ╨æ╨╕╨╜╨░╤Ç╨╜╨╕╨║ SM | ╤é╨╛╨╗╤î╨║╨╛ `sourcemod.2.ep1.so` | `sourcemod.1/2.ep1.so` + extensions |
| ╨¢╨╕╨╜╨║╨╛╨▓╨║╨░ | `tier0_i486.so`, `vstdlib_i486.so` | ╤é╨╛ ╨╢╨╡ (ep1/v34) |
| Gamedata fix | 12.10.2020 | assets ╨╕╨╖ ╤Ç╨╡╨╗╨╕╨╖╨░ 6572 |

## Gamedata ΓÇö ╤é╤Ç╨╡╨▒╤â╨╡╤é ╤Ç╤â╤ç╨╜╨╛╨╣ ╨┐╤Ç╨╛╨▓╨╡╤Ç╨║╨╕

### sm-cstrike (`game.css.txt` ╨▓ ╨░╤Ç╤à╨╕╨▓╨╡ ΓåÆ `game.cstrike.txt` ╤â ╨╜╨░╤ü)

| ╨ƒ╨╛╨╗╨╡ | ╨É╤Ç╤à╨╕╨▓ 6522 | ╨¥╨░╤ê assets (6572) | ╨í╤é╨░╤é╤â╤ü |
|---|---|---|---|
| `WeaponPrice` | **2064** | **2308** | **╨ƒ╤Ç╨╛╨▓╨╡╤Ç╨╕╤é╤î ╨▓╤Ç╤â╤ç╨╜╤â╤Ä ╨╜╨░ ╤å╨╡╨╗╨╡╨▓╨╛╨╝ server.so** |
| `WeaponName` | 6 | 6 | ╤ü╨╛╨▓╨┐╨░╨┤╨░╨╡╤é |
| `CTTeamScoreOffset` | linux 23 | linux 23 | ╤ü╨╛╨▓╨┐╨░╨┤╨░╨╡╤é |
| `TTeamScoreOffset` | linux 34 | linux 34 | ╤ü╨╛╨▓╨┐╨░╨┤╨░╨╡╤é |
| Buy-╤ä╤â╨╜╨║╤å╨╕╤Å | `HandleCommand_Buy` | `HandleCommand_Buy_Internal` | ╤Ç╨░╨╖╨╜╤ï╨╡ ╨╕╨╝╨╡╨╜╨░/╤ü╨╕╨│╨╜╨░╤é╤â╤Ç╤ï |
| Linux sigs | `@_ZN...` mangled | `@_ZN...` mangled | ╤ü╨╛╨▓╨┐╨░╨┤╨░╤Ä╤é |
| Windows sigs | ╤ü╤é╨░╤Ç╤ï╨╣ prologue (`55 8B EC`) | post-OB ╤ü╤é╨╕╨╗╤î | **╤Ç╨░╨╖╨╜╤ï╨╡ ╨▒╨╕╨╗╨┤╤ï v34** |

Linux-╤ü╨╕╨│╨╜╨░╤é╤â╤Ç╤ï ╨▓ sm-cstrike ╤ü╨╛╨▓╨┐╨░╨┤╨░╤Ä╤é. ╨á╨░╤ü╤à╨╛╨╢╨┤╨╡╨╜╨╕╨╡ ╨▓ `WeaponPrice` ╨╕ Windows-╤ü╨╕╨│╨╜╨░╤é╤â╤Ç╨░╤à ╤â╨║╨░╨╖╤ï╨▓╨░╨╡╤é ╨╜╨░ **╤Ç╨░╨╖╨╜╤ï╨╡ ╨▒╨╕╨╗╨┤╤ï CS:S v34** ΓÇö ╨║╨░╨║╨╛╨╣ offset ╨▓╨╡╤Ç╨╜╤ï╨╣, ╨╛╨┐╤Ç╨╡╨┤╨╡╨╗╤Å╨╡╤é╤ü╤Å ╤é╨╛╨╗╤î╨║╨╛ ╤ü╨▓╨╡╤Ç╨║╨╛╨╣ ╤ü ╨║╨╛╨╜╨║╤Ç╨╡╤é╨╜╤ï╨╝ `server.so` / `server_i486.so` ╨╜╨░ ╤ü╨╡╤Ç╨▓╨╡╤Ç╨╡.

### sdktools.games/game.cstrike.txt (Linux vtable offsets)

╨ÿ╨╖ ╨░╤Ç╤à╨╕╨▓╨░ 6522 (upstream SM ╤é╨╛╨│╨╛ ╨▓╤Ç╨╡╨╝╨╡╨╜╨╕, ╨╜╨╡ ╨┐╨╡╤Ç╨╡╨╛╨┐╤Ç╨╡╨┤╨╡╨╗╤Å╨╗╤ü╤Å):

| Offset | Linux |
|---|---|
| GiveNamedItem | 330 |
| RemovePlayerItem | 227 |
| Weapon_GetSlot | 225 |
| Ignite | 189 |
| Extinguish | 190 |
| Teleport | 99 |
| CommitSuicide | 358 |
| GetVelocity | 127 |
| EyeAngles | 119 |
| AcceptInput | 36 |
| SetEntityModel | 26 |
| WeaponEquip | 218 |
| Activate | 33 |
| PlayerRunCmd | 348 |
| GiveAmmo | 214 |
| DispatchKeyValue | 30 |
| DispatchKeyValueFloat | 31 |
| DispatchKeyValueVector | 32 |

╨ú ╨╜╨░╤ü ╤ì╤é╨╛╤é ╤ä╨░╨╣╨╗ ╨╕╨┤╤æ╤é ╨╕╨╖ upstream SM **6572** ╨┐╤Ç╨╕ ╤ü╨▒╨╛╤Ç╨║╨╡ (`prepare-package.sh` ╨╡╨│╨╛ ╨╜╨╡ ╨┐╨╡╤Ç╨╡╨╖╨░╨┐╨╕╤ü╤ï╨▓╨░╨╡╤é). ╨ƒ╤Ç╨╕ ╨┐╤Ç╨╛╨▒╨╗╨╡╨╝╨░╤à ╤ü sdktools ╨╜╨░ Linux ΓÇö **╤ü╨▓╨╡╤Ç╨╕╤é╤î vtable offsets ╨▓╤Ç╤â╤ç╨╜╤â╤Ä** ╤ü `server.so` ╨╕ ╨┐╤Ç╨╕ ╨╜╨╡╨╛╨▒╤à╨╛╨┤╨╕╨╝╨╛╤ü╤é╨╕ ╨╖╨░╤ä╨╕╨║╤ü╨╕╤Ç╨╛╨▓╨░╤é╤î ╨▓ `builder/assets/gamedata/`.

### sdkhooks.games/game.cstrike.txt

╨É╤Ç╤à╨╕╨▓ ╤ü╨╛╨┤╨╡╤Ç╨╢╨╕╤é vtable offsets ╨┤╨╗╤Å ╤à╤â╨║╨╛╨▓ (`OnTakeDamage`, `FireBullets`, `Weapon_Switch` ╨╕ ╤é.╨┤.) ΓÇö ╤é╨╛╨╗╤î╨║╨╛ Linux/Windows ╤ç╨╕╤ü╨╗╨░, ╨▒╨╡╨╖ ╤ü╨╕╨│╨╜╨░╤é╤â╤Ç. ╨ú ╨╜╨░╤ü ╤é╨╛╨╢╨╡ ╨╕╨╖ upstream 6572. ╨ƒ╤Ç╨╕ ╤ü╨▒╨╛╤Å╤à sdkhooks ΓÇö ╤ü╨▓╨╡╤Ç╨╕╤é╤î ╨░╨╜╨░╨╗╨╛╨│╨╕╤ç╨╜╨╛ sdktools.

## ╨ƒ╨╛╨╗╨╡╨╖╨╜╨╛╨╡ ╨╕╨╖ ╨░╤Ç╤à╨╕╨▓╨░ (╨╜╨╡ ╨┐╨╡╤Ç╨╡╨╜╨╛╤ü╨╕╨╝ ╨▓ ╤ü╨▒╨╛╤Ç╨║╤â)

╨ù╨░╤ä╨╕╨║╤ü╨╕╤Ç╨╛╨▓╨░╨╜╨╛ ╨┤╨╗╤Å ╤ü╨┐╤Ç╨░╨▓╨║╨╕; ╨▓ builder ╨╜╨╡ ╨╕╨╜╤é╨╡╨│╤Ç╨╕╤Ç╨╛╨▓╨░╨╗╨╕ ╨┐╨╛ ╤Ç╨╡╤ê╨╡╨╜╨╕╤Ä 2026-07-12.

- **Cleaner** (`cleaner.ext.2.ep1.so`, `"Cleaner" "on"` ╨▓ core.cfg, `cleaner.cfg`) ΓÇö ╤ä╨╕╨╗╤î╤é╤Ç ╤ü╨┐╨░╨╝╨░ `CreateFragmentsFromFile`, `DataTable warning`
- **CSSDM** (`cssdm.ext.2.ep1.so`, `cssdm.games.txt`) ΓÇö FFA/deathmatch, ╨┐╨╡╤Ç╨╡╤ü╨▒╨╛╤Ç 2022-03-12
- **Warmode configs** (`cfg/sourcemod/sm_warmode_on.cfg`, `sm_warmode_off.cfg`)
- **Extra extensions**: flashtools, filenetmessages, bintools, sendproxy
- **Metamod bundle** MMS 1.11.0-1130 + `server_i486.so` ΓÇö ╤Ç╨╡╤ä╨╡╤Ç╨╡╨╜╤ü ╤ü╨╛╨▓╨╝╨╡╤ü╤é╨╕╨╝╨╛╨╣ ╨▓╨╡╤Ç╤ü╨╕╨╕
- **ServerLang `"ru"`** ╨▓ core.cfg ╨░╤Ç╤à╨╕╨▓╨░

## ╨º╤é╨╛ ╤â ╨╜╨░╤ê╨╡╨╣ ╤ü╨▒╨╛╤Ç╨║╨╕ ╨╗╤â╤ç╤ê╨╡

- SM **6572** + ╨┐╨╛╨╗╨╜╤ï╨╣ ╨╜╨░╨▒╨╛╤Ç CSS34-╨┐╨░╤é╤ç╨╡╨╣ (`builder/patches/apply-sourcemod.sh`)
- `DisableAutoUpdate "yes"` ╨▓ core.cfg (`builder/prepare-package.sh`)
- Gamedata sm-cstrike ╨╕╨╖ ╤Ç╨╡╨╗╨╕╨╖╨░ 6572 (╨░╨║╤é╤â╨░╨╗╤î╨╜╨╡╨╡ ╨┤╨╗╤Å ╤å╨╡╨╗╨╡╨▓╨╛╨│╨╛ v34)
- ╨í╨▒╨╛╤Ç╨║╨░ Linux + Windows, upstream translations

## ╨ñ╨░╨╣╨╗╤ï ╨┤╨╗╤Å ╤Ç╤â╤ç╨╜╨╛╨╣ ╨▓╨╡╤Ç╨╕╤ä╨╕╨║╨░╤å╨╕╨╕ offsets

╨ƒ╤Ç╨╕ ╨┐╤Ç╨╛╨▓╨╡╤Ç╨║╨╡ ╨╜╨░ ╨╢╨╕╨▓╨╛╨╝ ╤ü╨╡╤Ç╨▓╨╡╤Ç╨╡:

1. `addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt` ΓÇö `WeaponPrice`, Windows sigs
2. `addons/sourcemod/gamedata/sdktools.games/game.cstrike.txt` ΓÇö vtable offsets (Linux)
3. `addons/sourcemod/gamedata/sdkhooks.games/game.cstrike.txt` ΓÇö hook vtable offsets

╨¡╤é╨░╨╗╨╛╨╜╨╜╤ï╨╣ server binary: `cstrike/bin/server.so` ╨╕╨╗╨╕ `server_i486.so` ╤é╨╛╨│╨╛ ╨▒╨╕╨╗╨┤╨░ v34, ╨┐╨╛╨┤ ╨║╨╛╤é╨╛╤Ç╤ï╨╣ ╨╜╨░╤ü╤é╤Ç╨░╨╕╨▓╨░╨╡╤é╤ü╤Å ╤ü╨╡╤Ç╨▓╨╡╤Ç.

---

## ╨ó╨╡╨╝╨░ MyArena (╤ä╨╛╤Ç╤â╨╝)

╨ÿ╤ü╤é╨╛╤ç╨╜╨╕╨║: [╨ó╨╡╤ü╤é╨╕╤Ç╨╛╨▓╨░╨╜╨╕╨╡ SourceMod 1.11.0.6541 ╨┤╨╗╤Å CS:S v34](https://forum.myarena.ru/index.php?/topic/44234-testirovanie-sourcemod-versii-11106541-dlia-css-v34-10052020/) (GoDtm666, ~190 ╨┐╨╛╤ü╤é╨╛╨▓, ╨░╨┐╤Ç 2020 ΓÇö 2022).

╨¡╤é╨╛ **╤é╨╛╤é ╨╢╨╡ ╨░╤Ç╤à╨╕╨▓**, ╤ç╤é╨╛ ╨╗╨╡╨╢╨╕╤é ╨▓ ╤Ç╨╡╨┐╨╛╨╖╨╕╤é╨╛╤Ç╨╕╨╕. ╨É╨▓╤é╨╛╤Ç ΓÇö ╤Ç╨░╨╖╤Ç╨░╨▒╨╛╤é╤ç╨╕╨║ MyArena, ╤ü╨▒╨╛╤Ç╨║╨░ ╨┤╨╗╤Å ╨┐/╤â ╤à╨╛╤ü╤é╨╕╨╜╨│╨░.

### ╨Ü╨╗╤Ä╤ç╨╡╨▓╨╛╨╡ ╨╕╨╖ FAQ (╨┐╨╛╤ü╤é #1)

| # | ╨ƒ╤Ç╨╛╨▒╨╗╨╡╨╝╨░ | ╨á╨╡╤ê╨╡╨╜╨╕╨╡ ╨░╨▓╤é╨╛╤Ç╨░ |
|---|---|---|
| ΓÇö | ╨₧╨▒╨╜╨╛╨▓╨╗╨╡╨╜╨╕╨╡ | ╨º╨╕╤ü╤é╤ï╨╣ ╤ü╨╡╤Ç╨▓╨╡╤Ç + ╨▓╨╡╤ü╤î ╨░╤Ç╤à╨╕╨▓ ╤å╨╡╨╗╨╕╨║╨╛╨╝ (╨▓╨║╨╗╤Ä╤ç╨░╤Å MMS) |
| 6 | ╨í╤é╨░╤Ç╤ï╨╡ MM/ext ╨╜╨╡ ╤Ç╨░╨▒╨╛╤é╨░╤Ä╤é | ╨ó╨╛╨╗╤î╨║╨╛ **Metamod core 2** (MMS 1.11.0-1130); core-legacy ╨╜╨╡╤ü╨╛╨▓╨╝╨╡╤ü╤é╨╕╨╝ |
| 9 | ╨ƒ╨╗╨░╨│╨╕╨╜╤ï SM 1.9/1.10 | **╨ƒ╨╡╤Ç╨╡╨║╨╛╨╝╨┐╨╕╨╗╤Å╤å╨╕╤Å** ╨┐╨╛╨┤ SM 1.11 (╨║╨╛╨╝╨┐╨╕╨╗╤Å╤é╨╛╤Ç ╨▓ ╨░╤Ç╤à╨╕╨▓╨╡) |
| 12 | Stripper ╤ü ╨┐╨░╨╜╨╡╨╗╨╕ | ╨¥╤â╨╢╨╡╨╜ **stripper-1.2.2** ╨┐╨╛╨┤ ╨╜╨╛╨▓╤ï╨╣ MMS (╨╜╨╡ ╨╕╨╖ ╨┐/╤â) |
| 14 | SourceBans 1.5.1 | ╨ù╨░╨╝╨╡╨╜╨╕╤é╤î ╨╜╨░ ╨▓╨╡╤Ç╤ü╨╕╤Ä ╨╕╨╖ ╤é╨╡╨╝╤ï |
| **15** | `[CSTRIKE] Could not locate HandleCommand_Buy` | **╨ú╨┤╨░╨╗╨╕╤é╤î** `addons/sourcemod/gamedata/sm-cstrike.games.txt` ΓÇö ╨▓ ╨░╤Ç╤à╨╕╨▓╨╡ ╨╡╨│╨╛ ╨╜╨╡╤é, gamedata ╨╗╨╡╨╢╨╕╤é ╨▓ `sm-cstrike.games/game.css.txt` |
| 17 | ╨ú╤ü╤é╨░╨╜╨╛╨▓╨║╨░ ╨┐╨╛╨▓╨╡╤Ç╤à ╤ü╤é╨░╤Ç╨╛╨│╨╛ SM | ╨í╨╝. ╨┐.15 ΓÇö ╨║╨╛╨╜╤ä╨╗╨╕╨║╤é gamedata |
| 18 | ╨Ü╤Ç╨░╤ê╨╕ | `-debug` ╨▓ ╨┐╨░╤Ç╨░╨╝╨╡╤é╤Ç╨░╤à ╨╖╨░╨┐╤â╤ü╨║╨░ |
| 20 | ╨ƒ╨╗╨░╨│╨╕╨╜╤ï ╨╜╨╡ ╨│╤Ç╤â╨╖╤Å╤é╤ü╤Å (debug) | ╨ƒ╨╡╤Ç╨╡╤ü╨▒╨╛╤Ç╨║╨░ ╨┐╨╛╨┤ SM 1.11 |

╨Æ ╨┐╨░╨║╨╡╤é╨╡ ╨╕╨╖ ╨║╨╛╤Ç╨╛╨▒╨║╨╕: `cssdm.ext.2.ep1`, `sendproxy.ext.2.ep1`, `dhooks.ext`, `flashtools.ext.2.ep1`, MMS 1.11.0-dev+1130.

╨Æ╨╡╤Ç╤ü╨╕╤Å ╨▓ ╨╜╨░╨╖╨▓╨░╨╜╨╕╨╕ ╤ä╨░╨╣╨╗╨░ **6522**, ╨▓ FAQ ΓÇö **6541**: ╨░╨▓╤é╨╛╤Ç ╨┐╨╕╤ê╨╡╤é, ╤ç╤é╨╛ git-╨║╨╛╨╝╨╝╨╕╤é╤ï ╨╜╨╡ ╨▓╨╡╨┤╤â╤é╤ü╤Å, ╨╜╨╛╨╝╨╡╤Ç ╨▓ ╨╕╨╝╨╡╨╜╨╕ ╨░╤Ç╤à╨╕╨▓╨░ ╨╜╨╡ ╨╛╨▒╨╜╨╛╨▓╨╗╤Å╨╡╤é╤ü╤Å.

### Gamedata ╨╕╨╖ ╨╛╨▒╤ü╤â╨╢╨┤╨╡╨╜╨╕╤Å (╨▓╨░╨╢╨╜╨╛ ╨┤╨╗╤Å ╤Ç╤â╤ç╨╜╨╛╨╣ ╨┐╤Ç╨╛╨▓╨╡╤Ç╨║╨╕)

**GetWeaponPrice sigscan failed** (mifka, ╨╕╤Ä╨╗╤î 2020):

```
[CSTRIKE] Sigscan for GetWeaponPrice failed
```

╨á╨╡╤ê╨╡╨╜╨╕╨╡ (GoDtm666 ╨┐╨╛╨┤╤é╨▓╨╡╤Ç╨┤╨╕╨╗): ╨┐╤Ç╨░╨▓╨║╨░ ╤ü╨╕╨│╨╜╨░╤é╤â╤Ç╤ï **`GetWeaponPrice`** ╨▓ `gamedata/sm-cstrike.games/game.css.txt`. ╨í╨▓╤Å╨╖╨░╨╜╨╛ ╤ü offset **`WeaponPrice`** ΓÇö ╨┐╤Ç╨╕ ╨╛╤ê╨╕╨▒╨║╨╡ CS_GetWeaponPrice ╨┐╨╗╨░╨│╨╕╨╜╤ï (restrict, shop ╨╕ ╤é.╨┤.) ╨┐╨░╨┤╨░╤Ä╤é ╨▓ native trace.

**HandleCommand_Buy** (FAQ + ╤é╨╕╨┐╨╕╤ç╨╜╨░╤Å ╨╛╤ê╨╕╨▒╨║╨░ ╨┐╤Ç╨╕ ╨╝╨╕╨│╤Ç╨░╤å╨╕╨╕): ╤ü╤é╨░╤Ç╤ï╨╣ ╤ä╨░╨╣╨╗ `sm-cstrike.games.txt` (flat layout) ╨║╨╛╨╜╤ä╨╗╨╕╨║╤é╤â╨╡╤é ╤ü ╨╜╨╛╨▓╤ï╨╝ layout `sm-cstrike.games/game.css.txt`. ╨ú ╨╜╨░╤ü ╨▓ `prepare-package.sh` ╤â╨╢╨╡ ╨╕╤ü╨┐╨╛╨╗╤î╨╖╤â╨╡╤é╤ü╤Å `game.cstrike.txt` ΓÇö ╨╜╨╛ ╨┐╤Ç╨╕ ╤â╤ü╤é╨░╨╜╨╛╨▓╨║╨╡ ╨┐╨╛╨▓╨╡╤Ç╤à ╤ç╤â╨╢╨╛╨│╨╛ SM ╤ü╤é╨░╤Ç╤ï╨╣ flat-╤ä╨░╨╣╨╗ ╨╜╤â╨╢╨╜╨╛ ╤â╨┤╨░╨╗╤Å╤é╤î ╨▓╤Ç╤â╤ç╨╜╤â╤Ä.

**HudTextMsg / HUD ╤ü╨▓╨╡╤Ç╤à╤â** (GoDtm666, ╨┤╨╡╨║ 2021): ╨╡╤ü╨╗╨╕ ╨┐╨╡╤Ç╨╡╤ü╤é╨░╨╗ ╤Ç╨░╨▒╨╛╤é╨░╤é╤î HUD-╤é╨╡╨║╤ü╤é ΓÇö ╨▓ `gamedata/core.games/common.games.txt` **╤â╨▒╤Ç╨░╤é╤î ╨║╨╛╨╝╨╝╨╡╨╜╤é╨░╤Ç╨╕╨╣** ╨╜╨░ `HudTextMsg`.

### ╨ú╤ü╤é╨░╨╜╨╛╨▓╨║╨░ ╨╕ ╤ü╨╛╨▓╨╝╨╡╤ü╤é╨╕╨╝╨╛╤ü╤é╤î

- **VDS / ╨┤╤Ç╤â╨│╨╛╨╣ ╤à╨╛╤ü╤é╨╕╨╜╨│**: ╤ç╨░╤ü╤é╤î ╨┐╨╛╨╗╤î╨╖╨╛╨▓╨░╤é╨╡╨╗╨╡╨╣ ╨╜╨╡ ╨▓╨╕╨┤╨╡╨╗╨░ SM ╨▓ `meta list` ΓÇö ╨░╨▓╤é╨╛╤Ç ╤ü╨╛╨▓╨╡╤é╤â╨╡╤é ╤â╨┤╨░╨╗╨╕╤é╤î ╨▓╤ü╤Ä `addons/` ╨╕ ╨╖╨░╨╗╨╕╤é╤î ╨░╤Ç╤à╨╕╨▓ **╨▒╨╡╨╖ ╨╕╤ü╨║╨╗╤Ä╤ç╨╡╨╜╨╕╨╣** (MMS ╨╕╨╖ ╨┐╨░╨║╨╡╤é╨░ ╨╛╨▒╤Å╨╖╨░╤é╨╡╨╗╨╡╨╜). ╨¢╨╛╨│╨╕: `+developer 1 +log on`.
- **Ubuntu 18.04**: `undefined symbol: pthread_mutex_trylock` ╨▓ `sourcepawn.jit.x86.so` / `clientprefs.ext.so` ΓÇö ╨┐╤Ç╨╛╨▒╨╗╨╡╨╝╨░ ╨╛╨║╤Ç╤â╨╢╨╡╨╜╨╕╤Å (glibc/pthread), ╨╜╨╡ gamedata.
- **6572 vs MyArena 6541** (KURTSEITOV, ╨┤╨╡╨║ 2021): ╨▓ ╤é╨╡╨╝╨╡ ╤ü╨┐╤Ç╨░╤ê╨╕╨▓╨░╨╗╨╕, ╤ç╤é╨╛ ╨╗╤â╤ç╤ê╨╡ ΓÇö MyArena ╨╕╨╗╨╕ `sourcemod-1.11.0-git6572-css34` (rom4s). ╨»╨▓╨╜╨╛╨│╨╛ ╨╛╤é╨▓╨╡╤é╨░ ╨░╨▓╤é╨╛╤Ç╨░ ╨▓ ╤é╨╡╨╝╨╡ ╨╜╨╡╤é; rom4s 6572 ΓÇö ╨▒╨╛╨╗╨╡╨╡ ╨┐╨╛╨╖╨┤╨╜╤Å╤Å community-╤ü╨▒╨╛╤Ç╨║╨░ ╤ü ╨╛╤é╨┤╨╡╨╗╤î╨╜╤ï╨╝ gamedata.

### ╨ƒ╤Ç╨╛╤ç╨╡╨╡ ╨╕╨╖ ╤é╨╡╨╝╤ï (╤ü╨┐╤Ç╨░╨▓╨╛╤ç╨╜╨╛)

- CSSDM: ╨▓ ╨┐╨░╨║╨╡╤é╨╡ ╤ü╨▓╨╛╨╣ `cssdm.ext.2.ep1`; ╨╛╤é╨┤╨╡╨╗╤î╨╜╤ï╨╣ `cssdm-2.1.6-dev-git226-css34-linux` ╤â ╨╜╨╡╨║╨╛╤é╨╛╤Ç╤ï╤à ╨║╤Ç╨░╤ê╨╕╨╗ ΓÇö ╨╜╤â╨╢╨╡╨╜ ext ╨╕╨╖ ╨░╤Ç╤à╨╕╨▓╨░.
- Stripper 1.2.2 ╤ü ╤ä╨╛╤Ç╤â╨╝╨░ ╤Ç╨░╨▒╨╛╤é╨░╨╡╤é ╤ü MMS core 2; stripper ╤ü ╨┐╨░╨╜╨╡╨╗╨╕ ΓÇö ╨╜╨╡╤é.
- Windows: ╨░╨▓╤é╨╛╤Ç **╨╜╨╡ ╨▓╤ï╨║╨╗╨░╨┤╤ï╨▓╨░╨╗** Windows-╤ü╨▒╨╛╤Ç╨║╤â (╤é╨╛╨╗╤î╨║╨╛ Linux ╨┤╨╗╤Å ╤é╨╡╤ü╤é╨░ ╨┐/╤â).
- ╨ƒ╨╗╨░╨│╨╕╨╜╤ï SM 1.10 API ╨╜╨░ SM 1.9 ╨╜╨╡ ╤Ç╨░╨▒╨╛╤é╨░╤Ä╤é ΓÇö ╨│╨╗╨░╨▓╨╜╨░╤Å ╨┐╤Ç╨╕╤ç╨╕╨╜╨░ ╨┐╨╡╤Ç╨╡╤à╨╛╨┤╨░ ╨╜╨░ 1.11 ╨┤╨╗╤Å v34 (Nekro).

### ╨º╤é╨╛ ╤Ç╨╡╨╗╨╡╨▓╨░╨╜╤é╨╜╨╛ ╨╜╨░╤ê╨╡╨╝╤â builder

| ╨¥╨░╤à╨╛╨┤╨║╨░ | ╨ö╨╡╨╣╤ü╤é╨▓╨╕╨╡ |
|---|---|
| `WeaponPrice` / `GetWeaponPrice` sig | **╨ƒ╤Ç╨╛╨▓╨╡╤Ç╨╕╤é╤î ╨▓╤Ç╤â╤ç╨╜╤â╤Ä** ╨╜╨░ ╤å╨╡╨╗╨╡╨▓╨╛╨╝ server.so |
| Flat `sm-cstrike.games.txt` vs `game.cstrike.txt` | ╨ƒ╤Ç╨╕ ╨╝╨╕╨│╤Ç╨░╤å╨╕╨╕ ╤â╨┤╨░╨╗╤Å╤é╤î ╤ü╤é╨░╤Ç╤ï╨╣ flat-╤ä╨░╨╣╨╗ |
| `HudTextMsg` ╨▓ common.games.txt | ╨ƒ╤Ç╨╛╨▓╨╡╤Ç╨╕╤é╤î, ╨╡╤ü╨╗╨╕ HUD-╤é╨╡╨║╤ü╤é ╨╜╨╡ ╤Ç╨░╨▒╨╛╤é╨░╨╡╤é |
| MyArena 6541 vs rom4s 6572 | ╨¥╨░╤ê builder = 6572; gamedata ╨╜╨╛╨▓╨╡╨╡ |
| MMS 1.11.0-1130 | ╨á╨╡╤ä╨╡╤Ç╨╡╨╜╤ü ╨┤╨╗╤Å ╤ü╨╛╨▓╨╝╨╡╤ü╤é╨╕╨╝╨╛╤ü╤é╨╕, ╨▓ ╨┐╨░╨║╨╡╤é ╨╜╨╡ ╨▓╤à╨╛╨┤╨╕╤é |

---

## ╨ó╨╡╨╝╨░ HLmod ΓÇö FrozDark SM 1.7.1 (2015)

╨ÿ╤ü╤é╨╛╤ç╨╜╨╕╨║: [[CS:S v34] Metamod 1.10.4 + Sourcemod 1.7.1 + FlashTools (Windows only)](https://hlmod.net/threads/cs-s-v34-metamod-1-10-4-sourcemod-1-7-1-flashtools-windows-only.28468/) (FrozDark, ╨░╨┐╤Ç 2015).

╨á╨░╨╜╨╜╤Å╤Å community-╤ü╨▒╨╛╤Ç╨║╨░ ╨┐╨╛╨┤ v34. Windows-only zip + ╨╛╤é╨┤╨╡╨╗╤î╨╜╤ï╨╣ **`game.css.txt`** (╨▓╨╗╨╛╨╢╨╡╨╜╨╕╨╡ ╨▓ ╤é╨╡╨╝╨╡). ╨í╨▓╤Å╨╖╨░╨╜╨╜╨░╤Å ╤é╨╡╨╝╨░: [[CS:S v34] Virtual Offsets](https://hlmod.net/threads/cs-s-v34-virtual-offsets.28417/) (FrozDark, ╨░╨┐╤Ç 2015).

### ╨º╤é╨╛ ╨┤╨╡╨╗╨░╨╗ FrozDark (╤Ç╨╡╨╗╨╡╨▓╨░╨╜╤é╨╜╨╛ ╨┤╨╗╤Å ╨┐╨░╤é╤ç╨╡╨╣)

| ╨ÿ╨╖╨╝╨╡╨╜╨╡╨╜╨╕╨╡ | ╨ö╨╡╤é╨░╨╗╨╕ |
|---|---|
| **cstrike extension** | ╨Æ╤ï╤Ç╨╡╨╖╨░╨╜╤ï natives ╤é╨╛╨╗╤î╨║╨╛ ╨┤╨╗╤Å OB/CS:GO: `Set/GetMVPCount`, `Set/GetContributionScore`, `Set/GetAssists`, `Set/GetClanTag` |
| **cstrike.inc** | ╨É╨┤╨░╨┐╤é╨╕╤Ç╨╛╨▓╨░╨╜ `CSRoundEndReason`; ╤â╨┤╨░╨╗╨╡╨╜╤ï ╤ä╤â╨╜╨║╤å╨╕╨╕, ╨╜╨╡╨┤╨╛╤ü╤é╤â╨┐╨╜╤ï╨╡ ╨╜╨░ v34 |
| **Extensions** | Flashbang Tools, CBaseServer Tools (Windows) |
| **core.cfg** | ┬½╨¥╨╡ ╨╕╨╖╨╝╨╡╨╜╤Å╨╣╤é╨╡┬╗ ΓÇö ╨║╨░╤ü╤é╨╛╨╝╨╜╤ï╨╣ ╨║╨╛╨╜╤ä╨╕╨│ ╨▓ ╨┐╨░╨║╨╡╤é╨╡ |
| **Gamedata** | ╨ƒ╨╛╨┤╨║╨╛╤Ç╤Ç╨╡╨║╤é╨╕╤Ç╨╛╨▓╨░╨╜╤ï ╤ü╨╕╨│╨╜╨░╤é╤â╤Ç╤ï **`GetWeaponPrice`** ╨╕ **`GetTranslatedWeaponAlias`** ╨▓ `game.css.txt` (╨╛╤é╨┤╨╡╨╗╤î╨╜╨╛╨╡ ╨▓╨╗╨╛╨╢╨╡╨╜╨╕╨╡ ╨┐╨╛╤ü╨╗╨╡ ╨┐╨╡╤Ç╨▓╨╛╨│╨╛ ╤Ç╨╡╨╗╨╕╨╖╨░) |

### Gamedata / offsets (╤Ç╤â╤ç╨╜╨░╤Å ╨┐╤Ç╨╛╨▓╨╡╤Ç╨║╨░)

1. **`GetWeaponPrice` + `GetTranslatedWeaponAlias`** ΓÇö FrozDark ╤Å╨▓╨╜╨╛ ╨┐╤Ç╨░╨▓╨╕╨╗ ╤ü╨╕╨│╨╜╨░╤é╤â╤Ç╤ï ╨┐╨╛╨┤ v34 Windows. ╨¡╤é╨╛ **╤é╨╛╤é ╨╢╨╡ ╨║╨╗╨░╤ü╤ü ╨┐╤Ç╨╛╨▒╨╗╨╡╨╝**, ╤ç╤é╨╛ `WeaponPrice` offset ╨╕ sigscan failed ╨▓ MyArena-╤é╨╡╨╝╨╡. ╨ƒ╤Ç╨╕ ╨┐╤Ç╨╛╨▓╨╡╤Ç╨║╨╡ ╤ü╨▓╨╡╤Ç╤Å╤é╤î ╨╛╨▒╨░ ╨┐╨╛╨╗╤Å ╨▓ `sm-cstrike.games/game.cstrike.txt`.

2. **Virtual offsets (Linux)** ΓÇö FrozDark ╨▓╤ï╨╗╨╛╨╢╨╕╨╗ ╨┐╨╛╨╗╨╜╤ï╨╣ vtable-╤ü╨┐╨╕╤ü╨╛╨║ CCSPlayer. ╨Ü╨╗╤Ä╤ç╨╡╨▓╤ï╨╡ ╨╕╨╜╨┤╨╡╨║╤ü╤ï ╤ü╨╛╨▓╨┐╨░╨┤╨░╤Ä╤é ╤ü sdktools gamedata ╨╕╨╖ ╨░╤Ç╤à╨╕╨▓╨░ MyArena 6522:

   | ╨ñ╤â╨╜╨║╤å╨╕╤Å | Linux vtable |
   |---|---|
   | GiveNamedItem | **330** |
   | RemovePlayerItem | 227 |
   | Weapon_GetSlot | 225 |
   | PlayerRunCmd | **348** |
   | CommitSuicide | 358 |
   | Ignite / Extinguish | 189 / 190 |
   | Teleport | 99 |

   **Windows: `offset - 1`** ╨╛╤é Linux-╨╖╨╜╨░╤ç╨╡╨╜╨╕╤Å (╨┐╤Ç╨░╨▓╨╕╨╗╨╛ FrozDark ╨┤╨╗╤Å v34).

3. **Linux + ╨╜╨╛╨▓╤ï╨╡ ╨▒╨╕╨╜╨░╤Ç╨╜╨╕╨║╨╕ SM/MM** ΓÇö FrozDark ╨┐╨╕╤ü╨░╨╗: ╨╝╨╛╨╢╨╜╨╛ ╤ü╤é╨░╨▓╨╕╤é╤î ╤ü╨▓╨╡╨╢╨╕╨╡ Linux-╨▒╨╕╨╜╨░╤Ç╨╜╨╕╨║╨╕ SM/MM **╨▒╨╡╨╖ ╨╖╨░╨╝╨╡╨╜╤ï gamedata**, ╨╜╨╛ **╨╜╨╡ ╨▒╤â╨┤╤â╤é ╤Ç╨░╨▒╨╛╤é╨░╤é╤î** flashtools ╨╕ cstrike extension ╨▒╨╡╨╖ ╨┐╨╡╤Ç╨╡╤ü╨▒╨╛╤Ç╨║╨╕ ╨┐╨╛╨┤ v34 (Release - Old Metamod).

### Windows-╤ü╨┐╨╡╤å╨╕╤ä╨╕╨║╨░ (╨╕╨╖ ╨╛╨▒╤ü╤â╨╢╨┤╨╡╨╜╨╕╤Å ╨▒╨░╨│╨╛╨▓)

| ╨æ╨░╨│ | ╨ƒ╤Ç╨╕╤ç╨╕╨╜╨░ / workaround |
|---|---|
| `game.cstrike.ext` ╨╜╨╡ ╨│╤Ç╤â╨╖╨╕╤é╤ü╤Å ╨╜╨░ Win2003 | `InitOnceExecuteOnce` ╨╜╨╡╤é ╨▓ KERNEL32.dll (SM ╤ü╨╛╨▒╤Ç╨░╨╜ ╨┐╨╛╨┤ Win7+) |
| `exit`/`quit` ╨║╤Ç╨░╤ê╨╕╤é ╤ü╨╡╤Ç╨▓╨╡╤Ç | ╨ù╨░╨╝╨╡╤ç╨╡╨╜╨╛ ╨╜╨░ Win2003; ╨╜╨░ Win8.1 ╤â ╨░╨▓╤é╨╛╤Ç╨░ ╨╜╨╡ ╨▓╨╛╤ü╨┐╤Ç╨╛╨╕╨╖╨▓╨╛╨┤╨╕╨╗╨╛╤ü╤î |
| `PrintHintText` + ╨║╨╕╤Ç╨╕╨╗╨╗╨╕╤å╨░ | ╨Ü╤Ç╨░╨║╨╛╨╖╤Å╨▒╤Ç╤ï ΓÇö workaround: ╨┐╤Ç╨╛╨▒╨╡╨╗ ╨▓ ╨╜╨░╤ç╨░╨╗╨╡ ╤ü╤é╤Ç╨╛╨║╨╕ |
| ╨Ü╤Ç╨░╤ê ╨┐╤Ç╨╕ ╨┤╨╡╤é╨╛╨╜╨░╤å╨╕╨╕ C4 | ╨Ü╨╛╨╜╤ä╨╗╨╕╨║╤é weapon limit (wS) + SMAC; ╨┐╨╛ ╨╛╤é╨┤╨╡╨╗╤î╨╜╨╛╤ü╤é╨╕ ╤Ç╨░╨▒╨╛╤é╨░╨╗╨╕ |
| Rename ╤ç╨╡╤Ç╨╡╨╖ admin menu | ╨Ü╤Ç╨░╤ê ΓÇö ┬½╨╛╤ü╨╛╨▒╨╡╨╜╨╜╨╛╤ü╤é╤î Orangebox┬╗; ╤ü╤é╨░╤Ç╤ï╨╣ basecommands ╨╕╨╗╨╕ ╨╖╨░╨║╨╛╨╝╨╝╨╡╨╜╤é╨╕╤Ç╨╛╨▓╨░╤é╤î 3 ╤ü╤é╤Ç╨╛╨║╨╕ |

### ╨º╤é╨╛ ╤Ç╨╡╨╗╨╡╨▓╨░╨╜╤é╨╜╨╛ ╨╜╨░╤ê╨╡╨╝╤â builder (6572)

| ╨¥╨░╤à╨╛╨┤╨║╨░ | ╨í╤é╨░╤é╤â╤ü ╤â ╨╜╨░╤ü |
|---|---|
| ╨Æ╤ï╤Ç╨╡╨╖ OB-only cstrike natives | ╨º╨░╤ü╤é╨╕╤ç╨╜╨╛ ╤ç╨╡╤Ç╨╡╨╖ `#if SOURCE_ENGINE >= SE_ORANGEBOX && SOURCE_ENGINE != SE_CSS` ╨▓ `apply-sourcemod.sh` |
| `GetWeaponPrice` / `GetTranslatedWeaponAlias` sigs | ╨Æ `builder/assets/gamedata/.../game.cstrike.txt` ΓÇö **╨┐╤Ç╨╛╨▓╨╡╤Ç╨╕╤é╤î ╨▓╤Ç╤â╤ç╨╜╤â╤Ä** |
| sdktools vtable offsets (Linux 330/348/ΓÇª) | ╨ÿ╨╖ upstream 6572; ╤ü╨╛╨▓╨┐╨░╨┤╨░╤Ä╤é ╤ü FrozDark/MyArena 6522 ΓÇö ╤à╨╛╤Ç╨╛╤ê╨╕╨╣ ╨╖╨╜╨░╨║ ╨┤╨╗╤Å Linux |
| Windows vtable = Linux ΓêÆ 1 | ╨ú╤ç╨╕╤é╤ï╨▓╨░╤é╤î ╨┐╤Ç╨╕ ╨▓╨╡╤Ç╨╕╤ä╨╕╨║╨░╤å╨╕╨╕ Windows gamedata |
| FrozDark `game.css.txt` (2015) | ╨ÿ╤ü╤é╨╛╤Ç╨╕╤ç╨╡╤ü╨║╨╕╨╣ ╤Ç╨╡╤ä╨╡╤Ç╨╡╨╜╤ü; ╨╜╨░╤ê╨╕ sigs ╨╜╨╛╨▓╨╡╨╡ (6572), ╨╜╨╛ offset/signature logic ╤é╨╛╤é ╨╢╨╡ |

╨í╨▓╤Å╨╖╨░╨╜╨╜╨░╤Å ╤é╨╡╨╝╨░ (╨╜╨╡ ╨┐╤Ç╨╛╤ç╨╕╤é╨░╨╜╨░ ΓÇö Cloudflare): `[CS:S v34] ╨í╨╕╨│╨╜╨░╤é╤â╤Ç╤ï ╤ä╤â╨╜╨║╤å╨╕╨╕` (FrozDark, ╨░╨┐╤Ç 2015) ΓÇö ╨▓╨╡╤Ç╨╛╤Å╤é╨╜╨╛ ╤Ç╨░╤ü╤ê╨╕╤Ç╨╡╨╜╨╜╤ï╨╣ ╤ü╨┐╨╕╤ü╨╛╨║ sigs.
