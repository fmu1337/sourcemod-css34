# CS:S v34 - сравнение SourceMod v1.11.0.6572 и v1.12.0.7239

Документ описывает различия между двумя upstream-сборками SourceMod в контексте **единственной целевой игры - Counter-Strike: Source v34** (pre-Orange Box, Episode One SDK).

Перенесено из обсуждения PR #6; актуальная реализация апгрейда - **PR #23** (`cursor/upgrade-sm-1.12-7239-5b81`).

## Версии и коммиты

| Параметр | v1.11.0.6572 (продакшн / master) | v1.12.0.7239 (цель PR #23) |
|---|---|---|
| `product.version` | `1.11.0` | `1.12.0` |
| Git commit | `832519ab647cdecb85763918dbfed1cb5e79c6cb` | `b951843d42f7b9204615c14885468ea131a24002` |
| Metamod:Source | **1.10.7** (`metamod.1.ep1`) | **1.12-dev** (`364cb6c…`, `metamod.2.ep1`) |
| Коммитов между SM-версиями | - | **667** |
| Изменённых файлов (весь репозиторий SM) | - | **1152** (+128728 / -47874 строк) |

## Стратегия пары SM + MM для v34

| | Golden (master) | PR #23 |
|---|---|---|
| SourceMod core | `sourcemod.1.ep1.so` (+ dual `2.ep1` в legacy layout) | **`sourcemod.2.ep1.so`** only |
| Metamod | MM 1.10 / PLAPI 11 / SourceHook v4 / `metamod.1.ep1` | MM 1.12 / PLAPI 16 / modern Core / `metamod.2.ep1` |
| Патчи SM | `apply-sourcemod.sh` | `apply-sourcemod-v112.sh` |
| Патчи MM | `apply-mmsource-css34.sh` (legacy transplant) | `apply-mmsource-v112.sh` (light) |
| Splice rom4s `logic.so` | auto при CXX11/libstdc++ | **запрещён** (1.11 logic нельзя класть в пакет 1.12) |

SM 1.12 ожидает современный Metamod (PLAPI 16, `META_NO_HL2SDK`). Держать SM 1.12 на MM 1.10/`1.ep1` нецелесообразно: для v34 апгрейд MM до 1.12 - часть той же миграции.

## Что затронуто для CS:S v34

### 1. Система сборки (критично)

| Аспект | v1.11.0.6572 | v1.12.0.7239 |
|---|---|---|
| AMBuild | 2.0-era | **AMBuild 2.2+** |
| SDK-описания | Встроены в `AMBuildScript` | **`hl2sdk-manifests`** (JSON) |
| SDK для v34 | `rom4s/hl2sdk-ep1c` как `ep1` + episode1 | **`alliedmodders/hl2sdk` episode1** (`--sdks=episode1`) |
| Архитектура | x86 | `--targets=x86` |
| C++ | C++14/17 частично | **C++17**, GCC >= 9 |

Патчи `apply-sourcemod.sh` (1.11) **не** накладываются на дерево 1.12 - для этого есть `apply-sourcemod-v112.sh`.

### 2. Бинарники пакета

**Golden 1.11** (dual layout):

```
addons/sourcemod/bin/sourcemod.1.ep1.so
addons/sourcemod/bin/sourcemod.2.ep1.so
addons/metamod/bin/metamod.1.ep1.so
```

**PR #23 / 1.12** (современный путь):

```
addons/sourcemod/bin/sourcemod.2.ep1.so
addons/sourcemod/bin/sourcemod.logic.so          # in-tree, не rom4s-splice
addons/sourcemod/bin/sourcepawn.jit.x86.so      # libsourcepawn, pthread/rt NEEDED
addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so
addons/metamod/bin/metamod.2.ep1.so
```

В upstream 1.12 `cstrike` по умолчанию только для `css`/`csgo`; css34 добавляет **`episode1`** в `extensions/cstrike/AMBuilder`.

### 3. Ядро SourceMod (core)

| Область | Изменение в 1.12 | Влияние на v34 |
|---|---|---|
| `PlayerManager` | language / hibernation forwards | Новые forwards для плагинов |
| `UserMessages` | рефакторинг, без PB-прокси в core для non-PB | Меньше кода в ep1-бинарнике |
| `smn_entities` / lump API | расширение EntProp | Новые возможности плагинов |
| `HalfLife2` / `GameHooks` | CDetour -> safetyhook | Патчи поверх новой структуры |
| `MenuStyle_*` | рефакторинг | `MIN()` уже чинится в билдере |
| Protobuf | не для ep1 | Не влияет на v34 |

### 4. Расширения

#### `game.cstrike`

- `rulesfix.cpp` - CS:GO only, не нужен для v34.
- Сигнатуры `CSWeaponDrop` / `HandleBuy` - в основном CS:GO.
- `natives.cpp`: `FindDataMapInfo` вместо incomplete EP1 `FindInDataMap` (патч в v112).
- Gamedata: для v34 - `builder/assets/gamedata/...`, не upstream `game.css.txt`.

#### `sdktools` / `sdkhooks`

Крупный рефакторинг (safetyhook, новые natives TE_*, voice, traces). На v34 критичны gamedata ep1 и корректный `SE_EPISODEONE` path.

### 5. SourcePawn

- Обновлённый SP между 1.11 и 1.12; `libsourcepawn.so` пакуется как `sourcepawn.jit.x86.so`.
- На glibc < 2.34 нужны явные `DT_NEEDED` на `libpthread`/`librt` (Debian 11).
- Плагины 1.11 обычно грузятся на 1.12; обратная компиляция `newdecls`-плагинов на 1.11 может не пройти.

### 6. Gamedata

Upstream 1.12 тянет Orange Box / x64 CSS offsets. Для v34:

- Кастомный `game.cstrike.txt` из `builder/assets/`.
- `prepare-package.sh` обрезает набор до ep1/cstrike.
- Прямое копирование upstream gamedata сломает natives на v34.

### 7. logic.so ABI (критичный для smoke)

`sourcemod.logic.so` должен:

- собираться с `_GLIBCXX_USE_CXX11_ABI=0` + sysroot gcc-4.9 (`SM_LOGIC_CXX_SYSROOT`);
- не экспортировать `__cxx11` symbols;
- не `DT_NEEDED` `libstdc++.so.6` (static embed);
- иметь `libpthread`/`librt` в `DT_NEEDED`.

Для 1.12 **нельзя** подменять logic бинарником rom4s 1.11 (`splice-reference-logic.sh` пропускается при `SOURCEMOD_MAJOR>=12`).

## Что потребовалось для сборки 1.12 (PR #23)

1. AMBuild 2.2 + `hl2sdk-manifests`
2. `apply-sourcemod-v112.sh` / `apply-mmsource-v112.sh`
3. `--sdks=episode1`, бинарники `*.2.ep1`
4. MM 1.12 pin (`364cb6c…`) вместо dual MM 1.10 + SM 1.12
5. logic: g++-9 + gcc-4.9 sysroot, без rom4s-splice
6. `libsourcepawn` / ExtLibrary: `--no-as-needed -lpthread -lrt`
7. Windows: только ASCII в генерируемых комментариях патчей (cp1252)
8. MM ConVar link order: `tier1` before `vstdlib` (иначе сломанные FindVar)
9. `blacklist.plugins.txt` в пакете; full Built-from SHAs в `generate_headers`

## Критический runtime-баг (smoke SIGSEGV) и фикс

**Симптом:** после `Network:` — `srcds exited before map de_dust2 loaded`. SIGSEGV в `vstdlib` `ConCommandBase::FindCommand` ← `CCvar::FindVar("sv_logecho")`.

**Bisect:** MM 1.12 alone OK; MM 1.12 + rom4s SM 1.11 OK; MM 1.12 + наш SM 1.12 — crash.

**Причина:** `GameConfigManager::CacheGameBinaryInfo` делал `dlopen(…/engine_i486.so, RTLD_NOW)`, пока srcds уже держал `engine_i686.so`. Временная копия engine регистрировала ConVar static ctors в общий `s_pConCommandBases`; после `dlclose` головы списка оставались dangling → crash при первом FindVar.

**Фикс (в `apply-sourcemod-v112.sh`):** `RTLD_NOW | RTLD_NOLOAD` + sibling `_i686`/`_i486`; то же для `@`-symbol path. Вторая копия engine для `CreateInterface` не грузится.

## CI статус (после фикса)

Все checks PR #23 зелёные: Build linux/windows, `check-built-package`, `test-built-smoke`, debian 11/12/13/latest, rocky9.

## Опционально перед merge

- Live CSS34 dedicated вне CI (если нужен ручной sanity)
- Совместимость прод-плагинов `.smx` на реальной карте
- В логах может мелькать `utlmemory.h IsIdxValid` assertion — smoke не валит

## Рекомендация

| Сценарий | Рекомендация |
|---|---|
| Продакшн v34 | Пока стабилен на **1.11.0.6572 + MM 1.10.7**; апгрейд — через merge **PR #23** |
| Нужны фичи/фиксы 1.12 | **PR #23** готов по CI smoke; merge после вашего live-check (если нужен) |
| Закрытие #6 | #6 supersed'ится #23 (этот документ перенесён сюда) |
| SM 1.13 | Не начинать до merge #23 (см. docs / PR #29) |

## Ссылки

- PR #23: https://github.com/fmu1337/sourcemod-css34/pull/23
- Golden css34-релиз: [v1.11.0.6572](https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572)
- Upstream SM 1.12: [1.12.0.7239](https://github.com/alliedmodders/sourcemod/releases/tag/1.12.0.7239)
- Changelog 1.11->1.12: `git log 832519ab..b951843d` в `alliedmodders/sourcemod`
