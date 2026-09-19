#!/bin/bash
# Полный сброс: стирает всю настройку WireGuard и собирает её заново с нуля.
#
#   sudo bash reset-all.sh                       # 3 клиента, порт 51820, MTU 1280
#   sudo bash reset-all.sh --clients 40 --port 443
#
# Старая настройка сохраняется архивом в /root — ничего не теряется безвозвратно.
# Рядом должны лежать install-wg-kz.sh, add-client.sh и set-server-mtu.sh.
set -euo pipefail

PORT=51820
MTU=1280
COUNT=3
PREFIX="vpn"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)    PORT="$2"; shift 2 ;;
        --mtu)     MTU="$2"; shift 2 ;;
        --clients) COUNT="$2"; shift 2 ;;
        --prefix)  PREFIX="$2"; shift 2 ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $*" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in install-wg-kz.sh add-client.sh set-server-mtu.sh; do
    [ -f "$SCRIPT_DIR/$f" ] || { echo "Рядом со скриптом нет $f — сначала скачайте все скрипты." >&2; exit 1; }
done

echo "==> Сохраняю прежнюю настройку"
if [ -d /etc/wireguard ]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"
    tar czf "/root/wireguard-backup-$STAMP.tgz" -C / etc/wireguard 2>/dev/null || true
    echo "    архив: /root/wireguard-backup-$STAMP.tgz"
fi

echo "==> Останавливаю туннель и стираю старое"
systemctl stop wg-quick@wg0 >/dev/null 2>&1 || true
rm -rf /etc/wireguard

echo "==> Собираю сервер заново (порт $PORT, MTU $MTU)"
MTU="$MTU" bash "$SCRIPT_DIR/install-wg-kz.sh" --port "$PORT" --client "${PREFIX}1" >/dev/null

for i in $(seq 2 "$COUNT"); do
    MTU="$MTU" bash "$SCRIPT_DIR/add-client.sh" "${PREFIX}${i}" >/dev/null
done

bash "$SCRIPT_DIR/set-server-mtu.sh" "$MTU" >/dev/null

# Раскладываем конфиги туда, откуда их удобно забрать по scp.
HOME_USER="${SUDO_USER:-ubuntu}"
HOME_DIR="$(getent passwd "$HOME_USER" | cut -d: -f6)"
if [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ]; then
    # Убираем все прежние конфиги: их ключей на сервере больше нет, а перепутать легко.
    rm -f "$HOME_DIR"/*.conf
    for f in /etc/wireguard/clients/*/*.conf; do
        cp "$f" "$HOME_DIR/"
    done
    chown "$HOME_USER": "$HOME_DIR"/*.conf 2>/dev/null || true
fi

echo
echo "================= готово ================="
echo "Порт сервера:      $PORT"
echo "MTU (сервер и клиенты): $MTU"
echo "Клиентов создано:  $COUNT"
echo
echo "Конфиги лежат в $HOME_DIR:"
ls -1 "$HOME_DIR"/*.conf 2>/dev/null | sed 's/^/  /'
echo
grep -h "^Endpoint" /etc/wireguard/clients/*/*.conf | head -1 | sed 's/^/Проверка: /'
echo
echo "Забрать на компьютер:  scp $HOME_USER@<адрес сервера>:\"*.conf\" ~/Downloads/"
echo "QR-код для телефона:   sudo qrencode -t ansiutf8 < /etc/wireguard/clients/${PREFIX}2/${PREFIX}2.conf"
