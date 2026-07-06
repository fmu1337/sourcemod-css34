# CS:S v34 — сравнение SourceMod v1.11.0.6572 и v1.12.0.7239

Документ описывает различия между двумя upstream-сборками SourceMod в контексте **единственной целевой игры — Counter-Strike: Source v34** (pre-Orange Box, Episode One SDK, `rom4s/hl2sdk-ep1c`).

## Версии и коммиты

| Параметр | v1.11.0.6572 (текущая) | v1.12.0.7239 (целевая) |
|---|---|---|
| `product.version` | `1.11.0` | `1.12.0` |
| Git commit | `832519ab647cdecb85763918dbfed1cb5e79c6cb` | `b951843d42f7b9204615c14885468ea131a24002` |
| Коммитов между версиями | — | **667** |
| Изменённых файлов (весь репозиторий) | — | **1152** (+128728 / −47874 строк) |
| Изменений в CS:S-релевантных путях | — | **144 файла** (+6440 / −2697 строк) |

## Что затронуто для CS:S v34 (общее)

Поскольку игра одна, ниже — только то, что реально влияет на v34-сервер, а не весь список движков (CS:GO, TF2, L4D2 и т.д.).

### 1. Система сборки (критично)

| Аспект | v1.11.0.6572 | v1.12.0.7239 |
|---|---|---|
| AMBuild | 1.x / ранний 2.x | **AMBuild 2.2+** (обязательно) |
| SDK-описания | Встроены в `AMBuildScript` | **`hl2sdk-manifests`** (JSON-манифесты) |
| Metamod:Source | `mmsource-1.10` | ожидается **`mmsource-1.12`** |
| Целевые архитектуры | x86 (v34) | по умолчанию x86 + x86_64; для v34 нужен `--targets=x86` |
| C++ стандарт | C++14/17 частично | **полный C++17**, GCC ≥ 9 / Clang ≥ 5 |

**Для v34 это главный риск:** текущие патчи `apply-sourcemod.sh` рассчитаны на старый `AMBuildScript` и **не применяются** к v1.12 без переработки.

### 2. Бинарники пакета (что должно получиться)

Текущий css34-пакет содержит:

```
addons/sourcemod/bin/sourcemod.1.ep1.{so,dll}
addons/sourcemod/bin/sourcemod.2.ep1.{so,dll}
addons/sourcemod/extensions/game.cstrike.ext.1.ep1.{so,dll}
addons/sourcemod/extensions/game.cstrike.ext.2.ep1.{so,dll}
addons/sourcemod/extensions/dbi.mysql.ext.{so,dll}
addons/sourcemod/extensions/dbi.sqlite.ext.{so,dll}
```

- **`1.ep1`** — сборка через `rom4s/hl2sdk-ep1c` с `SOURCE_ENGINE == SE_CSS` (код 6).
- **`2.ep1`** — сборка через `alliedmodders/hl2sdk` branch `episode1` с `SE_EPISODEONE`.

В upstream v1.12 расширение `cstrike` по умолчанию собирается только для SDK **`css`** и **`csgo`**, не для `episode1`. Для v34 нужен **дополнительный патч** `extensions/cstrike/AMBuilder`.

### 3. Ядро SourceMod (core)

Значимые изменения, затрагивающие v34 через css34-патчи:

| Область | Изменение в 1.12 | Влияние на v34 |
|---|---|---|
| `PlayerManager` | `OnClientLanguageChanged`, `OnServerEnter/ExitHibernation`, улучшенная логика языка | Новые forwards; плагины могут их использовать |
| `UserMessages` | рефакторинг, удаление protobuf-прокси из core для не-PB игр | Меньше кода в бинарнике ep1 |
| `smn_entities` | расширенная работа с entity props, lump API | Плагины с EntProp получают новые возможности |
| `HalfLife2` / `GameHooks` | рефакторинг, CDetour → safetyhook | Патчи `SE_CSS` нужно заново накладывать на новую структуру |
| `MenuStyle_*` | рефакторинг меню | Патчи `MIN()` уже есть в css34-билдере |
| Protobuf (`pb_*`) | вынесен/удалён из core для ep1 | **Не влияет** на v34 (PB только для CS:GO/Blade/MCV) |

### 4. Расширения

#### `game.cstrike` (cstrike.ext)

- В 1.12: `rulesfix.cpp` только для CS:GO (A2S_Rules) — **не нужен для v34**.
- Обновлены сигнатуры `CSWeaponDrop`, `HandleBuy` — в основном для CS:GO.
- `natives.cpp`: переход на `FindEntityServerClass` вместо прямого `GetNetworkable()` — **может затронуть v34**, если патч применён.
- Gamedata `game.css.txt` обновлён для Orange Box CSS (x64, новые оффсеты) — **для v34 не использовать напрямую**; css34-билдер подменяет на `builder/assets/gamedata/sm-cstrike.games/game.cstrike.txt`.

#### `sdktools`

Крупный рефакторинг (~30 файлов):

