#!/bin/bash
# Установка службы QP VPN из бандла приложения.
# Этот скрипт лежит внутри QPVPN.app и запускается самим приложением
# с правами администратора. Ключ --uninstall снимает службу.
set -euo pipefail

LABEL="com.kupibas.vpn.helper"
HELPER_DIR="/usr/local/libexec/kupibas-vpn"
STATE_DIR="/Library/Application Support/KupibasVPN"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
RUNTIME_DIR="/var/run/kupibas-vpn"

LOG="/var/log/kupibas-vpn-install.log"
RESOURCES="$(cd "$(dirname "$0")" && pwd)"
CONTENTS="$(cd "$RESOURCES/.." 2>/dev/null && pwd || echo "$RESOURCES")"
HELPERS="$CONTENTS/Library/Helpers"

if [ "$(id -u)" -ne 0 ]; then
    echo "Нужны права администратора." >&2
    exit 1
fi

touch "$LOG" 2>/dev/null || true
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null || true; }
log "=== запуск установщика: $* ==="

# Служба поднимает туннель сама, поэтому и снимается он вручную: удаляем
# сокет — процесс туннеля видит это и уходит.
stop_tunnel() {
    NAME_FILE="/var/run/amneziawg/kb0.name"
    if [ -f "$NAME_FILE" ]; then
        IFACE="$(cat "$NAME_FILE" 2>/dev/null || true)"
        if [ -n "$IFACE" ]; then
            rm -f "/var/run/amneziawg/$IFACE.sock"
            ifconfig "$IFACE" down >/dev/null 2>&1 || true
        fi
        rm -f "$NAME_FILE"
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    stop_tunnel
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    launchctl disable "system/$LABEL" 2>/dev/null || true
    launchctl enable "system/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$HELPER_DIR" "$RUNTIME_DIR"
    echo "Служба удалена. Настройки сохранены в $STATE_DIR"
    exit 0
fi

if [ ! -x "$HELPERS/kupibasvpnd" ]; then
    echo "В бандле приложения нет служебного файла kupibasvpnd." >&2
    exit 1
fi

echo "Останавливаю прошлую версию службы"
stop_tunnel
launchctl bootout "system/$LABEL" 2>/dev/null || true

echo "Ставлю файлы службы"
install -d -m 0755 "$HELPER_DIR"
install -m 0755 "$HELPERS/kupibasvpnd" "$HELPER_DIR/kupibasvpnd"
for tool in amneziawg-go awg wireguard-go wg; do
    if [ -f "$HELPERS/$tool" ]; then
        install -m 0755 "$HELPERS/$tool" "$HELPER_DIR/$tool"
    fi
done

# Список подсетей России кладём туда, где его прочитает служба: по нему
# главный фильтр решает, что идёт мимо туннеля.
if [ -f "$RESOURCES/ru_ipv4.txt" ]; then
    install -d -m 0755 "/Library/Application Support/QPVPN"
    install -m 0644 "$RESOURCES/ru_ipv4.txt" "/Library/Application Support/QPVPN/ru_ipv4.txt"
    echo "Список подсетей России: $(grep -vc '^#' "$RESOURCES/ru_ipv4.txt") записей"
fi

# macOS помечает всё скачанное карантином — со службы его нужно снять,
# иначе launchd может отказаться её запускать.
xattr -dr com.apple.quarantine "$HELPER_DIR" 2>/dev/null || true
APP_PATH="$(cd "$CONTENTS/.." 2>/dev/null && pwd || true)"
if [ -n "$APP_PATH" ] && [ "${APP_PATH##*.}" = "app" ]; then
    xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
fi

# Утилиты WireGuard: либо вложены в приложение, либо стоят из Homebrew.
# wg-quick не нужен: это скрипт на bash 4+, которого в macOS нет, — туннель
# служба поднимает сама через ifconfig и route.
MISSING=()
for tool in wireguard-go wg; do
    if [ ! -x "$HELPER_DIR/$tool" ] \
        && ! PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" command -v "$tool" >/dev/null 2>&1; then
        MISSING+=("$tool")
    fi
done

# Ключи с маскировкой поднимает только форк Amnezia. Если рядом лежит он —
# всё в порядке; если нет, обычные ключи работать будут, а AmneziaWG нет.
if [ -x "$HELPER_DIR/amneziawg-go" ]; then
    echo "Туннель: AmneziaWG (ключи с маскировкой поддерживаются)"
else
    echo "Внимание: рядом только обычный WireGuard — ключи AmneziaWG не поднимутся." >&2
fi
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Не хватает утилит WireGuard: ${MISSING[*]}" >&2
    echo "Переустановите приложение — утилиты лежат внутри него." >&2
    exit 1
fi

echo "Готовлю каталог настроек"
install -d -m 0770 -o root -g staff "$STATE_DIR"
if [ ! -f "$STATE_DIR/config.json" ]; then
    cat > "$STATE_DIR/config.json" <<'JSON'
{
  "version": 1,
  "enabled": false,
  "mode": "full",
  "server": {
    "name": "KZ",
    "endpoint": "",
    "publicKey": "",
    "presharedKey": "",
    "privateKey": "",
    "addresses": [],
    "dns": [],
    "mtu": 1420,
    "persistentKeepalive": 25
  },
  "rules": [],
  "options": {
    "useTunnelDNS": true,
    "disableIPv6": true,
    "reresolveMinutes": 5,
    "autoReconnect": true
  }
}
JSON
fi
chown root:staff "$STATE_DIR/config.json"
chmod 0660 "$STATE_DIR/config.json"

echo "Проверяю служебный файл"
if ! "$HELPER_DIR/kupibasvpnd" --check >/dev/null 2>&1; then
    log "kupibasvpnd --check не прошёл"
    {
        echo "--- диагностика бинарника ---"
        file "$HELPER_DIR/kupibasvpnd" 2>&1
        codesign -dv "$HELPER_DIR/kupibasvpnd" 2>&1 | head -5
    } >> "$LOG" 2>&1
    echo "Служебный файл не запускается на этом компьютере. Подробности: $LOG" >&2
    exit 1
fi

echo "Регистрирую службу в системе"
install -m 0644 -o root -g wheel "$RESOURCES/$LABEL.plist" "$PLIST"
# Файл службы тоже мог приехать с меткой карантина — launchd такую не примет.
xattr -dr com.apple.quarantine "$PLIST" 2>/dev/null || true

if ! plutil -lint "$PLIST" >/dev/null 2>&1; then
    echo "Файл службы повреждён: $PLIST" >&2
    exit 1
fi

# Прошлая регистрация снимается не мгновенно, а bootstrap поверх неё
# отвечает «Bootstrap failed: 5: Input/output error». Поэтому ждём,
# пока launchd действительно забудет метку.
launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
ATTEMPT=0
while launchctl print "system/$LABEL" >/dev/null 2>&1 && [ $ATTEMPT -lt 15 ]; do
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
log "ожидание снятия прошлой регистрации: $ATTEMPT с"

# Метка могла остаться помеченной как отключённая — тогда bootstrap
# тоже падает с ошибкой 5.
launchctl enable "system/$LABEL" >/dev/null 2>&1 || true

BOOTSTRAP_ERROR=""
if ! BOOTSTRAP_ERROR="$(launchctl bootstrap system "$PLIST" 2>&1)"; then
    log "bootstrap не удался: $BOOTSTRAP_ERROR"
    # Запасной путь: старый API launchctl, он переживает часть таких отказов.
    if launchctl load -w "$PLIST" >/dev/null 2>&1; then
        log "служба загружена через launchctl load"
    else
        {
            echo "--- диагностика launchd ---"
            echo "bootstrap: $BOOTSTRAP_ERROR"
            ls -l "$PLIST" "$HELPER_DIR" 2>&1
            launchctl print "system/$LABEL" 2>&1 | head -25
            launchctl print-disabled system 2>&1 | grep -i kupibas || true
        } >> "$LOG" 2>&1
        echo "launchd отклонил службу: $BOOTSTRAP_ERROR" >&2
        echo "Подробности записаны в $LOG" >&2
        exit 1
    fi
fi

launchctl kickstart -k "system/$LABEL" >/dev/null 2>&1 || true

sleep 2
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    log "служба запущена"
    echo "Служба установлена и запущена."
else
    log "служба не отвечает после запуска"
    launchctl print "system/$LABEL" >> "$LOG" 2>&1 || true
    echo "Служба установлена, но не отвечает. Журналы: /var/log/kupibas-vpn.log и $LOG" >&2
    exit 1
fi
