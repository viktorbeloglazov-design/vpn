#!/usr/bin/env bash
# Собирает инструкцию: HTML → проверка, что всё влезает → PDF.
#
# Chromium берётся из переменной CHROME. На машине разработчика это
# обычно установленный браузер, в CI — тот, что поставил workflow.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
chrome="${CHROME:-/opt/pw-browsers/chromium}"

if [[ ! -x "$chrome" ]]; then
  echo "Не нашёл Chromium: $chrome. Укажите путь через CHROME=…" >&2
  exit 1
fi

python3 "$here/build_manual.py"
CHROME="$chrome" python3 "$here/check_overflow.py"

"$chrome" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
  --print-to-pdf="$root/docs/instrukciya/QPVPN-instrukciya.pdf" \
  --virtual-time-budget=6000 \
  "file://$root/docs/instrukciya/index.html" 2>/dev/null

echo "Готово: docs/instrukciya/QPVPN-instrukciya.pdf"
