#!/bin/bash
# Превращает клиентский конфиг WireGuard в готовую настройку для роутера Keenetic.
#
# Один ключ WireGuard — это одно устройство. Если поднять туннель не на телефоне
# и не на ноутбуке, а на роутере, тем же самым ключом пользуется вся домашняя
# сеть: телефоны, телевизор, приставка, компьютеры.
#
#   ./scripts/keenetic-wg.sh KotiKey.conf
#   ./scripts/keenetic-wg.sh KotiKey.conf --out ~/keenetic
#   ./scripts/keenetic-wg.sh KotiKey.conf --endpoint mydom.keenetic.pro \
#       --server-peer iphone --server-peer macbook
#
set -euo pipefail

SRC=""
OUT_DIR="."
IFACE="Wireguard0"
MTU="1420"
GLOBAL_PRIORITY="4"
SERVER_IFACE="Wireguard1"
SERVER_NET="10.99.9"
SERVER_PORT="51820"
SERVER_ENDPOINT=""
LAN_IP="192.168.1.1"
CONN_NAME=""
PEERS=()

die() { printf "\033[31mОшибка:\033[0m %s\n" "$1" >&2; exit 1; }
note() { printf "\033[33m!\033[0m %s\n" "$1" >&2; }

usage() {
    cat <<'USAGE'
Использование:
  keenetic-wg.sh <конфиг.conf> [параметры]

Параметры:
  --out DIR             куда положить готовые файлы (по умолчанию текущая папка)
  --interface NAME      имя интерфейса на роутере (по умолчанию Wireguard0)
  --name TEXT           подпись подключения в интерфейсе роутера
  --mtu N               MTU туннеля (по умолчанию 1420)
  --priority N          приоритет подключения для «ip global» (по умолчанию 4)
  --lan-ip IP           адрес роутера в домашней сети (по умолчанию 192.168.1.1)
  --server-peer NAME    выдать ключ для устройства вне дома; можно повторять
  --endpoint HOST       белый IP или KeenDNS-имя роутера для таких ключей
  --server-port N       порт VPN-сервера роутера (по умолчанию 51820)
  --server-net A.B.C    подсеть VPN-сервера роутера (по умолчанию 10.99.9)
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --out) OUT_DIR="${2:?}"; shift 2 ;;
        --interface) IFACE="${2:?}"; shift 2 ;;
        --name) CONN_NAME="${2:?}"; shift 2 ;;
        --mtu) MTU="${2:?}"; shift 2 ;;
        --priority) GLOBAL_PRIORITY="${2:?}"; shift 2 ;;
        --lan-ip) LAN_IP="${2:?}"; shift 2 ;;
        --server-peer) PEERS+=("${2:?}"); shift 2 ;;
        --endpoint) SERVER_ENDPOINT="${2:?}"; shift 2 ;;
        --server-port) SERVER_PORT="${2:?}"; shift 2 ;;
        --server-net) SERVER_NET="${2:?}"; shift 2 ;;
        --server-iface) SERVER_IFACE="${2:?}"; shift 2 ;;
        -*) die "неизвестный параметр $1" ;;
        *) [ -z "$SRC" ] || die "лишний аргумент $1"; SRC="$1"; shift ;;
    esac
done

[ -n "$SRC" ] || { usage; exit 1; }
[ -f "$SRC" ] || die "файл не найден: $SRC"

umask 077
mkdir -p "$OUT_DIR"

# ── разбор конфига ────────────────────────────────────────────────────────────
# Значения [Interface] и список пиров: каждый пир — строка
# "pubkey|psk|endpoint|keepalive|allowed1,allowed2".
PRIVATE_KEY=""; ADDRESSES=""; DNS_LIST=""; SRC_MTU=""
PEER_LINES=()
cur_pub=""; cur_psk=""; cur_ep=""; cur_ka=""; cur_allowed=""
section=""

flush_peer() {
    [ -n "$cur_pub" ] || return 0
    PEER_LINES+=("$cur_pub|$cur_psk|$cur_ep|$cur_ka|$cur_allowed")
    cur_pub=""; cur_psk=""; cur_ep=""; cur_ka=""; cur_allowed=""
}

while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    case "$line" in
        "[Interface]") flush_peer; section="interface"; continue ;;
        "[Peer]") flush_peer; section="peer"; continue ;;
    esac
    key="$(printf '%s' "${line%%=*}" | sed 's/[[:space:]]*$//' | tr 'A-Z' 'a-z')"
    val="$(printf '%s' "${line#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ "$key" != "$line" ] || continue
    if [ "$section" = "interface" ]; then
        case "$key" in
            privatekey) PRIVATE_KEY="$val" ;;
            address)    ADDRESSES="$val" ;;
            dns)        DNS_LIST="$val" ;;
            mtu)        SRC_MTU="$val" ;;
        esac
    elif [ "$section" = "peer" ]; then
        case "$key" in
            publickey)          cur_pub="$val" ;;
            presharedkey)       cur_psk="$val" ;;
            endpoint)           cur_ep="$val" ;;
            persistentkeepalive) cur_ka="$val" ;;
            allowedips)         cur_allowed="$val" ;;
        esac
    fi
