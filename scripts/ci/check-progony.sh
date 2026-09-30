#!/usr/bin/env bash
# Проверяет, что проверки каждой платформы прогонялись на нынешнем коде.
#
# Ежедневная проверка запускается в контейнере, где нет ни dotnet, ни
# Xcode, ни Android SDK. Она честно писала «пропущена (нет dotnet)»,
# а в итоге всё равно печатала «проверки проходят». Проверки логики
# Windows к тому моменту не запускались пять дней — прогон идёт только
# при изменении windows/**, и никто этого не замечал.
#
# Поэтому спрашиваем не «есть ли у меня инструменты», а «прогонялись ли
# проверки на том коде, который сейчас лежит». Если код платформы
# менялся после последнего успешного прогона — это неполадка, а не
# пропуск.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "$root" <<'PY'
import json, subprocess, sys, urllib.request

ROOT = sys.argv[1]
BRANCH = "claude/mac-vpn-app-routes-7jv8o7"
RUNS = ("https://api.github.com/repos/viktorbeloglazov-design/vpn/"
        f"actions/runs?branch={BRANCH}&per_page=100&status=success")

# Прогон — и что он проверяет. Пути те же, по которым прогон
# запускается: если в них ничего не менялось, старый прогон
# по-прежнему говорит о нынешнем коде.
PROVERKI = [
    ("windows-tests", "Проверки логики Windows", ["windows/"]),
    ("build", "Проверки ядра Mac", ["Sources/", "Package.swift", "Tests/"]),
    ("android", "Проверки Android", ["android/"]),
]


def git(*args):
    out = subprocess.run(["git", "-C", ROOT, *args],
                         capture_output=True, text=True)
    return out.stdout.strip()


try:
    with urllib.request.urlopen(RUNS, timeout=60) as answer:
        runs = json.load(answer)["workflow_runs"]
except Exception as beda:
    print(f"пропущена: не удалось прочитать прогоны ({beda})")
    raise SystemExit(2)

bed = 0
for imya, chto, puti in PROVERKI:
    svezhiy = next((r for r in runs if r["name"] == imya), None)
    if svezhiy is None:
        print(f"{chto}: успешных прогонов нет вообще")
        bed += 1
        continue

    kod = git("log", "-1", "--format=%H", "--", *puti)
    if not kod:
        print(f"{chto}: в репозитории нет этих файлов")
        bed += 1
        continue

    progon = svezhiy["head_sha"]
    # Прогон покрывает нынешний код, если последняя правка платформы
    # уже была в дереве, на котором он шёл.
    pokryto = subprocess.run(
        ["git", "-C", ROOT, "merge-base", "--is-ancestor", kod, progon],
        capture_output=True).returncode == 0

    when = svezhiy["created_at"][:10]
    if pokryto:
        print(f"{chto}: прогон {when} на {progon[:7]} — покрывает нынешний код")
    else:
        print(f"{chto}: ПОСЛЕ ПРОГОНА КОД МЕНЯЛСЯ — не проверено")
        print(f"    последний успешный прогон: {when}, {progon[:7]}")
        print(f"    правка платформы позже: {kod[:7]} "
              f"({git('log', '-1', '--format=%s', kod)})")
        bed += 1

raise SystemExit(1 if bed else 0)
PY
