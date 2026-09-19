#!/bin/bash
# Установка службы Kupibas VPN из бандла приложения.
# Этот скрипт лежит внутри KupibasVPN.app и запускается самим приложением
# с правами администратора. Ключ --uninstall снимает службу.
set -euo pipefail

LABEL="com.kupibas.vpn.helper"
HELPER_DIR="/usr/local/libexec/kupibas-vpn"
STATE_DIR="/Library/Application Support/KupibasVPN"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
RUNTIME_DIR="/var/run/kupibas-vpn"

RESOURCES="$(cd "$(dirname "$0")" && pwd)"
CONTENTS="$(cd "$RESOURCES/.." 2>/dev/null && pwd || echo "$RESOURCES")"
HELPERS="$CONTENTS/Library/Helpers"

if [ "$(id -u)" -ne 0 ]; then
    echo "Нужны права администратора." >&2
    exit 1
fi

stop_tunnel() {
    if [ -f "$RUNTIME_DIR/kb0.conf" ]; then
        PATH="$HELPER_DIR:/opt/homebrew/bin:/usr/local/bin:$PATH" \
            wg-quick down "$RUNTIME_DIR/kb0.conf" >/dev/null 2>&1 || true
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    stop_tunnel
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$HELPER_DIR" "$RUNTIME_DIR"
    echo "Служба удалена. Настройки сохранены в $STATE_DIR"
    exit 0
fi

if [ ! -x "$HELPERS/kupibasvpnd" ]; then
    echo "В бандле приложения нет служебного файла kupibasvpnd." >&2
    exit 1
fi

echo "Останавливаю прошлую версию службы"
stop_tunnel
launchctl bootout "system/$LABEL" 2>/dev/null || true

echo "Ставлю файлы службы"
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$HELPERS/kupibasvpnd" "$HELPER_DIR/kupibasvpnd"
for tool in wireguard-go wg wg-quick; do
    if [ -f "$HELPERS/$tool" ]; then
        install -m 0755 "$HELPERS/$tool" "$HELPER_DIR/$tool"
    fi
done

# Утилиты WireGuard: либо вложены в приложение, либо стоят из Homebrew.
MISSING=()
for tool in wireguard-go wg wg-quick; do
    if [ ! -x "$HELPER_DIR/$tool" ] \
        && ! PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" command -v "$tool" >/dev/null 2>&1; then
        MISSING+=("$tool")
    fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Не хватает утилит WireGuard: ${MISSING[*]}" >&2
    echo "Установите их командой: brew install wireguard-tools wireguard-go" >&2
    exit 1
fi

echo "Готовлю каталог настроек"
install -d -m 0770 -o root -g staff "$STATE_DIR"
if [ ! -f "$STATE_DIR/config.json" ]; then
    cat > "$STATE_DIR/config.json" <<'JSON'
{
  "version": 1,
  "enabled": false,
  "mode": "full",
  "server": {
    "name": "KZ",
    "endpoint": "",
    "publicKey": "",
    "presharedKey": "",
    "privateKey": "",
    "addresses": [],
    "dns": [],
    "mtu": 1420,
    "persistentKeepalive": 25
  },
  "rules": [],
  "options": {
    "useTunnelDNS": true,
    "disableIPv6": true,
    "reresolveMinutes": 5,
    "autoReconnect": true
  }
}
JSON
fi
chown root:staff "$STATE_DIR/config.json"
chmod 0660 "$STATE_DIR/config.json"

echo "Регистрирую службу в системе"
install -m 0644 -o root -g wheel "$RESOURCES/$LABEL.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
launchctl enable "system/$LABEL"

sleep 2
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    echo "Служба установлена и запущена."
else
    echo "Служба установлена, но не отвечает. Журнал: /var/log/kupibas-vpn.log" >&2
    exit 1
fi
