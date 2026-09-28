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
file="$root/.github/latest-notes.md"
api="https://api.github.com/repos/viktorbeloglazov-design/vpn/releases/tags/latest"

[ -f "$file" ] || { echo "нет файла $file"; exit 1; }

published="$(curl -sS --max-time 60 -H 'Accept: application/vnd.github+json' "$api" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("body",""))' 2>/dev/null)"

if [ -z "$published" ]; then
    echo "пропущена: не удалось прочитать описание выпуска"
    exit 0
fi

if diff -q <(tr -d '\r' < "$file") <(printf '%s\n' "$published" | tr -d '\r') > /dev/null; then
    echo "описание выпуска совпадает с репозиторием"
    exit 0
fi

echo "ОПИСАНИЕ ВЫПУСКА РАСХОДИТСЯ С РЕПОЗИТОРИЕМ"
echo "Слева — файл .github/latest-notes.md, справа — страница загрузки:"
diff <(tr -d '\r' < "$file") <(printf '%s\n' "$published" | tr -d '\r') || true
exit 1
