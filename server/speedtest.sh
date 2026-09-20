#!/bin/bash
# Замер честной скорости до вашего сервера — без сайтов посередине.
#
#   sudo bash speedtest.sh          # включить замер (порт 5201)
#   sudo bash speedtest.sh --stop   # выключить, когда закончили
#
# Сайты меряют дорогу до себя, а не канал сервера: между вами и сайтом
# ещё полмира. iperf3 меряет ровно то, что нужно — сколько тянет сам
# сервер и путь до него. Если здесь скорость высокая, а в приложении
# низкая — виноват не сервер.
set -euo pipefail

PORT="${PORT:-5201}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0" >&2
    exit 1
fi

if [ "${1:-}" = "--stop" ]; then
    systemctl stop iperf3-qpvpn 2>/dev/null || true
    systemctl disable iperf3-qpvpn 2>/dev/null || true
    rm -f /etc/systemd/system/iperf3-qpvpn.service
    systemctl daemon-reload
    iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
    echo "Замер выключен, порт $PORT закрыт."
    exit 0
fi

if ! command -v iperf3 >/dev/null 2>&1; then
    echo "==> Ставлю iperf3"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq iperf3 >/dev/null
fi

PUBLIC_IP="$(curl -4 -s --max-time 10 https://ifconfig.me || true)"
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="адрес_сервера"

cat > /etc/systemd/system/iperf3-qpvpn.service <<UNIT
[Unit]
Description=iperf3 для замера скорости QP VPN
After=network.target

[Service]
ExecStart=/usr/bin/iperf3 --server --port ${PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable iperf3-qpvpn >/dev/null 2>&1 || true
systemctl restart iperf3-qpvpn

# Порт открываем только на время замера — закройте его командой --stop.
iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT

echo
echo "================ замер включён ================"
echo "Сервер слушает порт $PORT."
echo
echo "На телефоне поставьте «iPerf3 Wi-Fi Speed Test» (Android) и впишите:"
echo "    адрес:  $PUBLIC_IP"
echo "    порт:   $PORT"
echo
echo "Либо с компьютера, где есть iperf3:"
echo "    iperf3 -c $PUBLIC_IP -p $PORT        # отдача с вашей стороны"
echo "    iperf3 -c $PUBLIC_IP -p $PORT -R     # приём к вам"
echo "    iperf3 -c $PUBLIC_IP -p $PORT -P 4   # в четыре потока: предел канала"
echo
echo "Меряйте дважды: с включённым VPN и с выключенным."
echo "  разница небольшая  — канал сервера упирается, вопрос к тарифу VPS;"
echo "  без VPN сильно быстрее — режет туннель, пробуйте MTU в приложении."
echo
echo "Когда закончите, закройте порт:  sudo bash $0 --stop"
echo "==============================================="
