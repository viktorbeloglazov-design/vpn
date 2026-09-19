#!/bin/bash
# Диагностика подключения телефона к головному устройству автомобиля.
# Телефон должен быть подключён к компьютеру по adb (отладка по USB включена).
#   ./scripts/carlink-diag.sh          — разовая проверка
#   ./scripts/carlink-diag.sh --watch  — то же и дальше журнал в реальном времени
set -uo pipefail

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }

if ! command -v adb >/dev/null 2>&1; then
    bad "нет adb — поставьте platform-tools"
    exit 1
fi

DEVICES="$(adb devices | sed -n '2,$p' | grep -c "device$")"
if [ "$DEVICES" -eq 0 ]; then
    bad "телефон не виден по adb"
    exit 1
fi

echo "CarLink — диагностика"
echo
echo "Телефон:"
MODEL="$(adb shell getprop ro.product.model | tr -d '\r')"
BRAND="$(adb shell getprop ro.product.manufacturer | tr -d '\r')"
RELEASE="$(adb shell getprop ro.build.version.release | tr -d '\r')"
SDK="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
ok "$BRAND $MODEL, Android $RELEASE (API $SDK)"

echo
echo "Путь A — настоящий Android Auto:"
has_package() { adb shell pm list packages 2>/dev/null | tr -d '\r' | grep -qx "package:$1"; }

if has_package com.google.android.gms; then
    VERSION="$(adb shell dumpsys package com.google.android.gms | tr -d '\r' | grep -m1 versionName | cut -d= -f2)"
    ok "сервисы Google Play: $VERSION"
else
    bad "сервисов Google Play нет — настоящий Android Auto не запустится"
fi

if has_package com.android.vending; then ok "Play Маркет"; else warn "Play Маркета нет"; fi

if has_package com.google.android.projection.gearhead; then
    ok "Android Auto установлен"
else
    bad "Android Auto не установлен"
fi

echo
echo "Путь C — CarLink:"
if has_package kz.carlink; then
    ok "CarLink установлен"
else
    warn "CarLink не установлен: gradle assembleDebug && adb install -r ..."
fi

INJECTOR="$(adb shell settings get secure enabled_accessibility_services | tr -d '\r')"
case "$INJECTOR" in
    *kz.carlink*) ok "нажатия с экрана машины разрешены" ;;
    *) warn "служба нажатий выключена — нужна только для режима зеркала" ;;
esac

echo
echo "Провод:"
# Машина переводит телефон в режим аксессуара: в состоянии USB появляется accessory.
USB_STATE="$(adb shell getprop sys.usb.state | tr -d '\r')"
USB_CONFIG="$(adb shell getprop sys.usb.config | tr -d '\r')"
echo "  режим USB: $USB_STATE (настроен: $USB_CONFIG)"
case "$USB_STATE" in
    *accessory*) ok "телефон в режиме аксессуара — машина его видит" ;;
    *) warn "режима аксессуара нет: телефон сейчас не подключён к машине" ;;
esac

ACCESSORY="$(adb shell dumpsys usb 2>/dev/null | tr -d '\r' | grep -i -A4 "mCurrentAccessory" | head -6)"
if [ -n "$ACCESSORY" ]; then
    echo "  что представилось:"
    echo "$ACCESSORY" | sed 's/^/    /'
fi

echo
echo "Подсказка: журнал приложения целиком копируется кнопкой на главном экране."

if [ "${1:-}" = "--watch" ]; then
    echo
    echo "Слежу за журналом, Ctrl+C чтобы выйти."
    adb logcat -c
    adb logcat -s CarLink:I UsbDeviceManager:I UsbAccessory:I
fi