- Новые natives: `TE_WriteEnt`, `TE_ReadEnt`, `ForcePlayerSuicide` (explode), trace types.
- `vhelpers` / `vnatives`: reconciled Edict & Networkable (#1903).
- `hooks.cpp`: CDetour → safetyhook.
- EmitSound, tempents, voice — расширения API.

Для v34 все `#if SOURCE_ENGINE >= SE_ORANGEBOX` и `SE_EYE` патчи из `apply-sourcemod.sh` **нужно перенакладывать** на новые файлы.

#### `sdkhooks`

- `takedamageinfohack` — изменения для Orange Box; css34-патчи исключают `SE_CSS`.
- Новые хуки и safetyhook-интеграция.

### 5. SourcePawn / плагины

- Обновлён SourcePawn (несколько раз между 1.11 и 1.12).
- Новые API: 2D array access, `ParseTime`/`strptime`, `PluginIterator`, `OnPlayerRunCmdPre`.
- `newdecls`/`olddecls` — часть forwards переведена на `newdecls`.
- **Плагины**, скомпилированные под 1.11, как правило **работают** на 1.12 (обратная совместимость include), но плагины с `newdecls` могут не скомпилироваться на 1.11.

### 6. Gamedata

Upstream 1.12 обновляет `game.css.txt` для **Steam CSS (Orange Box)** с x64-оффсетами. Для v34:

- Используется **кастомный** `game.cstrike.txt` из `builder/assets/`.
- Gamedata обрезается до ep1/cstrike-набора в `prepare-package.sh`.
- Прямое копирование upstream gamedata **сломает** natives cstrike на v34.

### 7. Переводы и конфиги

- Новые языки (в т.ч. `zho`).
- `core.cfg`: `DisableAutoUpdate` → `yes` (уже делается в css34 `prepare-package.sh`).

## Сводка: что реально меняется для администратора v34-сервера

| Категория | Меняется? | Комментарий |
|---|---|---|
| Бинарники `.so`/`.dll` | Да | Полная пересборка |
| Gamedata cstrike | Нет* | *Остаётся кастомный v34-набор |
| Metamod:Source | Возможно | Рекомендуется 1.12 MMS с SM 1.12 |
| Совместимость плагинов .smx | Высокая | SM 1.12 обратно совместим |
| Перекомпиляция .sp | Опционально | Для новых API 1.12 |
| MySQL/SQLite ext | Да | Пересобираются |
| Структура каталогов | Нет | Тот же layout `addons/sourcemod/` |

## Риски обновления

### Высокий риск

1. **Патчи сборки не переносятся автоматически** — `apply-sourcemod.sh` падает на v1.12 с `Failed to locate episode1 SDK anchor in AMBuildScript`.
2. **AMBuild 2.2** — текущий `checkout-deps.sh` ставит AMBuild 2.0, v1.12 требует 2.2+.
3. **cstrike.ext для episode1** — upstream 1.12 не собирает расширение для ep1 SDK; без патча не будет `game.cstrike.ext.*.ep1.*`.
4. **Регрессии в natives** — изменения в sdktools/sdkhooks/cstrike могут сломать плагины, использующие EntProp, TempEnts, SDKHooks.

### Средний риск

5. **Metamod:Source 1.10 → 1.12** — возможны несовместимости с v34 Metamod (нужно проверить на реальном сервере).
6. **Gamedata** — при ошибке упаковки может попасть Orange Box gamedata вместо v34.
7. **SourcePawn JIT** — обновления VM; редкие edge-case с плагинами.

### Низкий риск

8. Новые forwards (`OnServerHibernation*`, `OnClientLanguageChanged`) — opt-in для плагинов.
9. Переводы — косметика.
10. CS:GO/TF2-специфичный код — не компилируется для ep1 SDK.

## Результат пробной сборки v1.12 (ветка `cursor/upgrade-sourcemod-1.12-5b81`)

Сборка **успешно завершена** после адаптации патчей:

```
packages/sourcemod-1.12.0-git7239-css34-linux.tar.gz
```

Содержимое (ключевые файлы):

- `addons/sourcemod/bin/sourcemod.1.ep1.so`
- `addons/sourcemod/bin/sourcemod.2.ep1.so`
- `addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so`
- `addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so`
- `addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt` (кастомный v34)

### Что потребовалось для сборки 1.12

1. AMBuild 2.2 вместо 2.0
2. Новый `apply-sourcemod-v112.sh` + общий `apply-sourcemod-common.sh`
3. Манифест `ep1.json` для `rom4s/hl2sdk-ep1c`
4. Патч `cstrike/AMBuilder` для `ep1` + `episode1`
5. Дополнительные флаги gcc для SDK ep1c (reorder, stringop-*, sign-compare)
6. Исправления libcurl, SourcePawn, `clamp` macro в SDK
7. Заглушки `SOURCE_ENGINE_PVKII` / `SOURCE_ENGINE_MCV` (несовпадение SM 1.12 и MMS 1.12 headers)

### Остаётся проверить на реальном сервере

- Загрузка Metamod + SourceMod на v34 dedicated
- Smoke-тест natives cstrike/sdktools/sdkhooks
- Совместимость существующих `.smx` плагинов

## Рекомендация

| Сценарий | Рекомендация |
|---|---|
| Продакшн v34-сервер стабилен | **Оставаться на 1.11.0.6572** до завершения адаптации |
| Нужны фиксы/фичи 1.12 | Обновляться через ветку `cursor/upgrade-sourcemod-1.12-5b81` после успешного CI |
| Новые плагины с 1.12 API | Планировать миграцию; тестировать на staging |

## Ссылки

- Текущий css34-релиз: [v1.11.0.6572](https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572)
- Upstream SM 1.12: [1.12.0.7239](https://github.com/alliedmodders/sourcemod/releases/tag/1.12.0.7239)
- Changelog 1.11→1.12: `git log 832519ab..b951843d` в `alliedmodders/sourcemod`
