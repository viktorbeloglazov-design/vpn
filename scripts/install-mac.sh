#!/bin/bash
# Установка QP VPN одной командой.
#
#   curl -fsSL https://raw.githubusercontent.com/viktorbeloglazov-design/vpn/claude/mac-vpn-app-routes-7jv8o7/scripts/install-mac.sh | bash
#
# Смысл: файл, скачанный через браузер, macOS помечает как «из интернета»,
# и приложение без сертификата Apple после первого отказа перестаёт
# открываться вовсе — значок прыгает в Dock и гаснет. Скачивание из терминала
# такой метки не ставит, поэтому приложение запускается сразу и навсегда.
set -euo pipefail

REPO="viktorbeloglazov-design/vpn"
APP="/Applications/QPVPN.app"
WORK="$(mktemp -d)"
MOUNT="$WORK/mnt"

cleanup() {
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Ищу свежую сборку"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=20" \
    | grep -o "https://[^\"]*QPVPN-[0-9.]*\.dmg" | head -1)"
if [ -z "$URL" ]; then
    echo "Не нашёл образ приложения в релизах." >&2
    exit 1
fi
echo "    $(basename "$URL")"

echo "==> Скачиваю"
curl -fL --progress-bar -o "$WORK/app.dmg" "$URL"

echo "==> Распаковываю"
mkdir -p "$MOUNT"
hdiutil attach -nobrowse -quiet -mountpoint "$MOUNT" "$WORK/app.dmg"

if [ ! -d "$MOUNT/QPVPN.app" ]; then
    echo "В образе нет приложения." >&2
    exit 1
fi

if pgrep -f "QPVPN.app/Contents/MacOS/QPVPN" > /dev/null; then
    echo "==> Закрываю прошлую копию"
    pkill -f "QPVPN.app/Contents/MacOS/QPVPN" || true
    sleep 1
fi

echo "==> Ставлю в «Программы»"
rm -rf "$APP" "/Applications/KupibasVPN.app"
cp -R "$MOUNT/QPVPN.app" "$APP"
hdiutil detach "$MOUNT" -quiet
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Проверяю"
if [ ! -x "$APP/Contents/MacOS/QPVPN" ]; then
    echo "Приложение установилось неполностью." >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "?")"

echo "==> Открываю"
open "$APP"
sleep 4

if pgrep -f "QPVPN.app/Contents/MacOS/QPVPN" > /dev/null; then
    echo
    echo "Готово: QP VPN $VERSION установлен и запущен."
    echo "Дальше в окне приложения: «Установить службу» → пароль администратора."
else
    echo
    echo "Приложение установлено, но не открылось." >&2
    echo "Журнал запуска: ~/Library/Logs/QPVPN.log" >&2
    cat "$HOME/Library/Logs/QPVPN.log" 2>/dev/null | tail -10 >&2 || true
    exit 1
fi
