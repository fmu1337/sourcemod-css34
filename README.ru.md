# sourcemod-css34

[English](README.md) | **Русский**

Пропатченные [SourceMod](https://www.sourcemod.net/) + [Metamod:Source](https://www.sourcemm.net/) для
**Counter-Strike: Source v34** (episode1, 32-bit), собранные из исходников для Linux с glibc 2.17+ и Windows.
Что мы меняем и зачем: [docs/CHANGES.md](docs/CHANGES.md).

## Установка

У каждой линии есть указатель, который всегда отдаёт её самую свежую сборку, прошедшую smoke-тест на
публичных URL:

```
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/mmsource-css34-linux.tar.gz
https://github.com/fmu1337/sourcemod-css34/releases/download/line-<line>/sourcemod-css34-linux.tar.gz
```

| `<line>` | Роль |
|----------|------|
| `sm13-latest` | **По умолчанию** (SourceMod 1.13) |
| `sm12-latest` | Последняя 1.12 |
| `sm11-oldstable` | Заморожена, dual-core (SourceMod 1.11) |

Точные версии SourceMod и Metamod каждой линии указаны в таблице в [README.md](README.md#install).

```bash
tar -xzf mmsource-css34-linux.tar.gz -C /path/to/cstrike
tar -xzf sourcemod-css34-linux.tar.gz -C /path/to/cstrike
```

Всегда берите Metamod и SourceMod из одной линии (или одного тега). Что сейчас отдаёт каждый указатель:
[`lines-index/lines.json`](https://github.com/fmu1337/sourcemod-css34/releases/download/lines-index/lines.json)
или страница релиза `line-<line>`. Zip-архивы для Windows есть только в релизах по тегам. Переход с SM 1.7 /
1.8 / 1.11: [docs/MIGRATION.md](docs/MIGRATION.md). Сторонние расширения: [docs/EXTENSIONS.md](docs/EXTENSIONS.md).

### sm11

`line-sm11-oldstable` также отдаёт MM 1.10.7 как `mmsource-legacy-css34-linux.tar.gz` — для расширений,
которые существуют только в виде `*.ext.1.ep1` (он запускает ядро SourceMod `1.ep1`; без DHooks).

## Совместимость

- **Старые плагины Metamod** (PLAPI 7–12, собранные под MM 1.4–1.10) работают на любом пакете MM 1.12: он
  также содержит ядро MM 1.10.7 `metamod.1.ep1` и передаёт такие плагины ему. `metaplugins.ini` оставьте как есть.
- **Старые плагины `.smx`** загружаются на 1.12 / 1.13 без изменений (CI загружает плагины, собранные spcomp
  1.7.3 и 1.11).
- **Расширения**, собранные под SM ≤ 1.12, не загружаются на 1.13 (API 9–11), и наоборот: под каждую линию
  нужна своя сборка.
- Оставшийся от стороннего MM 1.11 `metamod.2.ep1.so` → `Older Metamod… (11 < 14)`: это смесь версий, а не
  битый пакет. Плоский `gamedata/sm-cstrike.games.txt` из старой сборки ломает cstrike
  (`Could not locate HandleCommand_Buy`): удалите его.
- Автообновления gamedata нет: `updater.ext` перезаписал бы gamedata для v34. Оставшиеся от старых пакетов
  `updater.ext.so` / `webternet.ext.so` никогда не загружаются, их можно удалить.
- В `core.cfg` нет `FollowCSGOServerGuidelines` и `SteamAuthstringValidation`: на v34 обе ничего не делают.
  Старый `core.cfg` с ними загружается без изменений.

## MySQL HeatWave / MySQL 8.4 (`sm13-latest`)

`dbi.mysql` поддерживает `caching_sha2_password`, TLS 1.2/1.3 и `utf8mb4`. TLS выключен, если запись в
`databases.cfg` не требует его явно:

```
"ssl_mode"  "verify_ca"              // disabled (по умолчанию) | preferred | required | verify_ca | verify_identity
"ssl_ca"    "configs/mysql-ca.pem"   // относительно addons/sourcemod/
```

Для HeatWave используйте как минимум `required`, а лучше `verify_ca` с CA вашей DB system. `preferred`
откатывается на нешифрованное соединение и не проверяет сертификат. Неизвестный режим или режим проверки без
читаемого CA приводят к ошибке подключения. Ключи и значения такие же, как в
[fmu1337/sm-dbi-mysql](https://github.com/fmu1337/sm-dbi-mysql), где по умолчанию `preferred`: записи,
которые на это полагались, теперь должны указывать его явно. `sm12-latest` не может войти в MySQL 8.4 / HeatWave.

## Плохие релизы

Никогда не попадают на указатель; список — `known_bad` в `builder/lines.json`:

- `1.12.0.7239-mm1.12.0`, `1.12.0.7245-mm1.12.0`, `1.13.0.7394-mm1.12.0`: отсутствует или неверна gamedata
  для v34 (`SDKHook()` → `Hook type not supported on this game`).
- `1.11.0.6970-mm1.10.7`: SIGABRT при запуске на новых дистрибутивах, его ядро `2.ep1` не загружается. Заменён
  на `1.11.0.6970-mm1.12.0-dual`.
- `1.11.0.6572-mm1.10.7`: оффсеты SDKTools от Steam-версии CS:S. Всё ещё опубликован как prerelease (путь
  установщика для Windows `--sm rom4s` использует его zip с MM 1.10.7).

Линии Metamod 2.0 (`sm13-mm20`, `sm13-mm20-khook`) отправлены в архив: [docs/KHOOK.md](docs/KHOOK.md).

## Сборка

Нужен Docker. Сборки идут в закреплённом образе `quay.io/pypa/manylinux2014_i686` (glibc 2.17, GCC 10);
версии закреплены в [`builder/lines.json`](builder/lines.json).

```bash
CSS34_LINE=sm13-latest builder/docker/build.sh     # или sm12-latest; пакеты появятся в packages/
CSS34_LINE=sm13-latest builder/run/windows.sh      # Windows: windows-2022, MSVC 14.44
```

`sm11-oldstable` пересобирается только из своего архива заморозки. Релизы, указатели, обновления версий,
замороженная линия и CI: [docs/MAINTAINING.md](docs/MAINTAINING.md). Тесты: [testing/README.md](testing/README.md).
