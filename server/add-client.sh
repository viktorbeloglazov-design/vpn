#!/bin/bash
# Добавляет клиента к серверу WireGuard и печатает готовый конфиг для Kupibas VPN.
#
#   sudo bash add-client.sh mac
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_NET_V4="10.8.0"
NAME="${1:-mac}"
PORT="${PORT:-$(awk -F'= *' '/ListenPort/ {print $2; exit}' "$WG_DIR/wg0.conf")}"
DNS="${DNS:-1.1.1.1, 8.8.8.8}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $NAME" >&2
    exit 1
fi

if [ -z "${PUBLIC_IP:-}" ]; then
    PUBLIC_IP="$(curl -4 -s --max-time 10 https://ifconfig.me || true)"
fi
if [ -z "$PUBLIC_IP" ]; then
    echo "Не удалось определить публичный IP. Передайте его вручную: PUBLIC_IP=1.2.3.4 bash $0 $NAME" >&2
    exit 1
fi

umask 077
install -d -m 0700 "$WG_DIR/clients"

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
SERVER_PUBLIC="$(cat "$WG_DIR/server_public.key")"

# Следующий свободный адрес в подсети: считаем уже выданные.
if [ -f "$CLIENT_DIR/address" ]; then
    CLIENT_IP="$(cat "$CLIENT_DIR/address")"
else
    LAST="$(grep -ho "${WG_NET_V4}\.[0-9]\+" "$WG_DIR/wg0.conf" | awk -F. '{print $4}' | sort -n | tail -1)"
    [ -z "$LAST" ] && LAST=1
    CLIENT_IP="${WG_NET_V4}.$((LAST + 1))"
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
    systemctl restart wg-quick@wg0
fi

CONFIG="$CLIENT_DIR/$NAME.conf"
cat > "$CONFIG" <<CONF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = $CLIENT_IP/32
DNS = $DNS
MTU = 1420

[Peer]
PublicKey = $SERVER_PUBLIC
PresharedKey = $CLIENT_PSK
Endpoint = $PUBLIC_IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CONF
chmod 0600 "$CONFIG"

echo
echo "================ конфиг клиента «$NAME» ================"
cat "$CONFIG"
echo "========================================================"
echo
echo "Скопируйте текст выше и вставьте в Kupibas VPN: вкладка «Сервер» → «Вставить конфиг WireGuard…»."
echo "Файл также сохранён на сервере: $CONFIG"
if command -v qrencode >/dev/null 2>&1; then
    echo
    echo "QR-код (для телефона):"
    qrencode -t ansiutf8 < "$CONFIG"
fi
