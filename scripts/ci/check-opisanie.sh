#!/usr/bin/env bash
# Сверяет описание выпуска «latest» с файлом .github/latest-notes.md.
#
# Описание — первое, что читает человек на странице загрузки. Оно
# обновлялось только вместе с выпуском приложения и успело разойтись
# с действительностью: отправляло ставить на Windows чужой клиент,
# хотя наше приложение лежало в том же выпуске, и не упоминало
# инструкцию, которая лежала рядом.
#
# Проверяется не дата и не длина, а текст: что написано на странице
# против того, что лежит в репозитории.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "$root/.github/latest-notes.md" <<'PY'
import json, pathlib, sys, urllib.request

API = ("https://api.github.com/repos/viktorbeloglazov-design/vpn/"
       "releases/tags/latest")

nash = pathlib.Path(sys.argv[1])
if not nash.exists():
    print(f"нет файла {nash}")
    raise SystemExit(1)

try:
    with urllib.request.urlopen(API, timeout=60) as answer:
        published = json.load(answer).get("body", "")
except Exception as beda:
    print(f"пропущена: не удалось прочитать описание выпуска ({beda})")
    raise SystemExit(2)


def lines(text):
    """Строки без возвратов каретки и без пустого хвоста.

    GitHub отдаёт описание с \\r\\n и лишним переводом строки в конце.
    Это разметка передачи, а не расхождение текста.
    """
    out = [line.rstrip("\r") for line in text.split("\n")]
    while out and not out[-1].strip():
        out.pop()
    return out


ours = lines(nash.read_text(encoding="utf-8"))
theirs = lines(published)

if ours == theirs:
    print("описание выпуска совпадает с репозиторием")
    raise SystemExit(0)

import difflib
print("ОПИСАНИЕ ВЫПУСКА РАСХОДИТСЯ С РЕПОЗИТОРИЕМ")
print("«-» — как в репозитории, «+» — как на странице загрузки:")
for line in difflib.unified_diff(ours, theirs, lineterm="", n=1,
                                 fromfile="latest-notes.md",
                                 tofile="страница выпуска"):
    print(line)
raise SystemExit(1)
PY
