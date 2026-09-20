#!/usr/bin/env bash
#
# adb_doctor.sh — почему компьютер не видит машину по adb.
#
# ТОЛЬКО ЧТЕНИЕ. В машине ничего не меняется: скрипт перезапускает
# службу adb на самом компьютере и смотрит, что она видит.
#
# Запуск:
#   ./adb_doctor.sh                 # проверка по USB
#   ./adb_doctor.sh --ip 192.168.1.50   # ещё и попытка связаться по Wi-Fi
#
set -euo pipefail

ADB="${ADB:-adb}"
IP=""

while [ $# -gt 0 ]; do
    case "$1" in
        --ip) IP="${2:-}"; shift 2 ;;
        -h|--help)
            printf 'adb_doctor.sh [--ip АДРЕС_МАШИНЫ_В_WIFI]\n'
            exit 0
            ;;
        *) printf 'Непонятный ключ: %s\n' "$1" >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

step "Программа adb"
if ! command -v "$ADB" >/dev/null 2>&1; then
    say "adb не найден."
    say "Поставьте Android Platform Tools:"
    say "  brew install --cask android-platform-tools"
    say "Если Homebrew не отвечает — скачайте архив platform-tools вручную"
    say "и запустите скрипт так:  ADB=~/platform-tools/adb $0"
    exit 1
fi
say "$("$ADB" version | head -1)"
say "путь: $(command -v "$ADB")"

step "Перезапускаю службу adb на компьютере"
"$ADB" kill-server >/dev/null 2>&1 || true
"$ADB" start-server >/dev/null 2>&1 || true
say "готово"

step "Кого видит adb"
LIST="$("$ADB" devices -l 2>/dev/null | tr -d '\r' | awk 'NR > 1 && NF > 0')"
if [ -n "$LIST" ]; then
    printf '%s\n' "$LIST"
else
    say "ничего"
fi

READY="$(printf '%s\n' "$LIST" | awk '$2 == "device" { print $1 }' | head -1)"
UNAUTH="$(printf '%s\n' "$LIST" | awk '$2 == "unauthorized" { print $1 }' | head -1)"

if [ -n "$UNAUTH" ]; then
    step "Машина видна, но не разрешена"
    say "На экране автомобиля должен появиться запрос «Разрешить отладку по USB»."
    say "Нажмите «Разрешить» (и галочку «всегда»), затем запустите скрипт снова."
    exit 1
fi

if [ -z "$READY" ] && [ "$(uname -s)" = "Darwin" ]; then
    step "Что видит сам Mac на шине USB"
    USB="$(system_profiler SPUSBDataType 2>/dev/null | grep -iE 'product id|vendor id|manufacturer|serial number|speed' | head -40 || true)"
    if [ -n "$USB" ]; then
        printf '%s\n' "$USB"
        say ""
        say "Если в списке нет ничего похожего на автомобиль — до отладки дело не дошло:"
        say "кабель только для зарядки, не тот порт или машина не отдаёт USB-устройство."
    else
        say "Mac не показал ни одного устройства USB."
    fi
fi

if [ -z "$READY" ] && [ -n "$IP" ]; then
    step "Пробую по Wi-Fi: $IP:5555"
    "$ADB" connect "$IP:5555" 2>&1 | tr -d '\r' | head -3 || true
    LIST="$("$ADB" devices -l 2>/dev/null | tr -d '\r' | awk 'NR > 1 && NF > 0')"
    printf '%s\n' "${LIST:-ничего}"
    READY="$(printf '%s\n' "$LIST" | awk '$2 == "device" { print $1 }' | head -1)"
fi

if [ -z "$READY" ]; then
    step "Машина недоступна. Что проверить по порядку"
    cat <<'HINTS'
1. Кабель. Нужен кабель с данными, а не только зарядный. Проверьте тот же
   кабель на телефоне: если телефон виден в adb devices — кабель годный.
2. Порт. В L9 несколько портов USB; часть из них только питание.
   Пробуйте порт в переднем подлокотнике и порты в консоли по очереди.
3. Отладка в машине. В Li OS её включают в инженерном меню прошивки.
   Обычный андроидовский путь — «Настройки → О системе» и несколько
   нажатий по номеру сборки — в фирменных прошивках часто закрыт.
4. Запрос на экране. Сразу после подключения на экране машины может
   появиться окно «Разрешить отладку по USB» — его легко пропустить.
5. Wi-Fi. Если знаете адрес машины в домашней сети, попробуйте:
     ./adb_doctor.sh --ip 192.168.X.X
   Сработает только если в прошивке уже открыт порт 5555.

Без adb проверить прошивку на русский язык невозможно: все сведения
о системе и копии приложений читаются только через него.
HINTS
    exit 1
fi

step "Связь есть: $READY"
say "модель:   $("$ADB" -s "$READY" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
say "сборка:   $("$ADB" -s "$READY" shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')"
say "Android:  $("$ADB" -s "$READY" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')"
say "язык:     $("$ADB" -s "$READY" shell getprop persist.sys.locale 2>/dev/null | tr -d '\r')"
say ""
say "Можно запускать проверку языка:"
say "  ./check_ru.sh --serial $READY"
