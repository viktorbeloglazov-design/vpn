#!/bin/bash
# Установка службы kztunneld (нужны права root) и подготовка каталога настроек.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.kztunnel.helper"
HELPER_DIR="/usr/local/libexec/kztunnel"
STATE_DIR="/Library/Application Support/KZTunnel"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами администратора: sudo $0" >&2
    exit 1
fi

# Кому отдать права на каталог настроек: пользователю, который вызвал sudo.
ADMIN_USER="${SUDO_USER:-$(stat -f "%Su" /dev/console)}"

echo "==> Проверяю зависимости WireGuard"
MISSING=()
for tool in wg wg-quick wireguard-go; do
    if ! PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" command -v "$tool" >/dev/null 2>&1; then
        MISSING+=("$tool")
    fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Не найдены: ${MISSING[*]}" >&2
    echo "Установите их и повторите:" >&2
    echo "    brew install wireguard-tools wireguard-go" >&2
    exit 1
fi

BINARY=""
for candidate in "$ROOT/dist/kztunneld" "$ROOT/.build/release/kztunneld" "$ROOT/.build/arm64-apple-macosx/release/kztunneld" "$ROOT/.build/x86_64-apple-macosx/release/kztunneld"; do
    if [ -x "$candidate" ]; then BINARY="$candidate"; break; fi
done
if [ -z "$BINARY" ]; then
    echo "Не найден собранный kztunneld. Сначала выполните: ./scripts/build.sh" >&2
    exit 1
fi

echo "==> Останавливаю прошлую версию службы (если была)"
launchctl bootout "system/$LABEL" 2>/dev/null || true

echo "==> Ставлю демон в $HELPER_DIR"
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$BINARY" "$HELPER_DIR/kztunneld"

echo "==> Готовлю каталог настроек $STATE_DIR"
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
[ -f "$STATE_DIR/status.json" ] && chmod 0664 "$STATE_DIR/status.json" || true

echo "==> Устанавливаю launchd-службу"
install -m 0644 -o root -g wheel "$ROOT/launchd/$LABEL.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
launchctl enable "system/$LABEL"

sleep 2
echo
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    echo "Служба установлена и запущена (пользователь $ADMIN_USER может править настройки)."
else
    echo "Служба установлена, но не отвечает. Смотрите /var/log/kztunnel.log" >&2
fi
echo "Журнал: /var/log/kztunnel.log"
