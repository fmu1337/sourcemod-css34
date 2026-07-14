# Byte-identical `.so` vs rom4s («SUPER GOLDEN»)

Решённая развилка: стоит ли гнаться за **byte-to-byte** совпадением Linux `.so`
с релизом [rom4s `v1.11.0.6572`](https://github.com/rom4s/sourcemod-css34/releases/tag/v1.11.0.6572).

Связанные draft PR: [#4](https://github.com/fmu1337/sourcemod-css34/pull/4) (clang-9 CI),
[#9](https://github.com/fmu1337/sourcemod-css34/pull/9) (repro / experiments / research).

## Вердикт

**Не преследуем byte-identical как критерий качества.**

Рабочий golden — то, что уже в `master`: один pin SM+MM, layout, ABI-чеки, smoke
на живом CS:S v34 (`1.11.0.6572-mm1.10.7`).

Byte-match как «SUPER GOLDEN» остаётся только архивной целью **если** появятся
исходники удалённого оркестратора или полный Travis-лог 2020 года. Без этого
дальше крутить линкер-флаги не окупается.

## Почему почти наверняка нереально

1. **`rom4s/sourcemod-css34-builder` удалён** (GitHub 404, зеркал нет).
   В Wayback (2020-10-19) есть только оболочка репо и **имена** файлов
   (`build.py`, `config.json`, `patches/`, `run/`), **не содержимое**.
2. Наш `builder/` — **реконструкция** на bash, не копия Python-`build.py`.
   Патчи и порядок шагов ≠ оригиналу (это видно по `.text` на SDK-модулях).
3. Даже twin окружения (Ubuntu 14.04 + clang-9 + pinned deps) в экспериментах #9 дал:
   - **0 / 20** byte-identical native `.so`
   - **9 / 20** same-size (простые ext: logic, bintools, dbi.*, geoip, …)
   - same-size ≠ identical (разный SHA: `.comment`, padding, …)
4. Gap на `sourcemod.1.ep1` / sdkhooks / sdktools / game.cstrike — **десятки KB `.text`**,
   не «пара байт от strip». Symbol analysis указывал на ABI/codegen (libstdc++,
   SourceHook stubs, tier0 import vs stub) + **другой набор патчей**.

Твой скепсис («rom4s мог что-то накрутить в билдере») совпадает с фактами:
оркестратор и exact patch set **невосстановимы** из публичных источников.

## Что дал #4 (clang-9)

Отдельный experimental workflow / `linux-clang9.sh` / jammy-фиксы (`fenv.h`,
`-nostdinc++`).

**На master уже есть:** `USE_CLANG9=1` по умолчанию в `builder/run/linux.sh`,
`install-clang9.sh`, использование в `legacy-build.sh`.

#4 как PR **superseded**: clang-9 нужен для близости к rom4s toolchain, но сам по
себе byte-match не даёт. Draft закрыть.

## Что дал #9 (repro research)

Полезная **фактура**, не код для merge:

| Артефакт в ветке #9 | Смысл |
|---------------------|--------|
| `builder/RESEARCH.md` | Поиск builder: deleted, Wayback metadata only |
| `builder/REPRO.md` | Trusty Docker recipe + таблица 0/20 identical |
| `builder/BINARY-DIFF.md` / `symbol-analysis.py` | ELF-level gap (SDK `.text`, UND) |
| Exp #2–#8 (linker, symlinks, gcc bootstrap) | Не закрыли byte-gap |

В master этот research-стек **не вливаем** целиком (огромный, CONFLICTING, расходится
с текущим in-tree MM/SM пайплайном). Итог зафиксирован здесь.

Краткие цифры trusty repro (из #9 / `REPRO.md`):

| Модуль | Original | Repro (dynamic libstdc++) | Δ |
|--------|----------|---------------------------|---|
| `sourcemod.1.ep1.so` | ~951 KB | ~858 KB | ≈ −93 KB |
| `sdkhooks.ext.1.ep1.so` | ~383 KB | ~309 KB | ≈ −74 KB |
| `sdktools.ext.1.ep1.so` | ~608 KB | ~524 KB | ≈ −84 KB |
| `game.cstrike.ext.1.ep1.so` | ~290 KB | ~207 KB | ≈ −84 KB |

Простые extensions часто **same-size**, но не byte-identical.

## Когда имеет смысл снова трогать тему

- Появился clone / zip `sourcemod-css34-builder`, или
- полный Travis log сборок `v1.11.0.6572` (точные флаги, SHA builder, stdout `build.py`), или
- контакт с rom4s с доступом к патчам.

Иначе — сравнивать с rom4s на уровне **layout / ABI / smoke**, не `cmp` каждого `.so`.

## Связь с текущим golden

См. также [PATCH_STRATEGY.md](PATCH_STRATEGY.md): один pin, последовательные апгрейды,
без dual-CI и без слоёв ради слоёв. Byte-match **не** входит в чеклист релиза.
