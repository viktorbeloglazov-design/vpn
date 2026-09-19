#!/bin/bash
# Быстрая проверка: что установлено, что запущено, куда идёт трафик.
#   ./scripts/doctor.sh
set -uo pipefail

LABEL="com.kupibas.vpn.helper"
STATE_DIR="/Library/Application Support/KupibasVPN"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }

echo "Kupibas VPN — диагностика"
echo
echo "Зависимости:"
for tool in wg wg-quick wireguard-go; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool → $(command -v "$tool")"
    else
        bad "$tool не найден (brew install wireguard-tools wireguard-go)"
    fi
done

echo
echo "Служба:"
if [ -f "/Library/LaunchDaemons/$LABEL.plist" ]; then
    ok "launchd-служба установлена"
else
    bad "launchd-служба не установлена (sudo ./scripts/install.sh)"
fi
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    ok "служба загружена"
else
    bad "служба не загружена"
fi

echo
echo "Настройки:"
if [ -d "$STATE_DIR" ]; then
    ok "каталог: $(ls -ld "$STATE_DIR" | awk '{print $1, $3, $4}')"
else
    bad "каталог $STATE_DIR отсутствует"
fi
if [ -f "$STATE_DIR/status.json" ]; then
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$STATE_DIR/status.json" <<'PY'
import json, sys, time
with open(sys.argv[1]) as f:
    s = json.load(f)
age = time.time() - s.get("updatedAt", 0)
mark = "  \033[32m✓\033[0m" if age < 15 else "  \033[31m✗\033[0m"
print(f"{mark} статус: {s.get('state')} · режим: {s.get('mode')} · маршрутов: {s.get('routeCount')} · обновлён {age:.0f} с назад")
if s.get("message"):
    print(f"  \033[33m!\033[0m сообщение службы: {s['message']}")
PY
    else
        cat "$STATE_DIR/status.json"
    fi
else
    warn "status.json ещё не создан — служба не запускалась"
fi

echo
echo "Туннель:"
if ifconfig kb0 >/dev/null 2>&1 || [ -f /var/run/wireguard/kb0.name ]; then
    REAL="$(cat /var/run/wireguard/kb0.name 2>/dev/null || echo kb0)"
    ok "интерфейс: $REAL"
    if [ "$(id -u)" -eq 0 ]; then
        wg show kb0 2>/dev/null | sed 's/^/    /'
    else
        warn "для вывода wg show запустите: sudo ./scripts/doctor.sh"
    fi
else
    warn "туннель не поднят"
fi

echo
echo "Маршрутизация:"
DEF="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')"
echo "  маршрут по умолчанию → ${DEF:-неизвестно}"
for host in ipinfo.io kaspi.kz ozon.ru; do
    IFACE="$(route -n get "$host" 2>/dev/null | awk '/interface:/ {print $2}')"
    printf "  %-12s → %s\n" "$host" "${IFACE:-нет маршрута}"
done

echo
echo "Внешний адрес:"
IPJSON="$(curl -s --max-time 10 https://ipinfo.io/json || true)"
if [ -n "$IPJSON" ]; then
    echo "$IPJSON" | tr -d '{}"' | tr ',' '\n' | grep -E '^\s*(ip|city|country|org)' | sed 's/^/  /'
else
    warn "не удалось определить внешний IP"
fi

echo
echo "Последние записи журнала:"
tail -5 /var/log/kupibas-vpn.log 2>/dev/null | sed 's/^/  /' || warn "журнал пуст"
