#!/bin/bash
# Полная уборка QP VPN с компьютера.
#
#   uninstall-mac.sh [--keep-settings] [путь к .app] [ещё путь] ...
#
# Запускается приложением через системное окно с паролем — человеку
# терминал не нужен. Без аргументов убирает службу и остатки, пути
# приложений передаются списком.
#
# --keep-settings: оставить ключ и настройки. Нужно, когда убирают
# лишние копии, а пользоваться программой собираются дальше.
set -uo pipefail

LABEL="com.kupibas.vpn.helper"
BUNDLE_ID="com.kupibas.vpn"
HELPER_DIR="/usr/local/libexec/kupibas-vpn"
STATE_DIR="/Library/Application Support/KupibasVPN"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
RUNTIME_DIR="/var/run/kupibas-vpn"

KEEP_SETTINGS=0
APPS=()
for argument in "$@"; do
    case "$argument" in
        --keep-settings) KEEP_SETTINGS=1 ;;
        *) APPS+=("$argument") ;;
    esac
done

say() { echo "$*"; }

# ─────────────── 1. Остановить всё работающее ───────────────
#
# Программа живёт в строке меню и переживает закрытие окна. Пока старая
# копия в памяти, система будет показывать именно её, сколько новых
# ни поставь.
say "Останавливаю работающие копии"
pkill -f "/QPVPN.app/Contents/MacOS/QPVPN" 2>/dev/null || true
sleep 1
pkill -9 -f "/QPVPN.app/Contents/MacOS/QPVPN" 2>/dev/null || true

# ─────────────── 2. Снять службу ───────────────
say "Снимаю службу"
launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl disable "system/$LABEL" 2>/dev/null || true
launchctl enable "system/$LABEL" 2>/dev/null || true
pkill -f "$HELPER_DIR/kupibasvpnd" 2>/dev/null || true

# Туннель мог остаться поднятым — опускаем интерфейсы, которые завели мы.
if [ -d /var/run/amneziawg ]; then
    for name_file in /var/run/amneziawg/*.name; do
        [ -f "$name_file" ] || continue
        interface="$(cat "$name_file" 2>/dev/null || true)"
        [ -n "$interface" ] && ifconfig "$interface" down 2>/dev/null || true
    done
fi

rm -f "$PLIST"
rm -rf "$HELPER_DIR" "$RUNTIME_DIR" /var/run/amneziawg
rm -f /var/log/kupibas-vpn.log /var/log/kupibas-vpn-install.log

# ─────────────── 3. Удалить копии приложения ───────────────
#
# Удаляем только то, что и правда наше: путь должен оканчиваться на .app
# и внутри должен лежать наш опознавательный знак. Иначе опечатка в
# списке стоила бы человеку чужой программы.
removed=0
for app in ${APPS[@]+"${APPS[@]}"}; do
    case "$app" in
        *.app|*.app/) ;;
        *) say "Пропускаю (не приложение): $app"; continue ;;
    esac
    [ -d "$app" ] || continue

    found_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$app/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$found_id" != "$BUNDLE_ID" ]; then
        say "Пропускаю (чужая программа): $app"
        continue
    fi

    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$app/Contents/Info.plist" 2>/dev/null || echo "?")"
    rm -rf "$app" && say "Удалено: $app (версия $version)" && removed=$((removed + 1))
done

# Хвосты от неудачной замены при обновлении.
rm -rf /Applications/QPVPN.app.update "$HOME/Applications/QPVPN.app.update"

# ─────────────── 4. Настройки ───────────────
if [ "$KEEP_SETTINGS" -eq 1 ]; then
    say "Ключ и настройки оставлены"
else
    say "Удаляю настройки и ключ"
    rm -rf "$STATE_DIR" "/Library/Application Support/QPVPN"
    # Домашний каталог того, кто запустил программу, а не root.
    owner_home="${SUDO_USER:+/Users/$SUDO_USER}"
    owner_home="${owner_home:-$HOME}"
    rm -f "$owner_home/Library/Preferences/$BUNDLE_ID.plist"
    rm -rf "$owner_home/Library/Caches/$BUNDLE_ID"
    rm -rf "$owner_home/Library/Saved Application State/$BUNDLE_ID.savedState"
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
fi

# ─────────────── 5. Забыть удалённое ───────────────
#
# Система держит свой список установленных программ. Пока в нём остаётся
# запись об удалённой копии, она может открыть именно её — человек ставит
# новую версию, а запускается прежняя.
say "Обновляю список программ"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -kill -r -domain local -domain system -domain user >/dev/null 2>&1 || true
fi

say ""
say "Готово. Убрано копий приложения: $removed"
exit 0
