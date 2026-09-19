#!/bin/bash
# Разворачивает WireGuard-сервер на VPS (Ubuntu 22.04/24.04, Debian 11/12).
# Запускать на казахстанском сервере: именно его IP увидят сайты.
#
#   sudo bash install-wg-kz.sh [--port 51820] [--client mac]
set -euo pipefail

PORT=51820
CLIENT_NAME="mac"
WG_NET_V4="10.8.0"
WG_DIR="/etc/wireguard"

while [ $# -gt 0 ]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --client) CLIENT_NAME="$2"; shift 2 ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0" >&2
    exit 1
fi

echo "==> Ставлю пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wireguard iptables qrencode curl >/dev/null

echo "==> Включаю форвардинг пакетов"
cat > /etc/sysctl.d/99-wireguard.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
sysctl --system >/dev/null

WAN_IF="$(ip route show default | awk '/default/ {print $5; exit}')"
PUBLIC_IP="$(curl -4 -s --max-time 10 https://ifconfig.me || true)"
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="$(ip -4 addr show "$WAN_IF" | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"

echo "==> Внешний интерфейс: $WAN_IF, публичный адрес: $PUBLIC_IP"

umask 077
install -d -m 0700 "$WG_DIR"

if [ ! -f "$WG_DIR/server_private.key" ]; then
    wg genkey > "$WG_DIR/server_private.key"
    wg pubkey < "$WG_DIR/server_private.key" > "$WG_DIR/server_public.key"
fi
SERVER_PRIVATE="$(cat "$WG_DIR/server_private.key")"

if [ ! -f "$WG_DIR/wg0.conf" ]; then
    cat > "$WG_DIR/wg0.conf" <<CONF
[Interface]
Address = ${WG_NET_V4}.1/24
ListenPort = ${PORT}
PrivateKey = ${SERVER_PRIVATE}
SaveConfig = false

PostUp = iptables -t nat -A POSTROUTING -s ${WG_NET_V4}.0/24 -o ${WAN_IF} -j MASQUERADE
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
PostUp = iptables -t mangle -A FORWARD -i wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -t nat -D POSTROUTING -s ${WG_NET_V4}.0/24 -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t mangle -D FORWARD -i wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
CONF
    chmod 0600 "$WG_DIR/wg0.conf"
fi

echo "==> Запускаю wg0"
systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
systemctl restart wg-quick@wg0

echo "==> Добавляю клиента «$CLIENT_NAME»"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_IP="$PUBLIC_IP" PORT="$PORT" bash "$SCRIPT_DIR/add-client.sh" "$CLIENT_NAME"
