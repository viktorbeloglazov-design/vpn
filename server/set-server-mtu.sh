#!/bin/bash
# Задаёт MTU интерфейса wg0 на сервере.
#
#   sudo bash set-server-mtu.sh 1280
#
# Зачем: MTU в конфиге клиента ограничивает только пакеты клиент → сервер.
# Размер пакетов сервер → клиент определяется MTU интерфейса на сервере.
# Если путь до клиента узкий, обратный трафик теряется: рукопожатие проходит,
# данные не доходят. Лечится уменьшением MTU именно здесь.
set -euo pipefail

WG_DIR="/etc/wireguard"
CONF="$WG_DIR/wg0.conf"
MTU="${1:-}"

if ! [[ "$MTU" =~ ^[0-9]+$ ]] || [ "$MTU" -lt 576 ] || [ "$MTU" -gt 1500 ]; then
    echo "Укажите MTU числом от 576 до 1500: sudo bash $0 1280" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $MTU" >&2
    exit 1
fi

[ -f "$CONF" ] || { echo "Нет $CONF" >&2; exit 1; }

cp "$CONF" "$CONF.bak"

# MTU должен стоять в секции [Interface] — ставим сразу после её заголовка,
# предварительно убрав прежнее значение, чтобы не появилось двух строк.
awk -v mtu="$MTU" '
    /^\[Interface\]/ { print; print "MTU = " mtu; iface = 1; next }
    /^\[Peer\]/      { iface = 0 }
    iface && /^MTU[[:space:]]*=/ { next }
    { print }
' "$CONF.bak" > "$CONF.tmp"

if ! grep -q "^MTU = $MTU" "$CONF.tmp"; then
    echo "Не удалось записать MTU — конфиг не изменён." >&2
    rm -f "$CONF.tmp"
    exit 1
fi

mv "$CONF.tmp" "$CONF"
chmod 0600 "$CONF"

systemctl restart wg-quick@wg0

ACTUAL="$(ip -o link show wg0 2>/dev/null | sed -n 's/.* mtu \([0-9]*\) .*/\1/p')"
echo "MTU интерфейса wg0 на сервере: ${ACTUAL:-не определён}"
if [ "$ACTUAL" = "$MTU" ]; then
    echo "Готово. Клиентам ничего менять не нужно — их конфиги не затронуты."
else
    echo "Внимание: ожидался $MTU. Проверьте systemctl status wg-quick@wg0" >&2
fi
echo "Резервная копия: $CONF.bak"
