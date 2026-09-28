#!/usr/bin/env bash
# Ежедневная проверка выложенных сборок. Кладёт отчёт в docs/otchet/.
#
# Проверяется то, что видно снаружи, — ровно то, с чем имеет дело человек,
# который скачивает программу по постоянной ссылке:
#
#   * отвечает ли ссылка и не пустой ли файл;
#   * какая версия лежит рядом со сборкой;
#   * сходятся ли параметры маскировки с тем, что понимает служба;
#   * проходят ли проверки логики.
#
# Отчёт нужен, чтобы поломку замечала проверка, а не человек, у которого
# перестал работать VPN.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
today="$(date -u +%Y-%m-%d)"
out_dir="$root/docs/otchet"
out="$out_dir/$today.md"
mkdir -p "$out_dir"

base="https://github.com/viktorbeloglazov-design/vpn/releases/download/latest"
trouble=0

say() { printf '%s\n' "$1" >> "$out"; }

: > "$out"
say "# Отчёт за $today"
say ""
say "Проверка выложенных сборок. Время проверки — $(date -u '+%H:%M') UTC."
say ""
say "## Сборки"
say ""
say "| Программа | Версия | Ссылка | Размер |"
say "|---|---|---|---|"

check_build() {
    local title="$1" file="$2" version_file="$3" min_size="$4"

    local version size code
    version="$(curl -sS -L --max-time 60 -H 'Cache-Control: no-cache' \
        "$base/$version_file" 2>/dev/null | tr -d '[:space:]')"
    read -r code size < <(curl -sS -L --max-time 300 -o /dev/null \
        -w '%{http_code} %{size_download}' "$base/$file" 2>/dev/null || echo "000 0")

    local verdict="отвечает"
    if [ "$code" != "200" ]; then
        verdict="НЕ ОТВЕЧАЕТ ($code)"
        trouble=$((trouble + 1))
    elif [ "${size:-0}" -lt "$min_size" ]; then
        verdict="файл подозрительно мал"
        trouble=$((trouble + 1))
    fi
    if [ -z "$version" ]; then
        version="нет номера"
        trouble=$((trouble + 1))
    fi

    say "| $title | $version | $verdict | $(numfmt --to=iec "${size:-0}" 2>/dev/null || echo "${size:-0}") |"
}

check_build "Android" "QPVPN-android.apk"   "android-version.txt"  5000000
check_build "Windows" "QPVPN-windows.zip"   "windows-version.txt" 20000000
check_build "Mac"     "QPVPN-mac.dmg"       "mac-version.txt"      5000000
check_build "Инструкция" "QPVPN-instrukciya.pdf" "mac-version.txt" 100000

say ""
say "## Проверки"
say ""

run_check() {
    local title="$1"
    shift
    if "$@" > /tmp/otchet-check.log 2>&1; then
        say "- $title: в порядке"
    else
        say "- $title: **не прошла**"
        say ""
        say '```'
        tail -20 /tmp/otchet-check.log >> "$out"
        say '```'
        trouble=$((trouble + 1))
    fi
}

if command -v go >/dev/null 2>&1; then
    run_check "Параметры маскировки Windows" bash "$root/scripts/ci/check-masking.sh"
else
    say "- Параметры маскировки Windows: пропущена (нет go)"
fi

run_check "Описание выпуска" bash "$root/scripts/ci/check-opisanie.sh"

if command -v dotnet >/dev/null 2>&1; then
    run_check "Проверки логики Windows" dotnet test "$root/windows/tests" --nologo -v q
else
    say "- Проверки логики Windows: пропущена (нет dotnet)"
fi

if command -v swift >/dev/null 2>&1; then
    run_check "Проверки ядра Mac" swift test --package-path "$root"
else
    say "- Проверки ядра Mac: пропущена (нет swift)"
fi

# Инструкция собирается скриптом, а docs/instrukciya/index.html — его
# результат. Правка, внесённая прямо в index.html, живёт до следующей
# сборки и молча пропадает: PDF выкладывается заново и не меняется ни
# на байт. Поэтому пересобираем и смотрим, совпадает ли результат
# с тем, что лежит в репозитории.
check_manual() {
    command -v python3 >/dev/null 2>&1 || {
        say "- Инструкция: пропущена (нет python3)"
        return
    }

    local page="$root/docs/instrukciya/index.html"
    local before="/tmp/otchet-manual-before.html"
    cp "$page" "$before" 2>/dev/null || {
        say "- Инструкция: пропущена (нет файла)"
        return
    }

    python3 "$root/scripts/manual/build_manual.py" > /tmp/otchet-manual.log 2>&1 || {
        cp "$before" "$page"
        say "- Инструкция: **не собирается**"
        trouble=$((trouble + 1))
        return
    }

    # Сравниваем с тем, что лежало до пересборки. Иначе проверка слепа:
    # сборка сама затирает ручную правку, и сравнивать было бы не с чем.
    if cmp -s "$before" "$page"; then
        say "- Инструкция: собирается из скрипта, расхождений нет"
    else
        cp "$before" "$page"
        say "- Инструкция: **правки не дойдут до PDF**"
        say ""
        say "  Файл docs/instrukciya/index.html правили руками. Он собирается"
        say "  скриптом scripts/manual/build_manual.py и перезаписывается —"
        say "  правки нужно перенести в скрипт, иначе они пропадут."
        trouble=$((trouble + 1))
    fi
}

check_manual

# Сверка генератора говорит только про репозиторий. Выложенная
# инструкция может отстать от него: так и случилось — PDF обновлялся
# вовремя, а правок в нём не было. Сверяем текст скачанного файла
# с текстом, который собирается из кода сейчас.
if [ -x "${CHROME:-/opt/pw-browsers/chromium}" ]; then
    run_check "Выложенная инструкция" \
        env CHROME="${CHROME:-/opt/pw-browsers/chromium}" \
        python3 "$root/scripts/manual/check_published.py"
    git -C "$root" checkout -- docs/instrukciya 2>/dev/null || true
else
    say "- Выложенная инструкция: пропущена (нет браузера)"
fi

say ""
say "## Итог"
say ""
if [ "$trouble" -eq 0 ]; then
    say "Всё на месте: ссылки отвечают, версии выложены, проверки проходят."
else
    say "**Неполадок: $trouble.** Разобраться и выпустить исправление."
fi

echo "Отчёт: $out"
cat "$out"
exit 0
