#!/bin/bash
# Заводит сразу пачку клиентов WireGuard (например, 40 устройств) и складывает
# готовые конфиги в /etc/wireguard/clients/<имя>/<имя>.conf.
#
#   sudo bash add-clients-bulk.sh 40                 # device-01 … device-40
#   sudo bash add-clients-bulk.sh 40 --prefix office # office-01 … office-40
#   sudo bash add-clients-bulk.sh 40 --qr            # ещё и QR-коды для телефонов
#
# Один конфиг = одно устройство: у каждого клиента свой ключ, свой PresharedKey
# и свой адрес в туннеле. Один и тот же файл на нескольких устройствах работать
# не будет — они станут выбивать друг друга из туннеля.
#
# Ключи WireGuard бессрочные: пир действует, пока его [Peer] есть в wg0.conf.
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_NET_V4="10.8.0"
COUNT="${1:-40}"
shift || true

PREFIX="device"
WITH_QR=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --qr) WITH_QR=1; shift ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ]; then
    echo "Число клиентов должно быть положительным: bash $0 40" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $COUNT" >&2
    exit 1
fi

if [ ! -f "$WG_DIR/wg0.conf" ]; then
    echo "Нет $WG_DIR/wg0.conf — сначала разверните сервер: bash install-wg-kz.sh" >&2
    exit 1
fi

PORT="${PORT:-$(awk -F'= *' '/ListenPort/ {print $2; exit}' "$WG_DIR/wg0.conf")}"
DNS="${DNS:-1.1.1.1, 8.8.8.8}"
# 1420 подходит для обычной сети; за роутером с VPN или PPPoE ставьте MTU=1280.
MTU="${MTU:-1420}"

if [ -z "${PUBLIC_IP:-}" ]; then
    PUBLIC_IP="$(curl -4 -s --max-time 10 https://ifconfig.me || true)"
fi
if [ -z "$PUBLIC_IP" ]; then
    echo "Не удалось определить публичный IP. Передайте его вручную: PUBLIC_IP=1.2.3.4 bash $0 $COUNT" >&2
    exit 1
fi

# В /24 помещается 253 клиента: .1 занят сервером.
LAST="$(grep -ho "${WG_NET_V4}\.[0-9]\+" "$WG_DIR/wg0.conf" | awk -F. '{print $4}' | sort -n | tail -1)"
[ -z "$LAST" ] && LAST=1
if [ $((LAST + COUNT)) -gt 254 ]; then
    echo "В подсети ${WG_NET_V4}.0/24 не хватает адресов на $COUNT клиентов (занято до .$LAST)." >&2
    echo "Расширьте подсеть в $WG_DIR/wg0.conf, например до /23." >&2
    exit 1
fi

umask 077
install -d -m 0700 "$WG_DIR/clients"
SERVER_PUBLIC="$(cat "$WG_DIR/server_public.key")"
ADDED=0

for i in $(seq 1 "$COUNT"); do
    NAME="$(printf '%s-%02d' "$PREFIX" "$i")"
    CLIENT_DIR="$WG_DIR/clients/$NAME"
    install -d -m 0700 "$CLIENT_DIR"

    if [ ! -f "$CLIENT_DIR/private.key" ]; then
        wg genkey > "$CLIENT_DIR/private.key"
        wg pubkey < "$CLIENT_DIR/private.key" > "$CLIENT_DIR/public.key"
        wg genpsk > "$CLIENT_DIR/preshared.key"
    fi

    CLIENT_PRIVATE="$(cat "$CLIENT_DIR/private.key")"
    CLIENT_PUBLIC="$(cat "$CLIENT_DIR/public.key")"
    CLIENT_PSK="$(cat "$CLIENT_DIR/preshared.key")"

    if [ -f "$CLIENT_DIR/address" ]; then
        CLIENT_IP="$(cat "$CLIENT_DIR/address")"
    else
        LAST=$((LAST + 1))
        CLIENT_IP="${WG_NET_V4}.${LAST}"
        echo "$CLIENT_IP" > "$CLIENT_DIR/address"
    fi

    if ! grep -q "$CLIENT_PUBLIC" "$WG_DIR/wg0.conf"; then
        cat >> "$WG_DIR/wg0.conf" <<PEER

# client: $NAME
[Peer]
PublicKey = $CLIENT_PUBLIC
PresharedKey = $CLIENT_PSK
AllowedIPs = $CLIENT_IP/32
PEER
        ADDED=$((ADDED + 1))
    fi

    CONFIG="$CLIENT_DIR/$NAME.conf"
    cat > "$CONFIG" <<CONF
# $NAME
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = $CLIENT_IP/32
DNS = $DNS
MTU = $MTU

[Peer]
PublicKey = $SERVER_PUBLIC
PresharedKey = $CLIENT_PSK
Endpoint = $PUBLIC_IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CONF
    chmod 0600 "$CONFIG"
    echo "  $NAME  →  $CLIENT_IP  ($CONFIG)"
done

if [ "$ADDED" -gt 0 ]; then
    # syncconf применяет новых пиров, не разрывая уже поднятые туннели.
    if wg show wg0 >/dev/null 2>&1; then
        wg syncconf wg0 <(wg-quick strip wg0)
    else
        systemctl restart wg-quick@wg0
    fi
fi

echo
echo "Готово: клиентов в наличии — $COUNT, новых пиров добавлено — $ADDED."
echo "Конфиги: $WG_DIR/clients/<имя>/<имя>.conf (права 0600, копируйте по scp)."
echo "Ключи бессрочные: пир работает, пока его [Peer] есть в $WG_DIR/wg0.conf."

if [ "$WITH_QR" -eq 1 ]; then
    if command -v qrencode >/dev/null 2>&1; then
        for i in $(seq 1 "$COUNT"); do
            NAME="$(printf '%s-%02d' "$PREFIX" "$i")"
            echo
            echo "=== $NAME ==="
            qrencode -t ansiutf8 < "$WG_DIR/clients/$NAME/$NAME.conf"
        done
    else
        echo "qrencode не установлен: apt-get install -y qrencode" >&2
    fi
fi
