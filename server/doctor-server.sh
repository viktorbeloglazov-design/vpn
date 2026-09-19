#!/bin/bash
# Проверяет серверную часть WireGuard и объясняет, почему у клиентов нет интернета.
#
#   sudo bash doctor-server.sh          # только проверка
#   sudo bash doctor-server.sh --fix    # проверка и починка найденного
set -uo pipefail

WG_IF="wg0"
WG_NET="10.8.0.0/24"
FIX=0
WATCH=0
[ "${1:-}" = "--fix" ] && FIX=1
[ "${1:-}" = "--watch" ] && WATCH=1

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; PROBLEMS=$((PROBLEMS + 1)); }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }
PROBLEMS=0

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 ${1:-}" >&2
    exit 1
fi


if [ "$WATCH" = "1" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "Запустите с правами root: sudo bash $0 --watch" >&2
        exit 1
    fi
    command -v tcpdump >/dev/null 2>&1 || apt-get install -y tcpdump >/dev/null 2>&1

    echo "Наблюдение за туннелем — 20 секунд."
    echo "ПРЯМО СЕЙЧАС включите VPN на устройстве и откройте любой сайт."
    echo

    BEFORE="$(wg show "$WG_IF" transfer)"
    timeout 20 tcpdump -ni "$WG_IF" -c 15 2>/dev/null | sed 's/^/  /' > /tmp/wgdump.txt
    AFTER="$(wg show "$WG_IF" transfer)"

    echo "Пакеты внутри туннеля (что сервер расшифровал):"
    if [ -s /tmp/wgdump.txt ]; then
        cat /tmp/wgdump.txt
    else
        echo "  ПУСТО — ни одного пакета от клиента не дошло."
    fi

    echo
    echo "Счётчики до наблюдения:"; printf '%s\n' "$BEFORE" | sed 's/^/  /'
    echo "Счётчики после:";          printf '%s\n' "$AFTER"  | sed 's/^/  /'
    echo
    echo "Рукопожатия:"; wg show "$WG_IF" latest-handshakes | sed 's/^/  /'
    echo
    echo "Столбцы transfer: публичный ключ, принято сервером, отправлено сервером."
    echo "Если принято растёт, а отправлено стоит — сервер не выпускает трафик наружу."
    echo "Если оба по нулям — пакеты клиента до сервера не доходят."
    exit 0
fi

WAN="$(ip route show default | awk '/default/ {print $5; exit}')"

echo "Диагностика сервера WireGuard"
echo

echo "Интерфейс:"
if wg show "$WG_IF" >/dev/null 2>&1; then
    ok "$WG_IF поднят"
    PEERS="$(wg show "$WG_IF" peers | wc -l)"
    ok "клиентов в списке: $PEERS"
    HS="$(wg show "$WG_IF" latest-handshakes | awk '$2 > 0 {n++} END {print n+0}')"
    if [ "$HS" -gt 0 ]; then
        ok "рукопожатие есть у клиентов: $HS"
    else
        warn "ни одного рукопожатия — клиенты пока не подключались"
    fi
else
    bad "$WG_IF не поднят (systemctl status wg-quick@$WG_IF)"
fi

echo
echo "Пересылка пакетов:"
if [ "$(sysctl -n net.ipv4.ip_forward)" = "1" ]; then
    ok "net.ipv4.ip_forward = 1"
else
    bad "net.ipv4.ip_forward = 0 — сервер не пересылает трафик в интернет"
    if [ "$FIX" = "1" ]; then
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
        printf 'net.ipv4.ip_forward = 1\n' > /etc/sysctl.d/99-wireguard.conf
        ok "починено: форвардинг включён и закреплён"
    fi
fi

echo
echo "NAT (подмена адреса на выходе):"
echo "  внешний интерфейс: ${WAN:-не определён}"
if iptables -t nat -S POSTROUTING | grep -q "MASQUERADE"; then
    RULE="$(iptables -t nat -S POSTROUTING | grep MASQUERADE | head -1)"
    ok "правило есть: $RULE"
    RULE_IF="$(printf '%s' "$RULE" | sed -n 's/.*-o \([^ ]*\).*/\1/p')"
    if [ -n "$RULE_IF" ] && [ -n "$WAN" ] && [ "$RULE_IF" != "$WAN" ]; then
        bad "в правиле интерфейс $RULE_IF, а трафик уходит через $WAN — не совпадает"
        if [ "$FIX" = "1" ]; then
            iptables -t nat -A POSTROUTING -s "$WG_NET" -o "$WAN" -j MASQUERADE
            ok "починено: добавлено правило для $WAN"
        fi
    fi
else
    bad "нет MASQUERADE — ответы из интернета не находят дорогу назад"
    if [ "$FIX" = "1" ] && [ -n "$WAN" ]; then
        iptables -t nat -A POSTROUTING -s "$WG_NET" -o "$WAN" -j MASQUERADE
        ok "починено: NAT добавлен"
    fi
fi

echo
echo "Цепочка FORWARD:"
POLICY="$(iptables -S FORWARD | awk '/^-P FORWARD/ {print $3}')"
echo "  политика по умолчанию: ${POLICY:-неизвестно}"
if iptables -S FORWARD | grep -q -- "-i $WG_IF -j ACCEPT"; then
    ok "трафик из туннеля разрешён"
else
    if [ "$POLICY" = "ACCEPT" ]; then
        warn "явного правила нет, но политика ACCEPT — пропустит"
    else
        bad "трафик из туннеля блокируется (политика $POLICY, разрешающего правила нет)"
    fi
    if [ "$FIX" = "1" ]; then
        iptables -A FORWARD -i "$WG_IF" -j ACCEPT
        iptables -A FORWARD -o "$WG_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
        ok "починено: правила FORWARD добавлены"
    fi
fi

echo
echo "Интернет самого сервера:"
COUNTRY="$(curl -s --max-time 10 https://ifconfig.co/country 2>/dev/null)"
if [ -n "$COUNTRY" ]; then
    ok "выход в интернет есть, страна: $COUNTRY"
    [ "$COUNTRY" != "Kazakhstan" ] && warn "ожидался Kazakhstan — проверьте локацию сервера"
else
    bad "у сервера нет интернета — клиентам его взять неоткуда"
fi

echo
if [ "$PROBLEMS" -eq 0 ]; then
    echo "Проблем не найдено. Если у клиента всё ещё нет интернета, дело в MTU:"
    echo "  поменяйте в конфиге клиента MTU = 1420 на MTU = 1380."
else
    echo "Найдено проблем: $PROBLEMS."
    [ "$FIX" = "0" ] && echo "Починить: sudo bash $0 --fix"
fi
