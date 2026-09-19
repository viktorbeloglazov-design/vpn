#!/bin/bash
# Удаление службы kupibasvpnd. С ключом --purge удаляет и настройки.
set -euo pipefail

LABEL="com.kupibas.vpn.helper"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
HELPER_DIR="/usr/local/libexec/kupibas-vpn"
STATE_DIR="/Library/Application Support/KupibasVPN"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами администратора: sudo $0" >&2
    exit 1
fi

echo "==> Выключаю туннель, если он поднят"
if [ -f /var/run/kupibas-vpn/kb0.conf ]; then
    PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" wg-quick down /var/run/kupibas-vpn/kb0.conf 2>/dev/null || true
fi

echo "==> Снимаю службу"
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HELPER_DIR"
rm -rf /var/run/kupibas-vpn

if [ "${1:-}" = "--purge" ]; then
    echo "==> Удаляю настройки"
    rm -rf "$STATE_DIR"
    rm -f /var/log/kupibas-vpn.log /var/log/kupibas-vpn.stderr.log /var/log/kupibas-vpn.stdout.log
fi

echo "Готово."
