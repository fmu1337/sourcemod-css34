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

---

## Тема MyArena (форум)

Источник: [Тестирование SourceMod 1.11.0.6541 для CS:S v34](https://forum.myarena.ru/index.php?/topic/44234-testirovanie-sourcemod-versii-11106541-dlia-css-v34-10052020/) (GoDtm666, ~190 постов, апр 2020 — 2022).

Это **тот же архив**, что лежит в репозитории. Автор — разработчик MyArena, сборка для п/у хостинга.

### Ключевое из FAQ (пост #1)

| # | Проблема | Решение автора |
|---|---|---|
| — | Обновление | Чистый сервер + весь архив целиком (включая MMS) |
| 6 | Старые MM/ext не работают | Только **Metamod core 2** (MMS 1.11.0-1130); core-legacy несовместим |
| 9 | Плагины SM 1.9/1.10 | **Перекомпиляция** под SM 1.11 (компилятор в архиве) |
| 12 | Stripper с панели | Нужен **stripper-1.2.2** под новый MMS (не из п/у) |
| 14 | SourceBans 1.5.1 | Заменить на версию из темы |
| **15** | `[CSTRIKE] Could not locate HandleCommand_Buy` | **Удалить** `addons/sourcemod/gamedata/sm-cstrike.games.txt` — в архиве его нет, gamedata лежит в `sm-cstrike.games/game.css.txt` |
| 17 | Установка поверх старого SM | См. п.15 — конфликт gamedata |
| 18 | Краши | `-debug` в параметрах запуска |
| 20 | Плагины не грузятся (debug) | Пересборка под SM 1.11 |

В пакете из коробки: `cssdm.ext.2.ep1`, `sendproxy.ext.2.ep1`, `dhooks.ext`, `flashtools.ext.2.ep1`, MMS 1.11.0-dev+1130.

Версия в названии файла **6522**, в FAQ — **6541**: автор пишет, что git-коммиты не ведутся, номер в имени архива не обновляется.

### Gamedata из обсуждения (важно для ручной проверки)

**GetWeaponPrice sigscan failed** (mifka, июль 2020):

```
[CSTRIKE] Sigscan for GetWeaponPrice failed
```

Решение (GoDtm666 подтвердил): правка сигнатуры **`GetWeaponPrice`** в `gamedata/sm-cstrike.games/game.css.txt`. Связано с offset **`WeaponPrice`** — при ошибке CS_GetWeaponPrice плагины (restrict, shop и т.д.) падают в native trace.

**HandleCommand_Buy** (FAQ + типичная ошибка при миграции): старый файл `sm-cstrike.games.txt` (flat layout) конфликтует с новым layout `sm-cstrike.games/game.css.txt`. У нас в `prepare-package.sh` уже используется `game.cstrike.txt` — но при установке поверх чужого SM старый flat-файл нужно удалять вручную.

**HudTextMsg / HUD сверху** (GoDtm666, дек 2021): если перестал работать HUD-текст — в `gamedata/core.games/common.games.txt` **убрать комментарий** на `HudTextMsg`.

### Установка и совместимость

- **VDS / другой хостинг**: часть пользователей не видела SM в `meta list` — автор советует удалить всю `addons/` и залить архив **без исключений** (MMS из пакета обязателен). Логи: `+developer 1 +log on`.
- **Ubuntu 18.04**: `undefined symbol: pthread_mutex_trylock` в `sourcepawn.jit.x86.so` / `clientprefs.ext.so` — проблема окружения (glibc/pthread), не gamedata.
- **6572 vs MyArena 6541** (KURTSEITOV, дек 2021): в теме спрашивали, что лучше — MyArena или `sourcemod-1.11.0-git6572-css34` (rom4s). Явного ответа автора в теме нет; rom4s 6572 — более поздняя community-сборка с отдельным gamedata.

### Прочее из темы (справочно)

- CSSDM: в пакете свой `cssdm.ext.2.ep1`; отдельный `cssdm-2.1.6-dev-git226-css34-linux` у некоторых крашил — нужен ext из архива.
- Stripper 1.2.2 с форума работает с MMS core 2; stripper с панели — нет.
- Windows: автор **не выкладывал** Windows-сборку (только Linux для теста п/у).
- Плагины SM 1.10 API на SM 1.9 не работают — главная причина перехода на 1.11 для v34 (Nekro).

### Что релевантно нашему builder

| Находка | Действие |
|---|---|
| `WeaponPrice` / `GetWeaponPrice` sig | **Проверить вручную** на целевом server.so |
| Flat `sm-cstrike.games.txt` vs `game.cstrike.txt` | При миграции удалять старый flat-файл |
| `HudTextMsg` в common.games.txt | Проверить, если HUD-текст не работает |
| MyArena 6541 vs rom4s 6572 | Наш builder = 6572; gamedata новее |
| MMS 1.11.0-1130 | Референс для совместимости, в пакет не входит |

---

## Тема HLmod — FrozDark SM 1.7.1 (2015)

Источник: [[CS:S v34] Metamod 1.10.4 + Sourcemod 1.7.1 + FlashTools (Windows only)](https://hlmod.net/threads/cs-s-v34-metamod-1-10-4-sourcemod-1-7-1-flashtools-windows-only.28468/) (FrozDark, апр 2015).

Ранняя community-сборка под v34. Windows-only zip + отдельный **`game.css.txt`** (вложение в теме). Связанная тема: [[CS:S v34] Virtual Offsets](https://hlmod.net/threads/cs-s-v34-virtual-offsets.28417/) (FrozDark, апр 2015).

### Что делал FrozDark (релевантно для патчей)

| Изменение | Детали |
|---|---|
| **cstrike extension** | Вырезаны natives только для OB/CS:GO: `Set/GetMVPCount`, `Set/GetContributionScore`, `Set/GetAssists`, `Set/GetClanTag` |
| **cstrike.inc** | Адаптирован `CSRoundEndReason`; удалены функции, недоступные на v34 |
| **Extensions** | Flashbang Tools, CBaseServer Tools (Windows) |
| **core.cfg** | «Не изменяйте» — кастомный конфиг в пакете |
| **Gamedata** | Подкорректированы сигнатуры **`GetWeaponPrice`** и **`GetTranslatedWeaponAlias`** в `game.css.txt` (отдельное вложение после первого релиза) |

### Gamedata / offsets (ручная проверка)

1. **`GetWeaponPrice` + `GetTranslatedWeaponAlias`** — FrozDark явно правил сигнатуры под v34 Windows. Это **тот же класс проблем**, что `WeaponPrice` offset и sigscan failed в MyArena-теме. При проверке сверять оба поля в `sm-cstrike.games/game.cstrike.txt`.

2. **Virtual offsets (Linux)** — FrozDark выложил полный vtable-список CCSPlayer. Ключевые индексы совпадают с sdktools gamedata из архива MyArena 6522:

   | Функция | Linux vtable |
   |---|---|
   | GiveNamedItem | **330** |
   | RemovePlayerItem | 227 |
   | Weapon_GetSlot | 225 |
   | PlayerRunCmd | **348** |
   | CommitSuicide | 358 |
   | Ignite / Extinguish | 189 / 190 |
   | Teleport | 99 |

   **Windows: `offset - 1`** от Linux-значения (правило FrozDark для v34).

3. **Linux + новые бинарники SM/MM** — FrozDark писал: можно ставить свежие Linux-бинарники SM/MM **без замены gamedata**, но **не будут работать** flashtools и cstrike extension без пересборки под v34 (Release - Old Metamod).

### Windows-специфика (из обсуждения багов)

| Баг | Причина / workaround |
|---|---|
| `game.cstrike.ext` не грузится на Win2003 | `InitOnceExecuteOnce` нет в KERNEL32.dll (SM собран под Win7+) |
| `exit`/`quit` крашит сервер | Замечено на Win2003; на Win8.1 у автора не воспроизводилось |
| `PrintHintText` + кириллица | Кракозябры — workaround: пробел в начале строки |
| Краш при детонации C4 | Конфликт weapon limit (wS) + SMAC; по отдельности работали |
| Rename через admin menu | Краш — «особенность Orangebox»; старый basecommands или закомментировать 3 строки |

### Что релевантно нашему builder (6572)

| Находка | Статус у нас |
|---|---|
| Вырез OB-only cstrike natives | Частично через `#if SOURCE_ENGINE >= SE_ORANGEBOX && SOURCE_ENGINE != SE_CSS` в `apply-sourcemod.sh` |
| `GetWeaponPrice` / `GetTranslatedWeaponAlias` sigs | В `builder/assets/gamedata/.../game.cstrike.txt` — **проверить вручную** |
| sdktools vtable offsets (Linux 330/348/…) | Из upstream 6572; совпадают с FrozDark/MyArena 6522 — хороший знак для Linux |
| Windows vtable = Linux − 1 | Учитывать при верификации Windows gamedata |
| FrozDark `game.css.txt` (2015) | Исторический референс; наши sigs новее (6572), но offset/signature logic тот же |

Связанная тема (не прочитана — Cloudflare): `[CS:S v34] Сигнатуры функции` (FrozDark, апр 2015) — вероятно расширенный список sigs.
