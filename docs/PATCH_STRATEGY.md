# Стратегия патчей css34 (решённая развилка)

Документ фиксирует обсуждение вокруг [PR #7](https://github.com/fmu1337/sourcemod-css34/pull/7)
(«золотой билд 6572 + слоистые патчи») и выбор, на котором остановились.

## Контекст

Upstream SourceMod официально не поддерживает CS:S v34.
Сборка в этом репозитории всегда делает одно и то же:

1. Чекаутит pinned upstream (сейчас **1.11.0.6572**).
2. Прогоняет патчи из `builder/patches/` (в первую очередь `apply-sourcemod.sh`).
3. Собирает пакет и гоняет smoke / ABI-чеки.

Вопрос был не «патчить или нет», а **как устроить патчи, если завтра понадобится другая версия SM**.

## Две развилки

### A. Слоистая архитектура (идея #7)

Разделить патчи на три слоя:

| Слой | Смысл |
|------|--------|
| **common** (`apply-sourcemod-common.sh`) | Вечные v34/rom4s фиксы (pre-OB `SE_CSS`, ep1 SDK, gamedata) — «не трогать при апдейтах» |
| **v1.11** | AMBuild 1.x / inline SDK под текущий golden |
| **v1.12+** (`apply-sourcemod-v112.sh`) | AMBuild 2.2, `hl2sdk-manifests`, MMS 1.12 |

Роутер смотрит на `product.version` и выбирает version-specific слой.
Несколько версий SM могут жить в **одной** кодовой базе патчей; апгрейд = тонкий version-specific слой поверх common.

**Зачем это задумывалось:** параллельно держать golden 6572 и эксперимент 1.12/mid без copy-paste common-фиксов; «не сломать 6572 костылём под AMBuild 2.2».

### B. Один патчсет под текущий pin (как master сейчас)

Всё v34- и version-specific живёт в актуальных скриптах builder’а под **одну** поддерживаемую версию.
Следующий SM:

1. Ветка от `master`.
2. Новый `SOURCEMOD_COMMIT` / `SOURCEMOD_GIT_REV`.
3. Дописываем / правим существующие `apply-*.sh`, пока CI не зелёный.
4. Мержим, когда smoke на v34 ок.

Несколько версий в CI из одних и тех же слоёв **не** предполагаются.

## Решение

**Выбран вариант B** (последовательные апгрейды, один патчсет).

Почему слои (#7) сейчас не окупаются:

- Любая версия SM всё равно патчится builder’ом — слои не добавляют нового механизма, только организацию файлов.
- «Common» на практике не вечный: при скачке major/mid upstream часто двигает те же куски (AMBuild, SourceHook, extensions), и фикс всё равно правится руками.
- Поддерживаем **один** production pin (`1.11.0.6572` + свой MM); параллельный multi-version CI не ведём.
- Стоимость слоёв: каждый фикс — решение «в какой слой», риск рассинхрона common с реальным `apply-sourcemod.sh`.

Итог: идея #7 полезна как **справка**, но не как обязательная архитектура master.
Слои можно вернуться, если появятся **одновременно** две поддерживаемые версии SM в одном дереве (два pin’а в CI).

## Что делать при апгрейде SM

1. Ветка `cursor/upgrade-sourcemod-<ver>-…` от актуального `master`.
2. Сменить pin и прогнать `builder/run/linux.sh` + `test-built-smoke`.
3. Править патчи **in place** (тот же `apply-sourcemod.sh` и соседние `builder/patches/*`).
4. Не заводить отдельный `apply-sourcemod-common.sh`, пока не понадобится параллельная сборка двух версий.

Черновики апгрейдов (#6 = 1.12) — отдельные эксперименты поверх этой модели, а не поверх слоёв из #7.

Рекомендуемый порядок пробных апгрейдов: **6572 → 6588 (mid) → 6970+**, а не сразу к 6970.

## Mid-шаг 6588 (из PR #15)

[PR #15](https://github.com/fmu1337/sourcemod-css34/pull/15) натягивал тот же css34-патчсет на **6588** (`SOURCEMOD_PROFILE=mid`) как ступеньку между rom4s 6572 и experimental 6970.
Профильную схему / dual-CI **не берём** (модель B). Ниже — pin и грабли fetch/headers/AMBuild, плюс заявленный smoke.

### Испробованный pin

| | |
|--|--|
| Rev | **6588** (Jul 2020) |
| Commit | `4a4b9ce7f0c9f93a8380e680420900cd0c39dde9` |
| Статус по отчёту #15 | `sourcemod-1.11.0-git6588-css34-linux.tar.gz` — **smoke PASS** (17 plugins); 6572 на той же ветке тоже PASS |

Имеет смысл пробовать **6588 раньше 6970**: маленький шаг над golden, без пакета проблем ≥6800 / DHooks.

### Fetch / checkout

| Симптом | Что делать |
|---------|------------|
| Shallow `git fetch` только mid-пина | Дерево **отрывается** от истории 6572 (не тот source tree) |
| Проверка | Pin должен быть предком/потомком stable: `merge-base --is-ancestor <stable> HEAD` |
| Depth | Считать depth от delta `(mid_rev − 6572) + запас`, иначе deepen / unshallow |

На master для 6572 уже `fetch --depth=8192`. При смене pin на mid/дальше — явно заложить ancestry, не полагаться на «достал один SHA».

### Headers / build id

| Симптом | Фикс |
|---------|------|
| `generate_headers.py` считает rev через `git rev-list --count` | На shallow/неполной истории число врёт (например 286 вместо 6588) |
| Правильно | Явно задавать `SOURCEMOD_GIT_REV=6588` (и pin) при сборке / packaging |

### AMBuild (эпоха mid / 2.1)

Относительно 6572 на 6588 ловили отличия в logic `AMBuilder` (**postlink**) и в `configure_linux`, когда нет `cxx.target`.
При апгрейде ждать правки линкерных блоков in place в `apply-sourcemod.sh`, а не отдельный «слой mid».

### Что из root causes #15 уже в master (не повторять)

- Static **tier1 в core** (ConVar / hang до mapchange) — уже в патчах 6572.
- Logic **sysroot**, Logger/boot-trace, smoke — уже в master.
- **bintools**: в #15 был rom4s splice; в master — **in-tree** (#16). На mid-апгрейде не возвращать splice без причины.

### Как НЕ делать (отвергнуто вместе с #15)

- Держать `SOURCEMOD_PROFILE=mid|stable|experimental` и параллельные CI jobs в master.
- Rebase’ить всю старую ветку #15 на нынешний master «как есть» (за ней стек #10 + устаревший smoke).

## Грабли апгрейда ≥6800 / pin 6970 (из PR #10)

[PR #10](https://github.com/fmu1337/sourcemod-css34/pull/10) пробовал dual-track (**stable 6572** + **experimental 6970**) и оверлеи API/toolchain.
Саму архитектуру dual-CI **не берём** (см. решение B выше). Ниже — только фактура, на которую натыкались при прыжке к 6970; при следующем mid-апгрейде сверяться с этим чек-листом.

### Испробованный pin

| | |
|--|--|
| Rev | **6970** |
| Commit | `f53cb134ef83b580c83e1f4bf35f60d11c4571dd` |
| Статус | Сборка **не довели** дозеленого (DHooks / udis86); notes ниже всё равно полезны |

Ориентир «ждали сюрпризы»: upstream **≥ ~6800**.

### API / includes

| Симптом | Фикс, который пробовали |
|---------|-------------------------|
| `CS_OnCSWeaponDrop` — старые плагины без `donated` | В `cstrike.inc`: `bool donated=false` в forward |
| `SetCollisionGroup` убрали / переименовали | Deprecated `stock SetCollisionGroup` → `SetEntityCollisionGroup` в `sdktools_functions.inc` |

### Toolchain (gcc-9 multilib)

| Симптом | Фикс |
|---------|------|
| SourcePawn / AMBuild шумит на gcc-9 | `-Wno-sign-compare`, `-Wno-ignored-attributes` |
| Bundled DHooks: `-Wno-invalid-offsetof` на **C**-файлах | Флаг только в **cxxflags**, не в `cflags` |

### Упаковка / зависимости

| Тема | Заметка |
|------|---------|
| GeoIP | На более новом SM может понадобиться `GeoLite2-Country.mmdb` при packaging (в #10 — `download-geolite2.sh` с P3TERX mirror) |
| DHooks | Конфликт **bundled vs standalone** на 6970 — открытый риск, в том PR не закрыт |

### Как НЕ делать (отвергнуто вместе с #10)

- Параллельные CI jobs `linux-stable` + `linux-experimental` в одном workflow.
- Отдельные `apply-api-compat.sh` / `apply-toolchain.sh` как постоянный «слой ≥6800» в master.
- При апгрейде — править текущий `apply-sourcemod.sh` (и соседние патчи) **in place** на ветке апгрейда.

## Сравнение пакетов MM/SM и myarena (из PR #17)

[PR #17](https://github.com/fmu1337/sourcemod-css34/pull/17) добавил tooling для built Metamod + binary compare + smoke matrix vs rom4s/myarena.
**Код уже в master** (через [#19](https://github.com/fmu1337/sourcemod-css34/pull/19) / коммит `29c5d88`: `compare-binaries.sh`, `install-built-metamod.sh`, `install-sourcemod-package.sh`, `run-built-mm-matrix.sh`). Сам draft #17 мержить не нужно — закрыть как landed.

Ниже — совместимость, которую выявили прогоны; CI сейчас дымит **только наш** MM 1.10.7 + SM 6572, но локально matrix всё ещё полезен.

### Что проходило / не проходило

| Пара | Smoke |
|------|--------|
| **Built MM 1.10.7** + **rom4s SM 6572** | **PASS** |
| **Built MM 1.10.x** + **myarena SM 6522** | **FAIL** (ожидаемо) |
| **myarena MM 1.11** + **rom4s SM 6572** | **PASS** (на том же srcds) |

### Почему myarena SM ломается на нашем MM 1.10

| Ожидание MM 1.10 / rom4s layout | myarena 6522 / MM 1.11 bundle |
|--------------------------------|-------------------------------|
| Core **`sourcemod.1.ep1.so`** (+ часто `2.ep1`) | Только **`sourcemod.2.ep1.so`** (нет `1.ep1`) |
| Bridge `sourcemod_mm_i486.so`: **`CreateInterface` + `CreateInterface_MMS`** | Только **`CreateInterface_MMS`** |
| MM load: `metamod.1.ep1.so` | Bundle: **`metamod.2.ep1.so`**, MM **1.11** |

Итог: myarena-SM заточен под **Metamod 1.11 / 2.ep1 path**. Наш/rom4s путь — **MM 1.10 + CreateInterface + 1.ep1**. Смешивать built/rom4s MM 1.10 с myarena SM не надо.

Доп. наблюдение из compare: `myarena sourcemod.logic.so` + rom4s `sourcemod.1.ep1.so` → hang до mapchange (не наш текущий CI-путь, но ловушка при ручных миксах).

### Ориентиры размеров (на момент #17)

| Бинарник | Заметка |
|----------|---------|
| rom4s MM 1.10.6 | ~214 KB, stripped, старый GLIBC |
| Built MM 1.10.7-dev | крупнее (debug symbols), GLIBC хозяина/контейнера |
| myarena MM 1.11 | `metamod.2.ep1.so` only |

Актуальные наши артефакты — тег `1.11.0.6572-mm1.10.7` (in-tree SM+MM), не myarena.

### Field blockers: SDKHooks EP1 + PLAPI 11 vs MM 1.11 (2026-07-15)

На живом CSS:S v34 (Oracle/SCI, backup 2021-07-05 vs tag `1.11.0.6572-mm1.10.7`)
зафиксированы **два** release blocker’а — полный разбор в
[SDKHOOKS_EP1_RELEASE_BLOCKERS.md](SDKHOOKS_EP1_RELEASE_BLOCKERS.md):

1. **SDKHooks** `Failed to setup entity listeners` / SDKTools `gEntList` — когда
   SM 6572 реально загружен (отдельно от vtable overlay в [#34](https://github.com/fmu1337/sourcemod-css34/pull/34)).
2. **`11 < 14`** — release SM/exts намеренно PLAPI **11** (`apply-mmsource-css34.sh`);
   leftover / myarena **`metamod.2.ep1.so` (`1.11.0-dev+1130`, iface min 14)** режет
   чистый install до entity-listener path. С матчить только MM **1.10.x /
   `metamod.1.ep1` / `1.10.7-dev`**.

### Скрипты на master

```bash
# NEEDED / GLIBC / CreateInterface / strings
bash testing/scripts/compare-binaries.sh

# Local matrix (built MM + rom4s SM; myarena optional, failure expected on MM 1.10)
sudo bash testing/scripts/run-built-mm-matrix.sh
# SKIP_MYARENA_SMOKE=1 — пропустить myarena-кейс
```

## Связанные артефакты

| Что | Статус |
|-----|--------|
| [PR #7](https://github.com/fmu1337/sourcemod-css34/pull/7) | Развилка слоёв → этот документ; закрыть как superseded |
| [PR #10](https://github.com/fmu1337/sourcemod-css34/pull/10) | Dual-track 6572/6970 отвергнут; грабли ≥6800 сохранены выше |
| [PR #15](https://github.com/fmu1337/sourcemod-css34/pull/15) | Mid 6588 отвергнут как merge; pin/ancestry/headers сохранены в секции «Mid-шаг 6588» |
| [PR #17](https://github.com/fmu1337/sourcemod-css34/pull/17) | Tooling landed via #19; myarena/MM compatibility notes выше |
| Field report 2026-07-15 | SDKHooks `gEntList` + MM PLAPI 11 vs 1.11 mix — [SDKHOOKS_EP1_RELEASE_BLOCKERS.md](SDKHOOKS_EP1_RELEASE_BLOCKERS.md); sdkhooks vtables → #34 |
| [PR #4](https://github.com/fmu1337/sourcemod-css34/pull/4), [PR #9](https://github.com/fmu1337/sourcemod-css34/pull/9) | Byte-identical vs rom4s — **не преследуем**; вердикт в [BYTE_MATCH.md](BYTE_MATCH.md) |
| `builder/patches/apply-sourcemod.sh` | Актуальный монолитный патчсет под golden 6572 |
| Тег `1.11.0.6572-mm1.10.7` | Текущий релизный pin SM+MM |
| Draft [#6](https://github.com/fmu1337/sourcemod-css34/pull/6) (1.12) | Эксперимент major-апгрейда поверх модели B |
