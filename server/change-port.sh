#!/bin/bash
# Меняет UDP-порт сервера WireGuard и обновляет Endpoint во всех конфигах клиентов.
#
#   sudo bash change-port.sh 443
#
# Зачем: часть провайдеров блокирует WireGuard на стандартном порту 51820.
# На 443 трафик выглядит как обычный HTTPS/QUIC и обычно проходит.
set -euo pipefail

WG_DIR="/etc/wireguard"
CONF="$WG_DIR/wg0.conf"
PORT="${1:-}"

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Укажите порт числом: sudo bash $0 443" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $PORT" >&2
    exit 1
fi

[ -f "$CONF" ] || { echo "Нет $CONF" >&2; exit 1; }

OLD_PORT="$(awk -F'= *' '/^ListenPort/ {print $2; exit}' "$CONF")"
if [ -z "$OLD_PORT" ]; then
    echo "В $CONF не найден ListenPort" >&2
    exit 1
fi

if [ "$OLD_PORT" = "$PORT" ]; then
    echo "Сервер уже слушает порт $PORT — менять нечего."
    exit 0
fi

# Порт не должен быть занят другой службой.
if ss -lun | awk '{print $5}' | grep -q ":$PORT\$"; then
    echo "Порт $PORT уже занят другой службой. Выберите другой." >&2
    exit 1
fi

cp "$CONF" "$CONF.bak"
sed -i "s/^ListenPort *=.*/ListenPort = $PORT/" "$CONF"

UPDATED=0
for f in "$WG_DIR"/clients/*/*.conf; do
    [ -f "$f" ] || continue
    sed -i "s/^\(Endpoint *= *[^:]*\):.*/\1:$PORT/" "$f"
    UPDATED=$((UPDATED + 1))
done

systemctl restart wg-quick@wg0

command -v ufw >/dev/null 2>&1 && ufw allow "$PORT"/udp >/dev/null 2>&1

echo "Порт сервера: $OLD_PORT → $PORT"
echo "Обновлено конфигов клиентов: $UPDATED"
echo "Резервная копия конфига сервера: $CONF.bak"
echo
echo "ВАЖНО: на устройствах нужно заново загрузить конфиги — в старых остался порт $OLD_PORT."
echo "Либо вручную исправьте в приложении строку Endpoint, поменяв $OLD_PORT на $PORT."
echo
ss -lun | grep ":$PORT" >/dev/null 2>&1 && echo "Сервер слушает UDP $PORT ✓" || echo "Внимание: порт $PORT не слушается, проверьте systemctl status wg-quick@wg0"
