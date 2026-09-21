#!/bin/bash
# Второй вход на том же сервере — порт 443.
#
#   sudo bash port443.sh          # включить
#   sudo bash port443.sh --stop   # выключить
#
# Операторы, которые замедляют VPN, обычно смотрят и на номер порта: трафик
# на случайный высокий порт подозрителен сам по себе, а на 443 — нет, через
# него ходит весь обычный интернет. Иногда одного этого хватает.
#
# Ключи менять не нужно: пакеты с 443 просто перебрасываются на тот порт,
# который туннель уже слушает. В приложении меняется одна строка — адрес.
set -euo pipefail

WG_DIR="/etc/wireguard"
STATE="/etc/qpvpn-port443.conf"
NEW_PORT="${NEW_PORT:-443}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $*" >&2
    exit 1
fi

current_port() {
    # Порт берём из настроек туннеля: и у обычного WireGuard, и у Amnezia
    # он записан одинаково.
    for file in "$WG_DIR"/*.conf /opt/amnezia/awg/wg0.conf; do
        [ -f "$file" ] || continue
        awk -F'= *' '/^ *ListenPort/ {print $2; exit}' "$file" && return
    done
    # Не нашли в файлах — спросим у самого туннеля.
    if command -v awg >/dev/null 2>&1; then awg show 2>/dev/null | awk '/listening port/ {print $3; exit}'; fi
    if command -v wg >/dev/null 2>&1; then wg show 2>/dev/null | awk '/listening port/ {print $3; exit}'; fi
}

if [ "${1:-}" = "--stop" ]; then
    if [ -f "$STATE" ]; then
        # shellcheck disable=SC1090
        . "$STATE"
        iptables -t nat -D PREROUTING -p udp --dport "$NEW" -j REDIRECT --to-port "$OLD" 2>/dev/null || true
        iptables -D INPUT -p udp --dport "$NEW" -j ACCEPT 2>/dev/null || true
        rm -f "$STATE"
        echo "Вход на порту $NEW выключен."
    else
        echo "Вход на 443 и не был включён."
    fi
    exit 0
fi

PORT="$(current_port | tr -d '[:space:]')"
if [ -z "$PORT" ]; then
    echo "Не удалось понять, какой порт слушает туннель." >&2
    echo "Задайте вручную: PORT=31984 sudo bash $0" >&2
    exit 1
fi

if [ "$PORT" = "$NEW_PORT" ]; then
    echo "Туннель и так слушает $NEW_PORT — делать нечего."
    exit 0
fi

echo "==> Туннель слушает порт $PORT, добавляю вход на $NEW_PORT"
iptables -t nat -C PREROUTING -p udp --dport "$NEW_PORT" -j REDIRECT --to-port "$PORT" 2>/dev/null \
    || iptables -t nat -A PREROUTING -p udp --dport "$NEW_PORT" -j REDIRECT --to-port "$PORT"
iptables -C INPUT -p udp --dport "$NEW_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p udp --dport "$NEW_PORT" -j ACCEPT

cat > "$STATE" <<STATEFILE
NEW=$NEW_PORT
OLD=$PORT
STATEFILE

if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
fi

PUBLIC_IP="$(curl -4 -s --max-time 10 https://ifconfig.me || true)"
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="адрес_сервера"

echo
echo "================ вход на 443 готов ================"
echo "Старый вход работает по-прежнему: $PUBLIC_IP:$PORT"
echo "Новый:                            $PUBLIC_IP:$NEW_PORT"
echo
echo "В приложении: «Профиль» → «Запасной вход» → впишите"
echo "    $PUBLIC_IP:$NEW_PORT"
echo "Ключ менять не нужно."
echo
echo "Выключить:  sudo bash $0 --stop"
echo "==================================================="