done < "$SRC"
flush_peer

[ -n "$PRIVATE_KEY" ] || die "в конфиге нет PrivateKey — это не клиентский конфиг WireGuard"
[ -n "$ADDRESSES" ] || die "в конфиге нет Address"
[ ${#PEER_LINES[@]} -gt 0 ] || die "в конфиге нет ни одного [Peer]"
[ -n "$SRC_MTU" ] && MTU="$SRC_MTU"

prefix_to_mask() {
    local p="$1" i mask=""
    for i in 1 2 3 4; do
        local bits=$(( p > 8 ? 8 : (p > 0 ? p : 0) ))
        p=$(( p - bits ))
        mask="${mask}$(( (256 - 2 ** (8 - bits)) % 256 ))."
    done
    printf '%s' "${mask%.}"
}

# ── ключи для VPN-сервера роутера ─────────────────────────────────────────────
gen_private() {
    if command -v wg >/dev/null 2>&1; then
        wg genkey
    elif command -v openssl >/dev/null 2>&1; then
        openssl genpkey -algorithm X25519 2>/dev/null | openssl pkey -outform DER | tail -c 32 | base64
    else
        die "нужен wg или openssl, чтобы выпустить ключи (brew install wireguard-tools)"
    fi
}
pub_from_private() {
    local priv="$1"
    if command -v wg >/dev/null 2>&1; then
        printf '%s' "$priv" | wg pubkey
    else
        # PKCS#8-обёртка X25519 + 32 байта ключа → публичный ключ через openssl
        { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'
          printf '%s' "$priv" | base64 -d; } |
            openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64
    fi
}
gen_psk() {
    if command -v wg >/dev/null 2>&1; then wg genpsk
    else openssl rand -base64 32; fi
}

BASE="$(basename "$SRC")"; BASE="${BASE%.conf}"
BASE="$(printf '%s' "$BASE" | tr -c 'A-Za-z0-9._-' '-')"
[ -n "$CONN_NAME" ] || CONN_NAME="$BASE"
IMPORT_FILE="$OUT_DIR/keenetic-$BASE.conf"
CLI_FILE="$OUT_DIR/keenetic-$BASE.cli.txt"

# ── файл для импорта в веб-интерфейс ──────────────────────────────────────────
{
    echo "# Импорт: Интернет → Другие подключения → WireGuard → Добавить подключение"
    echo "[Interface]"
    echo "PrivateKey = $PRIVATE_KEY"
    echo "Address = $ADDRESSES"
    [ -n "$DNS_LIST" ] && echo "DNS = $DNS_LIST"
    echo "MTU = $MTU"
    for p in "${PEER_LINES[@]}"; do
        IFS='|' read -r pub psk ep ka allowed <<<"$p"
        echo
        echo "[Peer]"
        echo "PublicKey = $pub"
        [ -n "$psk" ] && echo "PresharedKey = $psk"
        [ -n "$ep" ] && echo "Endpoint = $ep"
        echo "AllowedIPs = ${allowed:-0.0.0.0/0}"
        echo "PersistentKeepalive = ${ka:-25}"
    done
} > "$IMPORT_FILE"

# ── команды CLI ───────────────────────────────────────────────────────────────
{
    echo "! Keenetic CLI: Управление → Общие настройки → Командная строка"
    echo "! (или telnet/ssh на роутер). Вставлять блоками, затем сохранить."
    echo "interface $IFACE"
    echo "    description \"$CONN_NAME\""
    echo "    security-level public"
    first_addr="${ADDRESSES%%,*}"
    first_addr="$(printf '%s' "$first_addr" | sed 's/[[:space:]]//g')"
    addr_ip="${first_addr%%/*}"
    addr_pfx="${first_addr#*/}"
    [ "$addr_pfx" = "$first_addr" ] && addr_pfx=32
    echo "    ip address $addr_ip $(prefix_to_mask "$addr_pfx")"
    echo "    ip mtu $MTU"
    echo "    ip tcp adjust-mss pmtu"
    echo "    ip global $GLOBAL_PRIORITY"
    echo "    wireguard private-key $PRIVATE_KEY"
    for p in "${PEER_LINES[@]}"; do
        IFS='|' read -r pub psk ep ka allowed <<<"$p"
        echo "    wireguard peer $pub"
        [ -n "$ep" ] && echo "        endpoint $ep"
        [ -n "$psk" ] && echo "        preshared-key $psk"
        echo "        keepalive-interval ${ka:-25}"
        IFS=',' read -ra nets <<<"${allowed:-0.0.0.0/0}"
        for n in "${nets[@]}"; do
            n="$(printf '%s' "$n" | sed 's/[[:space:]]//g')"
            [ -n "$n" ] || continue
            case "$n" in *:*) continue ;; esac   # IPv6 в Keenetic задаётся отдельно
            net_ip="${n%%/*}"; net_pfx="${n#*/}"
            [ "$net_pfx" = "$n" ] && net_pfx=32
            echo "        allow-ips $net_ip $net_pfx"
        done
        echo "        exit"
    done
    echo "    up"
    echo "    exit"
    echo "system configuration save"
} > "$CLI_FILE"

# ── ключи для устройств вне дома ──────────────────────────────────────────────
SERVER_FILES=()
if [ ${#PEERS[@]} -gt 0 ]; then
    [ -n "$SERVER_ENDPOINT" ] || note "не задан --endpoint: в конфигах устройств Endpoint придётся вписать вручную"
    SRV_PRIV="$(gen_private)"
    SRV_PUB="$(pub_from_private "$SRV_PRIV")"
    SRV_CLI="$OUT_DIR/keenetic-server.cli.txt"
    {
        echo "! VPN-сервер роутера: ключи для телефонов и ноутбуков вне дома."
        echo "! Работает только при белом IP или KeenDNS в режиме «прямой доступ»."
        echo "interface $SERVER_IFACE"
        echo "    description home-vpn"
        echo "    security-level private"
        echo "    ip address ${SERVER_NET}.1 255.255.255.0"
        echo "    ip mtu $MTU"
        echo "    ip tcp adjust-mss pmtu"
        echo "    wireguard listen-port $SERVER_PORT"
        echo "    wireguard private-key $SRV_PRIV"
    } > "$SRV_CLI"
    idx=1
    for name in "${PEERS[@]}"; do
        idx=$((idx + 1))
        safe="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')"
        priv="$(gen_private)"; pub="$(pub_from_private "$priv")"; psk="$(gen_psk)"
        ip="${SERVER_NET}.${idx}"
        {
            echo "    ! $safe"
            echo "    wireguard peer $pub"
            echo "        preshared-key $psk"
            echo "        allow-ips $ip 32"
            echo "        keepalive-interval 25"
            echo "        exit"
        } >> "$SRV_CLI"
        peer_file="$OUT_DIR/peer-$safe.conf"
        {
            echo "# $safe — подключение к домашнему роутеру Keenetic"
            echo "[Interface]"
            echo "PrivateKey = $priv"
            echo "Address = $ip/24"
            echo "DNS = $LAN_IP"
            echo "MTU = $MTU"
            echo
            echo "[Peer]"
            echo "PublicKey = $SRV_PUB"
            echo "PresharedKey = $psk"
            echo "Endpoint = ${SERVER_ENDPOINT:-ВАШ_БЕЛЫЙ_IP_ИЛИ_KEENDNS}:$SERVER_PORT"
            echo "AllowedIPs = 0.0.0.0/0"
            echo "PersistentKeepalive = 25"
        } > "$peer_file"
        SERVER_FILES+=("$peer_file")
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -t PNG -o "$OUT_DIR/peer-$safe.png" < "$peer_file"
            SERVER_FILES+=("$OUT_DIR/peer-$safe.png")
        fi
    done
    {
        echo "    up"
        echo "    exit"
        echo "system configuration save"
    } >> "$SRV_CLI"
    SERVER_FILES=("$SRV_CLI" "${SERVER_FILES[@]}")
fi

# ── итог ──────────────────────────────────────────────────────────────────────
cat <<REPORT

Готово. Один ключ — вся домашняя сеть.

Файлы:
  $IMPORT_FILE
      загрузить в веб-интерфейсе: Интернет → Другие подключения →
      WireGuard → Добавить подключение → Загрузить из файла
  $CLI_FILE
      то же самое командами, если импорт файла недоступен
REPORT
if [ ${#SERVER_FILES[@]} -gt 0 ]; then
    echo "  Для устройств вне дома:"
    for f in "${SERVER_FILES[@]}"; do echo "      $f"; done
fi
cat <<'REPORT'

Дальше на роутере:
  1. Компоненты: Управление → Общие настройки → Изменить набор компонентов →
     «WireGuard VPN» (и «Приоритеты подключений», если нужен выбор устройств).
  2. В подключении включить «Использовать для выхода в Интернет».
  3. Мои сети и Wi-Fi → Приоритеты подключений: профиль с WireGuard сверху,
     и в него — устройства, которым нужен туннель. Нужен всем — поставьте
     WireGuard первым в общем списке приоритетов.
  4. Интернет → Список DNS-серверов: 1.1.1.1 и 8.8.8.8, иначе имена сайтов
     продолжит резолвить провайдер.
  5. Проверка: на любом устройстве дома откройте 2ip.ru — должен быть IP сервера.

Подробности и разбор ошибок: docs/KEENETIC.md
REPORT
