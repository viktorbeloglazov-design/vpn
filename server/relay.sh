#!/bin/bash
# Запасной вход в туннель — на российском сервере.
#
#   sudo bash relay.sh 77.240.39.23:31984      # включить
#   sudo bash relay.sh --stop                  # выключить
#
# Когда оператор отключает мобильный интернет, наружу уходят только пакеты
# к разрешённым адресам. Казахстанский сервер в разрешённые не входит, и
# туннель не поднимается вовсе. Но если фильтр пропускает российские адреса
# целиком, а не только список сервисов, то помогает цепочка: телефон шлёт
# на российский адрес, а тот пересылает дальше.
#
# Ключи при этом те же самые: узел ничего не расшифровывает, он только
# перебрасывает пакеты. Менять в приложении нужно один адрес входа.
set -euo pipefail

PORT="${PORT:-31984}"
STATE="/etc/qpvpn-relay.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $*" >&2
    exit 1
fi

wan_interface() {
    ip route show default | awk '/default/ {print $5; exit}'
}

if [ "${1:-}" = "--stop" ]; then
    if [ -f "$STATE" ]; then
        # shellcheck disable=SC1090
        . "$STATE"
        iptables -t nat -D PREROUTING -p udp --dport "$LISTEN_PORT" -j DNAT \
            --to-destination "$TARGET" 2>/dev/null || true
        iptables -t nat -D POSTROUTING -p udp -d "${TARGET%:*}" --dport "${TARGET#*:}" \
            -j MASQUERADE 2>/dev/null || true
        iptables -D INPUT -p udp --dport "$LISTEN_PORT" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p udp -d "${TARGET%:*}" --dport "${TARGET#*:}" -j ACCEPT 2>/dev/null || true
        rm -f "$STATE"
        echo "Запасной вход выключен."
    else
        echo "Запасной вход и не был включён."
    fi
    exit 0
fi

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ "${TARGET#*:}" = "$TARGET" ]; then
    echo "Укажите, куда пересылать: sudo bash $0 адрес_сервера:порт" >&2
    echo "Например: sudo bash $0 77.240.39.23:31984" >&2
    exit 1
fi

TARGET_HOST="${TARGET%:*}"
TARGET_PORT="${TARGET#*:}"
LISTEN_PORT="$PORT"

echo "==> Включаю пересылку пакетов"
cat > /etc/sysctl.d/99-qpvpn-relay.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system >/dev/null

WAN="$(wan_interface)"
PUBLIC_IP="$(curl -4 -s --max-time 10 https://ifconfig.me || true)"
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="$(ip -4 addr show "$WAN" | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"

echo "==> Пробрасываю UDP :$LISTEN_PORT → $TARGET"
# DNAT переписывает адрес получателя, MASQUERADE — адрес отправителя,
# чтобы ответы вернулись тем же путём, а не мимо узла.
iptables -t nat -C PREROUTING -p udp --dport "$LISTEN_PORT" -j DNAT --to-destination "$TARGET" 2>/dev/null \
    || iptables -t nat -A PREROUTING -p udp --dport "$LISTEN_PORT" -j DNAT --to-destination "$TARGET"
iptables -t nat -C POSTROUTING -p udp -d "$TARGET_HOST" --dport "$TARGET_PORT" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -p udp -d "$TARGET_HOST" --dport "$TARGET_PORT" -j MASQUERADE
iptables -C INPUT -p udp --dport "$LISTEN_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p udp --dport "$LISTEN_PORT" -j ACCEPT
iptables -C FORWARD -p udp -d "$TARGET_HOST" --dport "$TARGET_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I FORWARD -p udp -d "$TARGET_HOST" --dport "$TARGET_PORT" -j ACCEPT

cat > "$STATE" <<STATEFILE
LISTEN_PORT=$LISTEN_PORT
TARGET=$TARGET
STATEFILE

# Правила живут в памяти: после перезагрузки их надо вернуть.
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
fi

echo
echo "================ запасной вход готов ================"
echo "Адрес входа:  $PUBLIC_IP:$LISTEN_PORT"
echo "Пересылает в: $TARGET"
echo
echo "В приложении QP VPN: вкладка «Профиль» → «Запасной вход» → впишите"
echo "    $PUBLIC_IP:$LISTEN_PORT"
echo "Ключ менять не нужно: узел ничего не расшифровывает, только пересылает."
echo
echo "Выключить:  sudo bash $0 --stop"
echo "====================================================="
