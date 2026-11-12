# Стратегия патчей css34

Как устроены патчи сегодня (после эпика #73, фазы 3–4) и как поднимать версии SourceMod / Metamod.

## Модель

- **Одна линия — один pin — одна серия.** Пины живут только в [`builder/lines.json`](../builder/lines.json);
  `python3 builder/lines.py gen` пишет из него `builder/versions.env`, CI-матрицы, карту тегов и таблицы README.
  Каждая собираемая линия (`sm12-latest`, `sm13-latest`) патчится своей git-серией
  `builder/patches/series/<line>/`, Metamod 1.12 — серией своего pin'а `builder/patches/series/MM_112/`
  (общей для обеих линий). Разбор каждого патча (что и зачем, что ломается без него) —
  [PATCHES.md](PATCHES.md).
- **Серия = `git apply` + проверка дерева.** `<repo>/NNNN-*.patch` на репозиторий (корень `sourcemod` или
  `metamod`, сабмодули вроде `sourcepawn`, `hl2sdk-manifests`); `series.json` хранит upstream-коммит и
  ожидаемое дерево (`git write-tree`) каждого репозитория. `builder/patches/apply-series.sh` применяет серию
  к чистому чекауту pin'а и падает на любом расхождении — fail-closed по построению, без «якорей» и `WARN`.
  `lines.py check` требует, чтобы коммит серии совпадал с pin'ом.
- **Скриптовых патчеров для 1.12+ больше нет** (`apply-sourcemod-v112.sh` / `apply-mmsource-v112.sh` удалены
  в T3.4). Скриптами остаются только собственный код: мост старых плагинов
  (`apply-mmsource-oldbridge.sh`, `builder/patches/mm-oldbridge/`), legacy-ядро MM 1.10
  (`apply-mmsource-css34.sh`) и отладочный `apply-sm-boot-trace.sh` (`CSS34_DEBUG_TRACE=1`, не в релизах).
- **Заморозка вместо поддержки старого кода.** `sm11-oldstable` заморожена (T2.7, [FREEZE.md](FREEZE.md)):
  пересобирается только из тега `sm11-freeze` и архива входов; код SM 1.11 из master удалён (T3.3).

```
SourceMod:  apply-sourcemod.sh                    # роутер: SM < 1.12 или линия без серии → ошибка
              └─ apply-series.sh series/<line>/
                    └─ apply-sm-boot-trace.sh     # только CSS34_DEBUG_TRACE=1
Metamod:    apply-series.sh series/MM_112/        # checkout-deps.sh, по коммиту pin'а
              └─ apply-mmsource-oldbridge.sh modern   # мост старых плагинов (metamod.1.ep1)
            apply-mmsource-css34.sh (MM 1.10)     # legacy-ядро для моста (bridge_metamod)
```

## Апгрейд (новая ревизия той же major)

Обычно его делает бот: `.github/workflows/upstream-bump.yml` (T4.4) раз в неделю открывает по PR на
каждую отставшую цель (`bump/sm12-latest`, `bump/sm13-latest`, `bump/MM_112`) через
`builder/scripts/upstream-bump.py`: двигает pin, перебазирует серию (`git apply --3way`), запускает
`lines.py gen` / `check` и проверку гамедаты на новом исходнике, в тело PR кладёт upstream-лог и
«рискованные» пути. CI на PR собирает, дымит и гоняет botplay. После мёржа тот же workflow пушит тег
линии, `release.yml` (T4.3) выпускает его prerelease'ом, промоутит после smoke/botplay публичных URL и
переключает `line-<line>`.

Jules (если задан `secrets.JULES_API_KEY`, `builder/scripts/jules.py`): на каждый новый bump-PR — ревью
только на чтение (что поменялось в upstream для v34, что проверить, что доработать) комментарием в PR;
если bump не применился (патч не лёг) — задача на минимальный фикс, который Jules оформляет своим PR в
master. Jules не получает токен репозитория, ничего не пушит в master и `bump/*`, ничего не мёржится
автоматически, сбой Jules API не ломает робота.

Руками — тот же порядок:

1. Pin в `builder/lines.json` (commit + rev).
2. `builder/scripts/patch-series.sh refresh <line или MM_112>` — читает pin прямо из `lines.json`
   (`lines.py gen` до этого не запустится: серия ещё для старого pin'а). Если патч не ложится, скрипт
   останавливается с конфликтом: правится сам `.patch`, затем повторный refresh.
3. `python3 builder/lines.py gen` и `python3 builder/lines.py check`.
4. Заранее, без правки pin'а: `builder/scripts/check-patch-drift.sh --sm-commit <rev> --line <line>`
   (или `--range old..new`, `--mm-commit`) показывает первый патч, который не ляжет.

## Новая линия или major

Новая линия — запись в `lines.json` (pin, линия, smoke-образы), своя серия (`patch-series.sh` по образцу
существующей), цель в `TARGETS` у `upstream-bump.py`, при необходимости — патч гамедаты в
`builder/assets/gamedata/` (`check-css34-gamedata.py` ловит новые upstream-lookup'ы). Правка серии одной
линии не задевает другие.
