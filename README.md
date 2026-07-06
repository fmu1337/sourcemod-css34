# sourcemod-css34

Patched [SourceMod](https://www.sourcemod.net/) builds for **Counter-Strike: Source v34** (non-Steam / legacy builds).

Продолжение наработок [rom4s/sourcemod-css34](https://github.com/rom4s/sourcemod-css34): последний рабочий релиз rom4s — **v1.11.0.6572** (июнь 2020). Этот репозиторий воспроизводит тот билд и даёт способ аккуратно натягивать более новый upstream, не ломая v34-фиксы.

## Модель поддержки

```
upstream SourceMod (submodule)
        ↓
apply-sourcemod.sh     ← rom4s/v34 фиксы (всегда)
        ↓
apply-upstream-patches ← API + toolchain (только для новых билдов)
        ↓
prepare-package.sh     ← gamedata v34, GeoIP, переводы
        ↓
sourcemod-1.11.0-gitXXXX-css34-*
```

| Слой | Файл | Когда |
|------|------|-------|
| **v34 / rom4s** | `builder/patches/apply-sourcemod.sh` | Всегда: ep1 SDK, SE_CSS guards, cstrike ext, tier0_i486 |
| **API compat** | `builder/patches/apply-api-compat.sh` | upstream ≥ 6800: `CS_OnCSWeaponDrop` default, `SetCollisionGroup` wrapper |
| **Toolchain** | `builder/patches/apply-toolchain.sh` | upstream ≥ 6800: gcc-9 флаги для SourcePawn/DHooks |
| **Packaging** | `builder/prepare-package.sh` | Обрезка gamedata, GeoLite2 `.mmdb`, `DisableAutoUpdate` |

### Профили сборки

| Профиль | Коммит | Rev | Назначение |
|---------|--------|-----|------------|
| **stable** (по умолчанию) | `832519ab` | **6572** | База rom4s, проверенный билд |
| **experimental** | `f53cb134e` | **6970** | Тест апгрейда upstream |

```bash
# Стабильный билд (как rom4s 6572)
builder/run/linux.sh

# Экспериментальный апгрейд
SOURCEMOD_PROFILE=experimental builder/run/linux.sh

# Явный пин
SOURCEMOD_COMMIT=832519ab647cdecb85763918dbfed1cb5e79c6cb SOURCEMOD_GIT_REV=6572 builder/run/linux.sh
```

Пины заданы в `builder/versions.env`.

## Сборка (Linux)

```bash
git submodule update --init --recursive
chmod +x builder/run/linux.sh builder/checkout-deps.sh builder/package.sh \
  builder/prepare-package.sh builder/download-geolite2.sh builder/resolve-version.sh \
  builder/apply-upstream-patches.sh builder/patches/*.sh
builder/run/linux.sh
```

Результат: `packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz`

Сборка на **gcc-9 multilib**, Ubuntu 22.04. Бинарники strip, gamedata обрезан под v34.

## Сборка (Windows)

Visual Studio Build Tools (x86), Python 3, Git Bash:

```bash
builder/run/windows.sh
```

## CI

- **linux-stable** — обязательный, профиль `stable` (6572)
- **linux-experimental** — опциональный, профиль `experimental` (6970), `continue-on-error`
- **windows** — stable

## Установка

Распаковать в `cstrike` (нужен Metamod:Source):

```bash
tar -xzf sourcemod-1.11.0-git6572-css34-linux.tar.gz -C /path/to/cstrike
```

## Апгрейд upstream (как натягивать новые билды)

1. Обновить `SOURCEMOD_EXPERIMENTAL_*` в `builder/versions.env`
2. Собрать: `SOURCEMOD_PROFILE=experimental builder/run/linux.sh`
3. Если падает компиляция — правки в `apply-toolchain.sh` (не трогать v34-логику)
4. Если ломается API плагинов — правки в `apply-api-compat.sh`
5. После проверки на сервере — перенести пин в `SOURCEMOD_STABLE_*`

**Не трогать** `apply-sourcemod.sh` без необходимости — это слой rom4s, от которого зависит вся v34-совместимость.

### Известные отличия 6970 от 6572 (для v34)

- Вкомплектован **DHooks** (`dhooks.ext`) — убрать standalone DHooks при апгрейде
- **GeoIP** — формат `.mmdb`, качается при сборке в `configs/geoip/`
- Новые SDKTools natives (не ломают старые плагины)
- Gamedata: `engine.css.txt`, `game.cstrike.txt` — доп. оффсеты

## Заметки

- SDK: `rom4s/hl2sdk-ep1c` + `alliedmodders/hl2sdk` episode1
- MySQL extension включён
- Только **x86** (32-bit) под v34 dedicated server
