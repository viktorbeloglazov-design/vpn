#!/usr/bin/env bash
#
# Проверка check_ru.sh на подставных adb и aapt2: скрипт должен пройти
# целиком, посчитать доли и выдать верный вердикт в трёх случаях —
# переведено всё, переведена только рамка системы, не переведено ничего.
#
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../check_ru.sh"
mock="$here/mock"
work="$(mktemp -d "${TMPDIR:-/tmp}/check_ru_test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0

check() {
    if [ "$2" = "$3" ]; then
        printf '  ok   %s\n' "$1"
    else
        printf '  ФАЙЛ %s: ожидалось «%s», получено «%s»\n' "$1" "$3" "$2"
        failures=$((failures + 1))
    fi
}

contains() {
    if grep -qF "$2" "$1"; then
        printf '  ok   отчёт содержит «%s»\n' "$2"
    else
        printf '  ФАЙЛ отчёт не содержит «%s»\n' "$2"
        failures=$((failures + 1))
    fi
}

# Покрытие рамки системы из строки «- рамка системы (`framework-res`): покрытие 80.0%»
coverage_of() {
    grep '^- рамка системы' "$1" | head -1 | sed -e 's/%$//' -e 's/.*покрытие //'
}

run_case() {
    profile="$1"
    out="$work/$profile.md"
    MOCK_PROFILE="$profile" \
    ADB="$mock/adb" AAPT2="$mock/aapt2" \
        "$script" --out "$out" --work "$work/w-$profile" > "$work/$profile.log" 2>&1
    printf '%s\n' "$out"
}

printf 'Сценарий «переведено всё»\n'
out="$(run_case full)"
verdict="$(grep -o 'Русские ресурсы в ключевых пакетах: [^*]*' "$out" | head -1 | awk '{ print $NF }')"
check "вердикт" "$verdict" "ДА"
contains "$out" "framework-res"
contains "$out" "com.chj.hvac"

printf 'Сценарий «переведена только рамка системы»\n'
out="$(run_case mixed)"
verdict="$(grep -o 'Русские ресурсы в ключевых пакетах: [^*]*' "$out" | head -1 | awk '{ print $NF }')"
check "вердикт" "$verdict" "ЧАСТИЧНО"
check "покрытие рамки" "$(coverage_of "$out")" "80.0"
contains "$out" "экраны машины — по-прежнему по-китайски"

printf 'Сценарий «русского нет»\n'
out="$(run_case none)"
verdict="$(grep -o 'Русские ресурсы в ключевых пакетах: [^*]*' "$out" | head -1 | awk '{ print $NF }')"
check "вердикт" "$verdict" "НЕТ"
check "покрытие рамки" "$(coverage_of "$out")" "0.0"

printf 'Скрипт ничего не меняет в машине\n'
forbidden="$(grep -vE '^[[:space:]]*#' "$script" | grep -nE '(settings put|setprop|am (start|broadcast)|pm (install|uninstall|grant|disable)|mount |rm -rf /system)' || true)"
check "запрещённых команд нет" "${forbidden:-нет}" "нет"

if [ "$failures" -gt 0 ]; then
    printf '\nНе сошлось: %s\n' "$failures"
    exit 1
fi
printf '\nВсё сошлось\n'
