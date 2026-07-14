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

Черновики апгрейдов (#6 = 1.12, #15 = 6588) остаются экспериментами поверх этой модели, а не поверх слоёв из #7.

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

## Связанные артефакты

| Что | Статус |
|-----|--------|
| [PR #7](https://github.com/fmu1337/sourcemod-css34/pull/7) | Развилка слоёв → этот документ; закрыть как superseded |
| [PR #10](https://github.com/fmu1337/sourcemod-css34/pull/10) | Dual-track 6572/6970 отвергнут; грабли сохранены в секции выше |
| `builder/patches/apply-sourcemod.sh` | Актуальный монолитный патчсет под golden 6572 |
| Тег `1.11.0.6572-mm1.10.7` | Текущий релизный pin SM+MM |
| Draft [#15](https://github.com/fmu1337/sourcemod-css34/pull/15) (6588), [#6](https://github.com/fmu1337/sourcemod-css34/pull/6) (1.12) | Живые эксперименты апгрейда поверх модели B |
