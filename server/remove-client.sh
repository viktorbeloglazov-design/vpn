#!/bin/bash
# Удаляет клиента WireGuard: убирает его [Peer] из wg0.conf и стирает ключи.
# Нужен, если устройство потеряно или конфиг куда-то утёк.
#
#   sudo bash remove-client.sh mac
#
# Изменения применяются через wg syncconf: остальные клиенты не отключаются.
set -euo pipefail

WG_DIR="/etc/wireguard"
NAME="${1:-}"

if [ -z "$NAME" ]; then
    echo "Укажите имя клиента: sudo bash $0 mac" >&2
    echo "Список заведённых клиентов:" >&2
    ls -1 "$WG_DIR/clients" 2>/dev/null | sed 's/^/  /' >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $NAME" >&2
    exit 1
fi

CONF="$WG_DIR/wg0.conf"
[ -f "$CONF" ] || { echo "Нет $CONF" >&2; exit 1; }

CLIENT_DIR="$WG_DIR/clients/$NAME"
PUBKEY=""
[ -f "$CLIENT_DIR/public.key" ] && PUBKEY="$(cat "$CLIENT_DIR/public.key")"

if ! grep -q "^# client: $NAME\$" "$CONF" && [ -z "$PUBKEY" ]; then
    echo "Клиент «$NAME» не найден ни в $CONF, ни в $WG_DIR/clients." >&2
    exit 1
fi

cp "$CONF" "$CONF.bak"

# Блок клиента — строка «# client: <имя>» и четыре строки за ней.
awk -v name="$NAME" '
    $0 == "# client: " name { skip = 5 }
    skip > 0 { skip--; next }
    { print }
' "$CONF.bak" > "$CONF.tmp"

# Страховка: в остатке не должно быть публичного ключа удаляемого клиента.
if [ -n "$PUBKEY" ] && grep -qF "$PUBKEY" "$CONF.tmp"; then
    echo "Публичный ключ клиента «$NAME» остался в конфиге — удаление отменено." >&2
    echo "Проверьте $CONF вручную, резервная копия: $CONF.bak" >&2
    rm -f "$CONF.tmp"
    exit 1
fi

if ! grep -q '^\[Interface\]' "$CONF.tmp"; then
    echo "После удаления конфиг повреждён — откатываю." >&2
    rm -f "$CONF.tmp"
    exit 1
fi

mv "$CONF.tmp" "$CONF"
chmod 0600 "$CONF"
rm -rf "$CLIENT_DIR"

if wg show wg0 >/dev/null 2>&1; then
    wg syncconf wg0 <(wg-quick strip wg0)
else
    systemctl restart wg-quick@wg0
fi

echo "Клиент «$NAME» удалён, его ключи больше не пускают на сервер."
echo "Резервная копия прежнего конфига: $CONF.bak"
echo "Осталось пиров: $(wg show wg0 peers 2>/dev/null | wc -l)"
