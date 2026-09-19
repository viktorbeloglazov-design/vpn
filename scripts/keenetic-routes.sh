#!/bin/bash
# Готовит для Keenetic список маршрутов «в туннель идёт только это».
#
# Основной канал остаётся провайдерским — в туннель уходят лишь адреса из
# списка. Домены резолвятся в IP: роутер маршрутизирует по адресам, а не по
# именам, поэтому список нужно иногда пересобирать.
#
#   ./scripts/keenetic-routes.sh --set ai
#   ./scripts/keenetic-routes.sh --set ai --set social 104.16.0.0/12 grok.com
#   ./scripts/keenetic-routes.sh --set ai --remove        # команды на снятие
#
set -euo pipefail

IFACE="Wireguard0"
OUT=""
REMOVE=0
ITEMS=()

die() { printf "\033[31mОшибка:\033[0m %s\n" "$1" >&2; exit 1; }

set_ai="chatgpt.com chat.openai.com openai.com api.openai.com cdn.oaistatic.com \
claude.ai anthropic.com api.anthropic.com gemini.google.com aistudio.google.com \
perplexity.ai midjourney.com grok.com"
set_social="instagram.com www.instagram.com facebook.com www.facebook.com \
x.com twitter.com api.twitter.com t.co"
set_media="spotify.com open.spotify.com accounts.spotify.com netflix.com"
set_dev="github.com raw.githubusercontent.com hub.docker.com registry-1.docker.io"

usage() {
    cat <<'USAGE'
Использование:
  keenetic-routes.sh [--set ИМЯ]... [домен|подсеть]... [параметры]

Наборы (--set):
  ai       ChatGPT, Claude, Gemini, Perplexity, Midjourney, Grok
  social   Instagram, Facebook, X (Twitter)
  media    Spotify, Netflix
  dev      GitHub, Docker Hub

Параметры:
  --interface NAME   интерфейс туннеля на роутере (по умолчанию Wireguard0)
  --out FILE         записать команды в файл
  --remove           выдать команды на снятие маршрутов, а не на добавление
  --list             показать состав наборов и выйти
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --list)
            for s in ai social media dev; do
                eval "v=\$set_$s"
                printf "\n%s:\n" "$s"
                for d in $v; do echo "  $d"; done
            done
            exit 0 ;;
        --set)
            name="${2:?}"; shift 2
            case "$name" in
                ai|social|media|dev) eval "v=\$set_$name"; for d in $v; do ITEMS+=("$d"); done ;;
                *) die "нет такого набора: $name (список: --list)" ;;
            esac ;;
        --interface) IFACE="${2:?}"; shift 2 ;;
        --out) OUT="${2:?}"; shift 2 ;;
        --remove) REMOVE=1; shift ;;
        -*) die "неизвестный параметр $1" ;;
        *) ITEMS+=("$1"); shift ;;
    esac
done

[ ${#ITEMS[@]} -gt 0 ] || { usage; exit 1; }

resolve() {
    local host="$1"
    if command -v dig >/dev/null 2>&1; then
        dig +short +time=3 +tries=1 A "$host" 2>/dev/null | grep -E '^[0-9.]+$' || true
    elif command -v host >/dev/null 2>&1; then
        host -t A "$host" 2>/dev/null | awk '/has address/ {print $NF}' || true
    elif command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u || true
    else
        python3 -c "
import socket, sys
try:
    print('\n'.join(sorted({i[4][0] for i in socket.getaddrinfo(sys.argv[1], 443, socket.AF_INET)})))
except Exception:
    pass" "$host" || true
    fi
}

prefix_to_mask() {
    local p="$1" i mask=""
    for i in 1 2 3 4; do
        local bits=$(( p > 8 ? 8 : (p > 0 ? p : 0) ))
        p=$(( p - bits ))
        mask="${mask}$(( (256 - 2 ** (8 - bits)) % 256 ))."
    done
    printf '%s' "${mask%.}"
}

emit() { if [ -n "$OUT" ]; then printf '%s\n' "$1" >> "$OUT"; else printf '%s\n' "$1"; fi; }

[ -n "$OUT" ] && : > "$OUT"

if [ "$REMOVE" -eq 1 ]; then
    emit "! Снятие маршрутов с $IFACE. Адреса могли смениться —"
    emit "! что не снимется, уберите в «Сетевые правила → Маршрутизация»."
else
    emit "! Маршруты «только это через туннель» для $IFACE."
    emit "! Вставить в Управление → Общие настройки → Командная строка."
fi

total=0
failed=()
SEEN=" "
seen_or_mark() {           # возвращает 1, если адрес уже выписан выше
    case "$SEEN" in *" $1 "*) return 1 ;; esac
    SEEN="$SEEN$1 "
    return 0
}
for item in "${ITEMS[@]}"; do
    if printf '%s' "$item" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$'; then
        net="${item%%/*}"; pfx="${item#*/}"
        [ "$pfx" = "$item" ] && pfx=32
        seen_or_mark "$net/$pfx" || continue
        emit "! $item"
        if [ "$REMOVE" -eq 1 ]; then
            emit "no ip route $net $(prefix_to_mask "$pfx") $IFACE"
        else
            emit "ip route $net $(prefix_to_mask "$pfx") $IFACE auto"
        fi
        total=$((total + 1))
        continue
    fi

    ips="$(resolve "$item" | sort -u)"
    if [ -z "$ips" ]; then
        failed+=("$item")
        continue
    fi
    printed=0
    while IFS= read -r ip; do
        [ -n "$ip" ] || continue
        case "$ip" in 127.*|0.0.0.0) continue ;; esac
        seen_or_mark "$ip/32" || continue
        [ "$printed" -eq 1 ] || { emit "! $item"; printed=1; }
        if [ "$REMOVE" -eq 1 ]; then
            emit "no ip route $ip 255.255.255.255 $IFACE"
        else
            emit "ip route $ip 255.255.255.255 $IFACE auto"
        fi
        total=$((total + 1))
    done <<<"$ips"
done

emit "system configuration save"

printf "\nМаршрутов: %d, интерфейс %s.\n" "$total" "$IFACE" >&2
[ -n "$OUT" ] && printf "Файл: %s\n" "$OUT" >&2
if [ ${#failed[@]} -gt 0 ]; then
    printf "\033[33m!\033[0m не удалось разрезолвить: %s\n" "${failed[*]}" >&2
fi
cat >&2 <<'HINT'

Помните: это маршруты по IP-адресам.
  • У сайтов за Cloudflare/Akamai адреса общие и меняются — список
    придётся пересобирать (и иногда он заденет соседей по тому же IP).
  • DNS роутера при этом остаётся провайдерским: имя резолвится напрямую,
    в туннель уходит только соединение с полученным адресом.
  • Проверка: на устройстве `traceroute <домен>` — первый хоп должен быть
    роутер, а дальше адреса сервера, а не провайдера.
HINT
