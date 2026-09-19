#!/bin/bash
# Проверяет конфиги WireGuard по-настоящему: поднимает туннель, ждёт handshake
# и смотрит, из какой страны видят вас сайты. Нужен Казахстан — KZ.
#
#   sudo bash scripts/test-configs-kz.sh clients/*.conf
#   sudo bash scripts/test-configs-kz.sh --country KZ clients/device-01.conf
#
# Конфиги проверяются по очереди: на время каждой проверки весь трафик машины
# уходит в туннель, поэтому на рабочем компьютере возможны короткие разрывы.
# Требуется wireguard-tools (wg, wg-quick) и curl.
set -uo pipefail

IFACE="wgtest"
WANT="KZ"
TIMEOUT=15

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --country) WANT="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) break ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Укажите конфиги: sudo bash $0 clients/*.conf" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите с правами root: sudo bash $0 $*" >&2
    exit 1
fi

for tool in wg wg-quick curl; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Не найден $tool. Linux: apt install wireguard-tools. macOS: brew install wireguard-tools" >&2
        exit 1
    }
done

WG_DIR="/etc/wireguard"
install -d -m 0700 "$WG_DIR"

cleanup() {
    wg-quick down "$IFACE" >/dev/null 2>&1
    rm -f "$WG_DIR/$IFACE.conf"
}
trap cleanup EXIT

# Страна выходного IP: два независимых источника, чтобы не зависеть от одного сервиса.
exit_country() {
    local out
    out="$(curl -s --max-time 10 https://ifconfig.co/json 2>/dev/null)"
    if [ -n "$out" ]; then
        printf '%s' "$out" | tr ',' '\n' | awk -F'"' '/country_iso/ {print $4; exit}'
        printf '%s' "$out" | tr ',' '\n' | awk -F'"' '/"ip"/ {print $4; exit}' >&2
        return
    fi
    out="$(curl -s --max-time 10 https://ipinfo.io/json 2>/dev/null)"
    printf '%s' "$out" | tr ',' '\n' | awk -F'"' '/"country"/ {print $4; exit}'
    printf '%s' "$out" | tr ',' '\n' | awk -F'"' '/"ip"/ {print $4; exit}' >&2
}

BASE_COUNTRY="$(exit_country 2>/dev/null)"
echo "Проверка конфигов WireGuard (ожидаемая локация: $WANT)"
echo "Без туннеля вас видят как: ${BASE_COUNTRY:-не удалось определить}"
echo

PASS=0; FAIL=0
for CONF in "$@"; do
    NAME="$(basename "$CONF" .conf)"
    printf '%s\n' "$NAME"

    if ! grep -q '^\[Interface\]' "$CONF" 2>/dev/null; then
        bad "не похоже на конфиг WireGuard"; FAIL=$((FAIL + 1)); echo; continue
    fi

    cleanup
    install -m 0600 "$CONF" "$WG_DIR/$IFACE.conf"

    if ! wg-quick up "$IFACE" >/dev/null 2>&1; then
        bad "туннель не поднялся (wg-quick up)"; FAIL=$((FAIL + 1)); echo; continue
    fi

    # Ждём рукопожатие: без него сервер не знает этого пира.
    HS=0
    for _ in $(seq 1 "$TIMEOUT"); do
        HS="$(wg show "$IFACE" latest-handshakes 2>/dev/null | awk '{print $2; exit}')"
        [ -n "$HS" ] && [ "$HS" != "0" ] && break
        sleep 1
    done

    if [ -z "$HS" ] || [ "$HS" = "0" ]; then
        bad "нет handshake за ${TIMEOUT} с"
        warn "почти всегда это значит: публичный ключ клиента не добавлен на сервер"
        warn "(либо закрыт UDP-порт эндпоинта). Добавьте [Peer] в wg0.conf и повторите."
        FAIL=$((FAIL + 1)); cleanup; echo; continue
    fi
    ok "handshake есть"

    IPADDR=""; COUNTRY="$(exit_country 2>/dev/null)"
    IPADDR="$( { exit_country >/dev/null; } 2>&1 )"

    if [ -z "$COUNTRY" ]; then
        warn "туннель работает, но страну определить не удалось (нет доступа к ifconfig.co/ipinfo.io)"
        FAIL=$((FAIL + 1))
    elif [ "$COUNTRY" = "$WANT" ]; then
        ok "внешний IP ${IPADDR:-?} — страна $COUNTRY"
        PASS=$((PASS + 1))
    else
        bad "внешний IP ${IPADDR:-?} — страна $COUNTRY, а нужна $WANT"
        warn "трафик идёт не через тот сервер, либо AllowedIPs не 0.0.0.0/0"
        FAIL=$((FAIL + 1))
    fi

    RX="$(wg show "$IFACE" transfer 2>/dev/null | awk '{print $2; exit}')"
    [ -n "$RX" ] && [ "$RX" != "0" ] && ok "данные от сервера получены ($RX байт)"

    cleanup
    echo
done

echo "==============================="
echo "Пройдено: $PASS, не пройдено: $FAIL"
[ "$FAIL" -eq 0 ] && echo "Все проверенные конфиги дают локацию $WANT."
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
