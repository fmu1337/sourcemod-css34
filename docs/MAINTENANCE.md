# Стратегия поддержки sourcemod-css34

CS:S v34 официально не поддерживается Valve и AlliedModders уже много лет. Этот репозиторий — **продолжение наработок [rom4s](https://github.com/rom4s/sourcemod-css34)**: последний рабочий upstream-билд, который он собирал, — **v1.11.0.6572**.

Цель проекта:

1. **Воспроизвести** тот же билд 6572 (layout, бинарники, gamedata v34).
2. **Проверить** его автоматически при каждом изменении.
3. **Натягивать** новые версии SourceMod **поверх** v34-фиксов, не ломая то, что уже работало.

## Три слоя

```
┌─────────────────────────────────────────┐
│  Upstream SourceMod (alliedmodders)     │  ← меняется: 6572 → 7239 → …
├─────────────────────────────────────────┤
│  CSS34 / rom4s fixes (apply-*-common)   │  ← НЕ ТРОГАТЬ без веской причины
├─────────────────────────────────────────┤
│  Version-specific patches (v111 / v112) │  ← только под новый AMBuild/SDK
└─────────────────────────────────────────┘
```

### Слой 1 — upstream

Пин коммита через переменные окружения:

| Переменная | Базовый билд (master) | Эксперимент 1.12 |
|---|---|---|
| `SOURCEMOD_COMMIT` | `832519ab…` | `b951843d…` |
| `SOURCEMOD_GIT_REV` | `6572` | `7239` |
| `SOURCEMOD_MAJOR` | `11` | `12` |

### Слой 2 — rom4s / v34 fixes (`apply-sourcemod-common.sh`)

Общие патчи для **любой** версии SM:

- pre-Orange Box: `SE_CSS` без Orange Box / SE_EYE API
- `rom4s/hl2sdk-ep1c` + `episode1` SDK
- `PlayerManager`, `HalfLife2`, sdktools, sdkhooks, cstrike
- кастомный gamedata в `builder/assets/gamedata/`
- упаковка: strip, `DisableAutoUpdate`, обрезка gamedata

**Правило:** изменения здесь — только если чинят v34 на всех поддерживаемых версиях SM. Не смешивать с «удобствами для одной версии».

### Слой 3 — version-specific

| Скрипт | Когда |
|---|---|
| `apply-sourcemod.sh` (v1.11 path) | AMBuild 1.x, inline `AMBuildScript`, ep1 SDK в скрипте |
| `apply-sourcemod-v112.sh` | AMBuild 2.2+, `hl2sdk-manifests`, MMS 1.12 |

Роутер в `apply-sourcemod.sh` смотрит на `product.version` и выбирает путь.

## Ветки

| Ветка | Назначение |
|---|---|
| `master` | **Золотой билд** v1.11.0.6572 — то, что должно совпадать с rom4s |
| `cursor/upgrade-sourcemod-1.12-5b81` | Эксперимент: 1.12.0.7239 поверх тех же v34-фиксов |
| `cursor/v34-version-comparison-5b81` | Документация отличий версий |

Новые upstream-версии — **отдельные ветки** `cursor/upgrade-sourcemod-X.Y-5b81`. В `master` мержить только после проверки на v34-сервере.

## Проверка билда

### Автоматически (CI + локально)

```bash
builder/verify-package.sh packages/sourcemod-*-css34-linux.tar.gz
```

Скрипт проверяет наличие обязательных файлов из оригинального layout rom4s.

### Полная сборка базового билда

```bash
git submodule update --init --recursive
builder/run/linux.sh
builder/verify-package.sh packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz
```

### Эксперимент с новой версией SM

```bash
SOURCEMOD_COMMIT=b951843d42f7b9204615c14885468ea131a24002 \
SOURCEMOD_GIT_REV=7239 \
SOURCEMOD_MAJOR=12 \
builder/run/linux.sh
```

Если сборка падает — чинить **только** `apply-sourcemod-v112.sh` (или добавить `v113.sh`), **не** переписывать `common`.

## Чеклист перед мержем апдейта в master

- [ ] `builder/run/linux.sh` на 6572 всё ещё проходит (регрессия)
- [ ] `verify-package.sh` OK для нового архива
- [ ] Gamedata v34 не заменён upstream Orange Box `game.css.txt`
- [ ] На реальном v34 dedicated: Metamod грузит SM, `sm version`, cstrike natives
- [ ] Существующие `.smx` плагины стартуют без ошибок

## Риски «натягивания» апдейтов

| Риск | Митигация |
|---|---|
| Сломать common-патчи при рефакторинге | Держать common отдельно; 6572 в CI всегда |
| Upstream меняет AMBuild / SDK layout | Version-specific скрипт на ветке |
| Новый gamedata перетирает v34 offsets | `prepare-package.sh` + assets в репо |
| MMS несовместим с v34 | Пока MMS 1.10 для 6572; 1.12 — только на upgrade-ветке |

## Ссылки

- Оригинал rom4s: https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572
- Сравнение 1.11 vs 1.12: [V34_COMPARISON_v1.11.6572_vs_v1.12.7239.md](V34_COMPARISON_v1.11.6572_vs_v1.12.7239.md)
