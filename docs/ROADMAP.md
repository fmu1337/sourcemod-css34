# sourcemod-css34 — ROADMAP: план работ для агентов (v2)

Дата: 2026-10-15. Основан на исследованиях metamod / upstream / crutches / oldos / process / dual и двух независимых критиках.

## Решения владельца (зафиксировано)

| # | Решение |
|---|---|
| D1 | Три линии SM: **1.11** = 6970, собрать один раз правильно → заморозить; **1.12** = 1.12-dev (сейчас 7255), периодические бампы; **1.13** = master (сейчас 7477), периодические бампы. |
| D2 | **1.ep1 только для 1.11.** 1.12/1.13 — только 2.ep1 на Metamod 1.12-dev (сейчас git1227). |
| D3 | 1.11 — **один SM-пакет с обоими ядрами** (1.ep1 для MM 1.10.7, 2.ep1 для MM 1.12), как у rom4s. |
| D4 | Старые ОС: **glibc 2.17** (CentOS/RHEL 7+, Debian 8+, Ubuntu 14.04+) через `quay.io/pypa/manylinux2014_i686`. |
| D5 | **Windows для всех трёх линий**, включая оба варианта 1.11; публикация только после Windows smoke. |
| D6 | `sm13-mm20` — в отставку; `sm13-mm20-khook` — заморозить вне CI до слияния KHook в SM master (PR #2403); ID линий и контракт `v34_server_base` сохраняются (поля только добавляются); сломанные релизы → prerelease с баннером; еженедельные bump-PR, мёржит владелец, релиз после мёржа автоматически. |
| D7 (по умолчанию, можно возразить до T2.6) | Default-Metamod на `line-sm11-oldstable` — **MM 1.12**; MM 1.10.7 — отдельный ассет `mmsource-legacy-css34-*`. Формат тегов — **прежний** (`1.12.0.7255-mm1.12.0`, `-rN` для пересборок); для двойной 1.11 — `1.11.0.6970-mm1.12.0-dual`. |

## Фундаментальные противоречия → разрешение

1. **Паритет 1:1 с rom4s ↔ современный апстрим.** clang-9 из bitbucket, gcc-4.9 sysroot, ABI0, C++20→17 + самописный `std::span`, UB-переписка `CheckedMul`… → паритет не цель; совместимость проверяется поведением (smoke, botplay, vtable-check, PLAPI-пробы); один тулчейн — GCC 10 в manylinux2014.
2. **«legacy-build» не legacy** (debian:11 → glibc 2.29, хотя srcds v34 требует 2.3.2, rom4s — 2.12) → manylinux2014, гейт `GLIBC ≤ 2.17` на каждом ELF.
3. **«Заморозить 1.11» ↔ опубликованный 1.11 сломан** (SIGABRT на Ubuntu 24.04/Debian 13; 2.ep1 не грузится ни в одном MM) → сначала правильная пересборка и доказательство, потом заморозка вместе со всеми входами.
4. **Двухъядерный пакет, где работает одно ядро** (`apply-mmsource-css34.sh` затирает `core/` legacy-заголовками → PLAPI 11 у обоих) → per-SDK include roots; дизайн доказан частичной пересборкой (smoke 6/6, botplay 2/2), реальный билдер должен воспроизвести.
5. **«Один пин» в документации ↔ 5 линий в CI, пины руками в ~10 местах** → `builder/lines.json` как единственный источник, остальное генерируется.
6. **Fail-open патчинг ↔ «главное, чтобы работало»** (часть патчей уже молча не применяется) → fail-closed + git-серии патчей.
7. **Отладка в релизах** (SM_BOOT_TRACE в `/tmp`, LOG_ECHO_SAFE ломает `sv_logecho`, Logger «всегда Mapchange» — подпорка под smoke) → убрать; smoke не должен требовать изменённого поведения SM.
8. **CI, который прячет падения** → фаза 0 до всех рефакторингов.
9. **«Как апстрим» ↔ голый апстрим не работает на v34** → минимальный обоснованный набор патчей (A/B-проверка каждого), обобщаемые — апстриму.
10. **Гейт, закрепляющий баг** (`check-package.sh` требует ≥100 экспортов logic = утечку libstdc++) → правила rom4s заменить на свидетельства v34.

## Целевая архитектура

| Линия | SourceMod | Metamod | Политика | Платформы |
|---|---|---|---|---|
| `sm11-oldstable` | 1.11.0.6970 (f53cb134), двухъядерный, DHooks как `dhooks.ext.2.ep1` | MM 1.12 git1227 (default) + MM 1.10.7 git976 (legacy) | frozen; CI только пере-проверяет опубликованное | Linux + Windows |
| `sm12-latest` | 1.12-dev 7255 (03865e00) | MM 1.12-dev git1227 (общий пин) | tracking stable | Linux + Windows |
| `sm13-latest` | master 7477 (ce7dccff), настоящий C++20 | MM 1.12-dev git1227 | tracking dev; MM 2.0 — плановая миграция после KHook в SM master | Linux + Windows |
| `sm13-mm20`, `sm13-mm20-khook` | — | — | retired / frozen, вне CI, код в `archive/khook` | — |

**Linux-тулчейн (проверено в исследовании):** `quay.io/pypa/manylinux2014_i686@sha256:30305867f278896ee117b0d162a8e4f9b7b16819e6590f6139e14c5ed5b23fdd` (CentOS 7.9 i686, glibc 2.17, devtoolset-10 GCC 10.2.1), Python для AMBuild — `/opt/python/cp311-cp311/bin/python`, AMBuild по SHA.
- Все Linux-модули: `-static-libstdc++ -Wl,--exclude-libs=libstdc++.a:libsupc++.a`; `--exclude-libs=ALL` — только для `sourcemod.logic.so` и не-SDK расширений (dbi.*, общие); на ядрах, игровых расширениях и `metamod.*.ep1` экспорт tier1 (ConVar, `s_pConCommandBases`, `InterfaceReg`) остаётся. libgcc_s — динамически, как в проверенных сборках. `spcomp` — исключение (линкуется с libstdc++.so.6 динамически; гейт GLIBCXX ≤ 3.4.19).
- Предупреждения GCC 10 как закоммиченные патчи AMBuildScript (не env-обёртка): `-Wno-volatile` (C++20), `-Wno-format-truncation -Wno-stringop-truncation` (MM 1.12 `-Werror`, metamod.cpp:852), `-Wno-sign-compare` (1.11).
- MariaDB Connector/C: статический **OpenSSL 1.1.1w** (проверен); 3.5 LTS — отдельной задачей с TLS-пробой.

**Windows:** MSVC x86 на закреплённом `windows-2022` + зафиксированный toolset/SDK (версии пишутся в манифест), zip с прямыми слешами и `css34-package.json`.

## Конвенции для всех задач

- Одна задача = одна ветка + один draft PR; мёрж только при зелёном CI.
- Каждый PR, меняющий команду/точку входа, **в том же PR** обновляет AGENTS.md и README.
- Smoke-гейт для изменений сборки: до T1.6 — debian:11 + ubuntu:24.04; с T1.6 — centos:7 (floor) + ubuntu:24.04 + debian:13.
- Задачи не ссылаются на scratchpad: всё нужное — в тексте задачи.

## Фазы и задачи

### Фаза 0 — CI говорит правду (дни)

**T0.1 CI-гигиена + отставка mm20/khook из CI** — `test-server.yml`, `build.yml`, `release.yml`, `cleanup-artifacts.yml`, `legacy-build.sh`, `.gitignore`, `resolve-version.sh`.
Убрать `cleanup-workflow-storage` (логи падений — 7 дней); расписание чистки `keep_hours=72`; `cancel-in-progress` только для PR; удалить `test-built-botplay` (`if: false`), `.travis.yml`, `pushbuild.txt`; точные пути вместо `ls | head -n1`; `/mmsource-*.tar.gz` в `.gitignore`, не создавать симлинки на `/workspace`; убрать `sm13-mm20`/`sm13-mm20-khook` из всех матриц (Linux, Windows, Wine), их builder-код — в ветку `archive/khook`, pointer'ы не трогать; сравнения с rom4s-baseline в botplay — только информационные.
*Приёмка:* actionlint чистый; `grep -rn 'head -n1' .github builder testing | grep packages` пусто; в PR с намеренно падающим smoke артефакт доступен после прогона; в матрицах только sm11/sm12/sm13.

**T0.2 install-deps + обязательный vtable-check** (после T0.1 — общие файлы) — `install-deps.sh`, `smoke-test.sh`.
Ставить `python3` и `binutils`; фикс пустого массива под bash 4.3 (`set -u`); vault CentOS 7 по https; `--no-install-recommends`; при `CSS34_CI=1` SKIP vtable-check = FAIL.
*Приёмка:* install-deps = 0 в centos:7, ubuntu:16.04/18.04/24.04, debian:9/10/11/13, rockylinux:9; в логах CI «vtable offsets match» для каждой линии; на пакете 1.12.0.7245 проверка падает.

**T0.3 Smoke на новых ОС** (после T0.1) — `test-server.yml`: ubuntu:24.04 и debian:13 для sm11/sm12/sm13; текущий sm11 — `continue-on-error` до фазы 2.
*Приёмка:* CI воспроизводит `free(): invalid pointer` для sm11 на 24.04.

**T0.4 Убрать отладочные костыли из релизов** (после T0.2).
`smoke-test.sh:129` — требовать `Started map "${MAP}"` от движка; `:293` — заменить на «SourceMod log file session started», вывод `sm plugins list` и отсутствие `<FAILED>`; удалить `apply-logger-mapchange-fix.sh` и LOG_ECHO_SAFE; SM_BOOT_TRACE — только при `CSS34_DEBUG_TRACE=1`, якоря `apply-sm-boot-trace.sh` перевести на непатченный Logger.cpp.
*Приёмка:* `strings sourcemod.*.so | grep -c sm-boot-trace` = 0; smoke и botplay зелёные без Logger-патчей.

**T0.5 `builder/lines.json` (минимальный)** — пины, статус линии, `known_bad`, генератор `versions.env` (`builder/lines.py gen|check`); `check-version-pins.sh` → `lines.py check` в CI.
*Приёмка:* `source resolve-version.sh` даёт те же переменные для всех линий (diff пуст); ручная правка `versions.env` валит `lines.py check`.

**T0.6 Разбор сломанных релизов** *(после ok владельца)*.
В prerelease + баннер «KNOWN BAD → line-…»: `1.11.0.6572-mm1.10.7`, `1.12.0.7239-mm1.12.0`, `1.12.0.7245-mm1.12.0`, `1.13.0.7394-mm1.12.0`, `1.11.0.6970-mm1.10.7`; заметка на Windows-ассетах базовых khook-тегов; GitHub «Latest» → `1.13.0.7472-mm1.12.0-r2`; список в `lines.json.known_bad`.
*Приёмка:* `releases/latest` = smoke-passed тег; отвечают 200: `line-{sm12-latest,sm13-latest,sm13-mm20,sm13-mm20-khook}/{lines.json,SHA256SUMS,*.tar.gz}`, `lines-index/lines.json`, ассеты `1.12.0.7245-mm1.12.0` и Windows-MM zip из `1.11.0.6572-mm1.10.7` (их использует `v34_server_base`).

### Фаза 1 — Новый тулчейн, glibc 2.17, свежие пины

**T1.1 Перенос сборки в manylinux2014 (одним PR, иначе не станет зелёным)** — новый `builder/docker/build.sh` (заменяет `legacy-build.sh`), `run/linux.sh`, `checkout-deps.sh`, патчи AMBuildScript, `check-package.sh`.
Всё из раздела «Linux-тулчейн»: образ по digest, devtoolset-10, Python 3.11, флаги GCC 10, скрытие libstdc++, OpenSSL 1.1.1w (`./Configure linux-elf no-shared no-tests no-dso -fPIC`, sha256); убрать захардкоженные `gcc-9`/`g++-9` и пути к Debian `libstdc++.a` для logic; фикс `__GNUC__ == 4` → `__GNUC__ >= 4` **только** в MM 1.10 `core-legacy/oslink.h:66`, `core-legacy/ISmmPlugin.h:384`, `core-legacy/sourcemm.cpp:638`; в `check-package.sh` убрать правило «≥100 экспортов logic» и rom4s-сравнение, добавить `GLIBC_FLOOR` (по умолчанию 2.17). Закрепить SHA hl2sdk `episode1`, `rom4s/hl2sdk-ep1c`, AMBuild; sha256 для всех tarball'ов; переводы — из того же коммита SM; GeoLite2 — с sha256 и атрибуцией MaxMind.
*Приёмка:* для sm11/sm12/sm13 пакеты собираются; `readelf -p .comment` = GCC 10.2.1, нет `clang version`; max GLIBC ≤ 2.17 у всех ELF; `objdump -T --defined-only sourcemod.logic.so | c++filt | grep -cE 'std::|__cxxabiv1'` = 0; ни один MM .so не имеет `NEEDED libstdc++.so.6`; `nm -D` ядер показывает `T _ZN6ConVarC1EPKcS1_i` и `B _ZN14ConCommandBase18s_pConCommandBasesE`; smoke на debian:11 и ubuntu:24.04 (sm11 — на MM 1.10.7, пока одноядерный путь).

**T1.2 Номер сборки MM/SM в рантайме** — `checkout-deps.sh`, `generate_headers`-патчи.
Сейчас из-за `--depth 1` MM показывает `1.12.0-dev+1`. Подставлять `MM_REV`/`SM_REV` из `lines.json` (Linux и Windows), убрать патчи «полный SHA» в пользу строки версии css34.
*Приёмка:* `meta version` содержит `+<MM_REV>` и `Build ID: <MM_REV>:`; `sm version` = `<major>.<SM_REV>`; smoke это проверяет.

**T1.3 C++20 для 1.13** — удалить даунгрейд C++20→17 и `cxx17-compat/span`.
*Приёмка:* в логе sm13 `-std=c++20`, 0 упоминаний `cxx17-compat`; smoke зелёный.

**T1.4 Удаление костылей тулчейна (по коммиту на пункт, каждый со smoke)** — clang-9/10 и обёртки, gcc-4.9 sysroot, `patch-ambuild-linker.sh`, CheckedMul-переписка, strptime-шим, `-fno-sized-deallocation`, затем отдельным коммитом `_GLIBCXX_USE_CXX11_ABI=0` (только при зелёном botplay). `patch-ambuild-py312.sh` оставить или заменить закреплённым Python.
*Приёмка:* `git grep -nE 'clang-9|clang\+\+-9|clang-10|gcc-4\.9|SM_LOGIC_CXX_SYSROOT|sysroot-i386' builder testing .github` пусто; smoke+botplay зелёные.

**T1.5 Бампы + пробы на изменения 7477** — `lines.json`: sm12 → 7255 (`03865e00cc124221122ae9798ad38998566f9a2b`), sm13 → 7477 (`ce7dccfffbabe02f872f5ac3f4eb3f310e68f9f3`), MM 1.12 → git1227 (`75dd7b26…`). Новые botplay-пробы: sound hook `Plugin_Changed` (#2586), чистка entity output hooks на смене карты (#2589), userid lookup (#2577). Защита от флагов манифеста: проба `$CXX -Werror <flag> -fsyntax-only`, неподдерживаемые флаги отбрасываются (манифесты ebd6e10).
*Приёмка:* `sm version` = 1.12.0.7255 / 1.13.0.7477, `meta version` = 1.12.0-dev+1227; новые пробы зелёные.

**T1.6 Матрица ОС, загрузка dbi** — на каждый PR: smoke centos:7, ubuntu:24.04, debian:13 для каждой линии + один botplay на линию; еженедельно и на релиз: debian:10/11, rockylinux:9, ubuntu:14.04/16.04/18.04, debian:8/9 и botplay на centos:7. Образы по digest; paths-filter для doc-only PR. В smoke — `sm exts load dbi.mysql` / `dbi.pgsql` (сейчас никто не грузит).
*Приёмка:* пакет с floor 2.29 валит centos:7; dbi-расширения грузятся на centos:7 и ubuntu:24.04.

**T1.7 Windows для sm12/sm13** — `run/windows.sh`, `package*-windows.ps1`, `build.yml`.
`runs-on: windows-2022` + зафиксированный MSVC toolset; имена ассетов с ревизией; манифест в zip; zip через python `zipfile`; smoke грузит SDK Hooks (и DHooks); sm12 добавлен в Windows-матрицу; Wine botplay (коротко, de_dust2) — опционально или записать как принятый пробел.
*Приёмка:* `unzip -l` без `\`; манифест есть; нативный и Wine smoke зелёные для sm12 и sm13.

**T1.8 Релизы sm12/sm13 + откат pointer'а** — `release.yml`.
Release-smoke на centos:7, ubuntu:24.04, debian:13; Linux-pointer не зависит от джоба `windows` (ни напрямую, ни через `checksums`); новые теги в маппинге (`1.12.0.7255-mm1.12.0`, `1.13.0.7477-mm1.12.0`); вход `repoint_tag` в `workflow_dispatch`: вернуть pointer на прежний smoke-passed тег + smoke-pointer; runbook в README.
*Приёмка:* pointer'ы sm12/sm13 на новых тегах, `min_glibc=2.17` в манифестах; тестовый repoint на `-r2` и обратно проходит.

### Фаза 2 — Двухъядерная 1.11, сборка и заморозка (после T1.8)

**T2.1 Legacy-заголовки MM отдельно** — `apply-mmsource-css34.sh`, `gen-sh-decl-extern-v4.py`, `build-metamod.sh`, `checkout-deps.sh`, `resolve-version.sh`.
Генерировать `$MM110/core-css34legacy/` (копия `core/*.h` + `core-legacy/sourcehook` + SH_DECL_EXTERN v4 + legacy-порядок ISmmAPI/ISmmPlugin + PLAPI 11 + `__GNUC__ >= 4`); `core/` не трогать; убрать симлинк `$mms/sourcehook`, ProtoInfo-guard и `sourcehook-pibuilder-shim.h`; guard в `build-metamod.sh` — проверять `core-css34legacy/sourcehook/sourcehook.h`.
*Приёмка:* `git diff --stat 80e8ff0 -- core/ ':!core/metamod_console.cpp'` пусто; `core-css34legacy/ISmmPluginExt.h` = PLAPI 11, SourceHook v4; `metamod.1.ep1.so` экспортирует GetGameDllBridge/GetVspBridge, smoke с MM 1.10.7 зелёный.

**T2.2 Два Metamod для sm11** — sm11 выкачивает MM 1.10-dev (80e8ff0) и MM 1.12 (собственный замороженный пин в `lines.json`, равный git1227), собирает два MM-пакета, оба с `css34-package.json`.

**T2.3 Per-SDK include roots + DHooks + plapi-probe** — `apply-sourcemod.sh` (путь 1.11), `run/linux.sh`.
В `ConfigureForHL2` (f53cb134:AMBuildScript ~567-573): `sdk.name == 'ep1'` → `CSS34_MMS_LEGACY_CORE` и его `/sourcehook`, остальное → `mms_root/core` (MM 1.12); configure `--sdks=ep1,episode1 --mms-path=<mmsource-1.12>`; вернуть DHooks как `dhooks.ext.2.ep1` (без `dhooks.ext.so`); сохранить нужное для 1.ep1 (loader `CreateInterface` → `sourcemod.1.ep1`, Query non-NULL, GAMEFIX 1.ep1, `--allow-multiple-definition`). Добавить `testing/tools/plapi-probe.c`: i386-программа, которая с `LD_LIBRARY_PATH=<srv>/bin` делает `dlopen` модуля, вызывает экспорт `CreateInterface("ISmmPlugin", …)` (для SM ≥ 1.12 — `CreateInterface_MMS`), берёт `vtable[0]` (`GetApiVersion`) и печатает PLAPI.
*Приёмка:* в логе ep1 — `-I…/core-css34legacy`, остальное — `-I…/mmsource-1.12/core`; в пакете `sourcemod.{1,2}.ep1`, `{sdktools,sdkhooks,game.cstrike}.ext.{1,2}.ep1`, `dhooks.ext.2.ep1`; plapi-probe: `*.1.ep1` = 11, `*.2.ep1` ∈ [14,16] с экспортом CreateInterface; наборы экспортов совпадают с эталоном из spike'а (описание в PR); 0 строк `WARN` в логе сборки 1.11 (fail-closed для пути 1.11 — в этой же задаче).

**T2.4 Гейты двухъядерного пакета** — статика (оба ядра, оба суффикса, `dhooks.ext.2.ep1` и нет `dhooks.ext`, loader экспортирует оба `CreateInterface*`, plapi-probe); динамика: smoke dual × {MM 1.12, MM 1.10.7} × {centos:7, ubuntu:24.04, debian:13}; botplay на обоих MM (DHooks-проба available=1 на MM 1.12, SKIP на MM 1.10.7); тест переключения MM.
*Приёмка:* гейт падает на опубликованном `1.11.0.6970-mm1.10.7` (2.ep1 = 11); новый пакет зелёный везде.

**T2.5 Windows двухъядерный** — сначала отдельная сборка MM 1.10.7 `metamod.1.ep1.dll` на закреплённом runner'е; затем SM с той же логикой AMBuildScript; PE-проверка PLAPI (11 / 16); нативный + Wine smoke на обоих MM с SDK Hooks. Запасной путь при дублях `CreateInterface` в MSVC — две сборки со слиянием только для Windows.

**T2.6 Манифесты, pointer, инструкция** — SM-манифест: блок `cores{1.ep1,2.ep1}`, `metamod_binaries`; скалярный `metamod_binary` для sm11 → `metamod.2.ep1` (**изменение значения** — согласовать с `v34_server_base`, см. T2.8); новые ассеты `mmsource-legacy-css34-{linux.tar.gz,windows.zip}`; README: выбор/переключение MM (удалить `addons/metamod/bin/{server*,metamod.*}`, распаковать другой MM, сохранить `metaplugins.ini`), что работает на каком MM.

**T2.7 Заморозка 1.11** — образ сборки → `ghcr.io/fmu1337/css34-build-ml2014@sha256:…` + `docker save | zstd` и все исходные tarball'ы (SM, MM 1.10/1.12, hl2sdk, ep1c, AMBuild, OpenSSL, MySQL, GeoLite2) как ассеты релиза `sm11-freeze-inputs`; версии Windows-тулчейна в манифесте; сборка через защищённое окружение `frozen-release`; `lines.json`: `status=frozen` + sha256 пакетов; еженедельный `frozen-verify.yml`; sm11 убирается из push-CI; политика: после заморозки 1.11 пересобирается только из тега `sm11-freeze`, код 1.11 на master можно удалять в фазе 3.
*Приёмка:* `--network none` пересборка из архива даёт идентичный набор экспортов и PLAPI; `line-sm11-oldstable` существует; frozen-verify зелёный.

**T2.8 Инсталлятор (кросс-репо, PR готовит агент, применяет владелец)** — `fmu1337/v34_server_base`: добавить `sm11-oldstable` в `sources.json`, переключатель `--metamod {default,legacy}`, заменить fallback на known-bad 7245, consumer-smoke.

### Фаза 3 — Патчи: fail-closed, минимальные серии

**T3.1 Drift-harness** `builder/scripts/check-patch-drift.sh` — dry-run слоя патчей на новом апстрим-коммите; запускается в bump-PR.
**T3.2 Fail-closed для sm12/sm13/MM 1.12** — промах якоря = ошибка (allowlist с причиной); 0 `WARN` в CI.
**T3.3 Удаление мёртвого кода** — SE_CSS-правки, старые цепочки вариантов, splice-скрипты и `PURE_SOURCE_BUILD`, `sourcemod-6572-css34.patch`, `assets/hl2sdk-manifests/ep1.json`, режим MM 1.11, `apply-toolchain.sh`, include-заглушки, сабмодуль `sourcemod` (fetch по пину); код 1.11 — после T2.7.
**T3.4 Git-серии патчей** — по PR на дерево: `patches/sm13/`, `patches/sm12/`, `patches/mm112/` (`git am`, проверка `HEAD^{tree}` из `lines.json`). Каждый патч проходит A/B (без него smoke/botplay падает или есть доказательство), итог в `docs/PATCHES.md`.
**T3.5 Проверка покрытия гамедаты на каждом бампе** — все используемые смещения/сигнатуры sdktools/sdkhooks/cstrike/core присутствуют в css34-overlay (3 из 5 сломанных релизов — из-за гамедаты).
**T3.6 Черновики апстрим-репортов** — RTLD_NOLOAD, FindDataMapInfo, pthread NEEDED, mem.h, порядок tier1 для episode1, баги KHook DHooks.

### Фаза 4 — Релизы v2 и автоматизация

**T4.1 `lines.json` → генерация CI-матриц, маппинга тегов, таблиц README**; удалить fallback-пины из скриптов; `matrix.json` — только история/совместимость.
**T4.2 Один `ci.yml`** (инкрементально: сначала plan-джоб и генерация матриц, потом перенос джобов) с единым `gate`; удалить jammy-сборку из `build.yml`.
**T4.3 `release.yml` v2** — тег проверяется против пинов; prerelease → smoke публичных URL → promote → pointer; Windows не блокирует Linux; SHA256SUMS последним; Latest явно; автогенерация release notes (пины, тулчейн, `min_glibc`, known-bad).
**T4.4 `upstream-bump.yml`** — еженедельно PR на линию (+ MM 1.12-dev): `git log`, рискованные пути, drift dry-run, проверка гамедаты; токен GitHub App; после мёржа — авто-релиз.
**T4.5 OpenSSL 3.5 LTS** (опционально) — с пробой TLS-подключения к MariaDB в CI.

### Фаза 5 — Документация и уборка

**T5.1 Финальная документация** — README, AGENTS.md, PATCH_STRATEGY.md (новая модель), testing/README.md; BYTE_MATCH.md, V34_COMPARISON, 6522-notes, JULES_DAILY_VERSION_BUMP.md → `docs/archive/`.
**T5.2 Уборка веток** — `claude/css34-dhooks-probe`, `claude/youthful-gates-vkav5l`, `claude/khook-mm-2-0-v34-k9wv3x`, `cursor/mm20-khook-c33d`, `upgrade/sm13-mm20-khook-…`, `cursor/cleanup-stale-branches-dabc`; решить судьбу draft PR #71.

## Порядок

```
Фаза 0: T0.1 → {T0.2 → T0.4} ‖ T0.3 ; T0.5 ; T0.6 (после ok владельца)
Фаза 1: T1.1 → {T1.2 ‖ T1.3 ‖ T1.4} → T1.5 → {T1.6 ‖ T1.7} → T1.8
Фаза 2: (после T1.8) T2.1 → T2.2 → T2.3 → T2.4 → {T2.5 ‖ T2.6} → T2.7 ; T2.8 после T2.6
Фаза 3: T3.1 ‖ T3.2 (после фазы 1) → T3.3 (1.11-часть после T2.7) → T3.4 ; T3.5, T3.6 в любой момент
Фаза 4: T4.1 (после T0.5) → T4.2 → T4.3 → T4.4 ; T4.5 опционально
Фаза 5: документация — в каждом PR; T5.1 финал; T5.2 в любой момент
```

## Действия владельца

1. Отключить ежедневную задачу Jules (иначе она продолжит править пины параллельно с планом).
2. Одобрить T0.6 (перевод сломанных релизов в prerelease).
3. Создать GitHub App (contents + pull-requests: write) для bump-бота → `vars.BUMP_APP_ID`, `secrets.BUMP_APP_KEY`.
4. Создать окружение `frozen-release`; сделать `gate` обязательной проверкой master.
5. Применить PR в `v34_server_base` (T2.8); отправить апстрим-репорты (T3.6).
6. Возразить до T2.6, если default-Metamod для 1.11 должен быть MM 1.10.7 (D7).

## Риски

- Двухъядерная Windows-сборка не проверялась (дубли `CreateInterface` в MSVC, MM 1.10.7 на современном MSVC) → T2.5 начинается с отдельной сборки MM 1.10.7; запасной путь — две сборки со слиянием.
- Будущий C++ в SM master сверх GCC 10 → план B: clang + sysroot CentOS 7 (тот же floor); план C: manylinux_2_28 (floor 2.28).
- Отказ от ABI0 — только за botplay-гейтом.
- Контейнеры делят ядро хоста: реальные старые ядра (CentOS 7, 3.10) не проверены.
- KHook в SM master → 1.13 потребует MM 2.0: плановая миграция с заморозкой последней SourceHook-сборки.
- Сторонние 1.ep1-only расширения и MM-плагины PLAPI ≤ 11 работают только с legacy-MM; DHooks и `.2.ep1` — только с MM 1.12.
- Нагрузка CI: per-PR — только floor+ceiling образы и один botplay на линию, остальное — еженедельно.
