# CS:S v34 — заметки по варианту SM 6522

Сравнение архива `mms-1.11.0-1130_sourcemod-1.11.0-6522-css_v34-linux-up-git6541-10.05.2020-fix-gamedata-12.10.2020.zip` с текущей сборкой (SM **6572**).

Дата анализа: 2026-07-12.

## Идентификация пакета

| | Архив 6522 | Наш builder |
|---|---|---|
| SourceMod | 1.11.0-6522 (git6541) | 1.11.0-6572 |
| Metamod | 1.11.0-1130 (в комплекте) | не входит |
| Бинарник SM | только `sourcemod.2.ep1.so` | `sourcemod.1/2.ep1.so` + extensions |
| Линковка | `tier0_i486.so`, `vstdlib_i486.so` | то же (ep1/v34) |
| Gamedata fix | 12.10.2020 | assets из релиза 6572 |

## Gamedata — требует ручной проверки

### sm-cstrike (`game.css.txt` в архиве → `game.cstrike.txt` у нас)

| Поле | Архив 6522 | Наш assets (6572) | Статус |
|---|---|---|---|
| `WeaponPrice` | **2064** | **2308** | **Проверить вручную на целевом server.so** |
| `WeaponName` | 6 | 6 | совпадает |
| `CTTeamScoreOffset` | linux 23 | linux 23 | совпадает |
| `TTeamScoreOffset` | linux 34 | linux 34 | совпадает |
| Buy-функция | `HandleCommand_Buy` | `HandleCommand_Buy_Internal` | разные имена/сигнатуры |
| Linux sigs | `@_ZN...` mangled | `@_ZN...` mangled | совпадают |
| Windows sigs | старый prologue (`55 8B EC`) | post-OB стиль | **разные билды v34** |

Linux-сигнатуры в sm-cstrike совпадают. Расхождение в `WeaponPrice` и Windows-сигнатурах указывает на **разные билды CS:S v34** — какой offset верный, определяется только сверкой с конкретным `server.so` / `server_i486.so` на сервере.

### sdktools.games/game.cstrike.txt (Linux vtable offsets)

Из архива 6522 (upstream SM того времени, не переопределялся):

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

У нас этот файл идёт из upstream SM **6572** при сборке (`prepare-package.sh` его не перезаписывает). При проблемах с sdktools на Linux — **сверить vtable offsets вручную** с `server.so` и при необходимости зафиксировать в `builder/assets/gamedata/`.

### sdkhooks.games/game.cstrike.txt

Архив содержит vtable offsets для хуков (`OnTakeDamage`, `FireBullets`, `Weapon_Switch` и т.д.) — только Linux/Windows числа, без сигнатур. У нас тоже из upstream 6572. При сбоях sdkhooks — сверить аналогично sdktools.

## Полезное из архива (не переносим в сборку)

Зафиксировано для справки; в builder не интегрировали по решению 2026-07-12.

- **Cleaner** (`cleaner.ext.2.ep1.so`, `"Cleaner" "on"` в core.cfg, `cleaner.cfg`) — фильтр спама `CreateFragmentsFromFile`, `DataTable warning`
- **CSSDM** (`cssdm.ext.2.ep1.so`, `cssdm.games.txt`) — FFA/deathmatch, пересбор 2022-03-12
- **Warmode configs** (`cfg/sourcemod/sm_warmode_on.cfg`, `sm_warmode_off.cfg`)
- **Extra extensions**: flashtools, filenetmessages, bintools, sendproxy
- **Metamod bundle** MMS 1.11.0-1130 + `server_i486.so` — референс совместимой версии
- **ServerLang `"ru"`** в core.cfg архива

## Что у нашей сборки лучше

- SM **6572** + полный набор CSS34-патчей (`builder/patches/apply-sourcemod.sh`)
- `DisableAutoUpdate "yes"` в core.cfg (`builder/prepare-package.sh`)
- Gamedata sm-cstrike из релиза 6572 (актуальнее для целевого v34)
- Сборка Linux + Windows, upstream translations

## Файлы для ручной верификации offsets

При проверке на живом сервере:

1. `addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt` — `WeaponPrice`, Windows sigs
2. `addons/sourcemod/gamedata/sdktools.games/game.cstrike.txt` — vtable offsets (Linux)
3. `addons/sourcemod/gamedata/sdkhooks.games/game.cstrike.txt` — hook vtable offsets

Эталонный server binary: `cstrike/bin/server.so` или `server_i486.so` того билда v34, под который настраивается сервер.
