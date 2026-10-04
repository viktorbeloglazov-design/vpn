#!/bin/bash
# Ставит службу QP VPN на настоящий Mac в CI и проверяет, что она живёт.
#
#   sudo scripts/ci/check-mac-service.sh /Applications/QPVPN.app
#
# Раньше CI только собирал приложение: служба ни разу не ставилась и не
# запускалась. Поэтому «служба вообще не запускается» на Mac у человека
# было первым, что мы об этом узнавали. Теперь — до выпуска.
#
# Этапы:
#   1. служба ставится тем же скриптом, что и у человека, и живёт;
#   2. VPN включён с ключом к несуществующему серверу — туннель
#      поднимается, служба не падает и не перезапускается;
#   3. VPN выключен — туннель снят, служба на месте;
#   4. служба сама обновляется: ей подсовывается номер версии старше
#      выложенной, и она должна скачать выложенную и встать на неё.
set -uo pipefail

APP="${1:?укажите путь к QPVPN.app}"
LABEL="com.kupibas.vpn.helper"
STATE="/Library/Application Support/KupibasVPN"
HELPER_DIR="/usr/local/libexec/kupibas-vpn"
LOG="/var/log/kupibas-vpn.log"
FAILED=0

fail() { echo "ПРОВАЛ: $*"; echo "::error::$*"; FAILED=1; }

# Журналы прогона из этой сессии не скачать, а заметки к проверке видны
# везде. Поэтому самое нужное ещё и складываем в заметки: многострочный
# текст кодируется так, как велит GitHub (%0A вместо перевода строки).
annotate() {
    local title="$1" text
    text="$(cat | tail -n 60 | sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}')"
    [ -n "$text" ] && echo "::notice title=$title::$text"
}
ok()   { echo "в порядке: $*"; }

pid_of() {
    launchctl print "system/$LABEL" 2>/dev/null | awk '/^\tpid = / {print $3; exit}'
}

status_age() {
    local mtime
    mtime="$(stat -f %m "$STATE/status.json" 2>/dev/null || echo 0)"
    echo $(( $(date +%s) - mtime ))
}

alive() {
    local what="$1" pid age
    pid="$(pid_of)"
    age="$(status_age)"
    if [ -z "$pid" ]; then
        fail "$what: служба не запущена"
    elif [ "$age" -gt 15 ]; then
        fail "$what: состояние не обновлялось $age с — цикл службы стоит"
    else
        ok "$what: служба работает (pid $pid), состояние свежее ($age с)"
    fi
}

no_restarts() {
    if [ -s "$STATE/perezapuski.txt" ]; then
        fail "$1: служба перезапускала себя сама:"
        cat "$STATE/perezapuski.txt"
    else
        ok "$1: самоперезапусков нет"
    fi
}

dump() {
    echo "::group::Журнал службы"
    tail -n 200 "$LOG" 2>/dev/null || echo "(журнала нет)"
    echo "::endgroup::"
    echo "::group::Ошибки службы (stderr)"
    tail -n 50 /var/log/kupibas-vpn.stderr.log 2>/dev/null || true
    echo "::endgroup::"
    echo "::group::Установщик"
    tail -n 50 /var/log/kupibas-vpn-install.log 2>/dev/null || true
    echo "::endgroup::"
    echo "::group::Состояние"
    cat "$STATE/status.json" 2>/dev/null || true
    echo
    launchctl print "system/$LABEL" 2>&1 | head -30 || true
    echo "::endgroup::"
}
notes() {
    tail -n 60 "$LOG" 2>/dev/null | annotate "Журнал службы"
    { cat "$STATE/perezapuski.txt" 2>/dev/null; cat "$STATE/obnovlenie.txt" 2>/dev/null; } | annotate "Перезапуски и обновление"
    { tail -n 20 /var/log/kupibas-vpn.stderr.log 2>/dev/null; tail -n 20 /var/log/kupibas-vpn-install.log 2>/dev/null; } | annotate "stderr и установщик"
    { cat "$STATE/status.json" 2>/dev/null; echo; launchctl print "system/$LABEL" 2>&1 | head -25; } | annotate "Состояние"
}
trap 'dump; notes' EXIT

echo "=== 1. Установка ==="
if ! "$APP/Contents/Resources/install-helper.sh"; then
    fail "установщик завершился ошибкой"
    exit 1
fi
VERSION="$(cat "$HELPER_DIR/version" 2>/dev/null || true)"
echo "Версия службы: ${VERSION:-нет отметки}"
sleep 20
alive "сразу после установки"
FIRST_PID="$(pid_of)"
sleep 40
alive "через минуту"
[ "$(pid_of)" = "$FIRST_PID" ] || fail "за минуту служба сменила pid: $FIRST_PID → $(pid_of)"

echo "=== 2. VPN включён (сервер недоступен) ==="
WG="$APP/Contents/Library/Helpers/wg"
CLIENT_KEY="$("$WG" genkey)"
SERVER_KEY="$("$WG" genkey | "$WG" pubkey)"
# Ключи одноразовые, сгенерированы здесь же, сервер — из адресов для
# документации (192.0.2.0/24), которые никуда не ведут.
CLIENT_KEY="$CLIENT_KEY" SERVER_KEY="$SERVER_KEY" STATE="$STATE" python3 - <<'PY'
import json, os
path = os.path.join(os.environ["STATE"], "config.json")
config = json.load(open(path))
config["enabled"] = True
config["server"].update({
    "name": "CI",
    "endpoint": "192.0.2.10:51820",
    "publicKey": os.environ["SERVER_KEY"],
    "privateKey": os.environ["CLIENT_KEY"],
    "addresses": ["10.66.66.2/32"],
    "dns": [],
    "mtu": 1420,
})
json.dump(config, open(path, "w"), ensure_ascii=False, indent=2)
PY
# Пока туннель поднимается, приложение не должно видеть тишину:
# раньше подъём шёл полминуты, и всё это время «служба не отвечала».
for second in $(seq 1 30); do
    sleep 1
    age="$(status_age)"
    if [ "$age" -gt 10 ]; then
        fail "на $second-й секунде подъёма туннеля служба молчит $age с — приложение напишет «не отвечает»"
        break
    fi
done
sleep 30
alive "минута с включённым VPN"
grep -q "utun" <(ifconfig -l) && ok "туннельный интерфейс поднят" || echo "(туннельного интерфейса нет — смотрим журнал)"
UP_LINE="$(grep "Туннель поднят" "$LOG" | tail -1)"
echo "$UP_LINE"
ROUTES="$(echo "$UP_LINE" | sed -n 's/.*маршрутов в туннель: \([0-9]*\).*/\1/p')"
TOOK="$(echo "$UP_LINE" | sed -n 's/.*за \([0-9]*\) с.*/\1/p')"
[ "${ROUTES:-0}" -gt 20 ] && ok "маршрутов в туннель: $ROUTES" || fail "маршрутов в туннель мало: ${ROUTES:-нет записи}"
IN_TABLE="$(netstat -rn -f inet | grep -c utun || true)"
echo "В таблице маршрутов через utun: $IN_TABLE"
[ "$IN_TABLE" -gt 20 ] && ok "маршруты действительно лежат в таблице" || fail "в таблице маршрутов через туннель всего $IN_TABLE"
[ -n "$TOOK" ] && [ "$TOOK" -le 15 ] && ok "туннель поднялся за $TOOK с" || echo "туннель поднимался ${TOOK:-?} с — долго"
sleep 120
alive "три минуты с включённым VPN"
[ "$(pid_of)" = "$FIRST_PID" ] || fail "с включённым VPN служба сменила pid: $FIRST_PID → $(pid_of)"
no_restarts "с включённым VPN"
route -n get default >/dev/null 2>&1 && ok "у Mac есть маршрут по умолчанию" || fail "у Mac пропал маршрут по умолчанию"

echo "=== 3. VPN выключен ==="
STATE="$STATE" python3 - <<'PY'
import json, os
path = os.path.join(os.environ["STATE"], "config.json")
config = json.load(open(path))
config["enabled"] = False
json.dump(config, open(path, "w"), ensure_ascii=False, indent=2)
PY
sleep 25
alive "после выключения"
[ "$(pid_of)" = "$FIRST_PID" ] || fail "после выключения служба сменила pid"
no_restarts "после выключения"
route -n get default >/dev/null 2>&1 && ok "маршрут по умолчанию на месте" || fail "после выключения нет маршрута по умолчанию"

echo "=== 4. Служба обновляется сама ==="
PUBLISHED="$(curl -fsSL --retry 3 https://github.com/viktorbeloglazov-design/vpn/releases/download/latest/mac-version.txt || true)"
if [ -z "$PUBLISHED" ]; then
    {
        echo "--- curl -v ---"
        curl -v --max-time 20 https://github.com/viktorbeloglazov-design/vpn/releases/download/latest/mac-version.txt 2>&1 | tail -25
        echo "--- route get github.com ---"
        route -n get github.com 2>&1
        echo "--- маршруты utun ---"
        netstat -rn -f inet | grep utun | head
        echo "--- DNS ---"
        scutil --dns | head -20
    } | annotate "Сеть после выключения"
fi
echo "Выложена версия: ${PUBLISHED:-не узнать}"
if [ -z "$PUBLISHED" ]; then
    fail "не узнать выложенную версию"
elif ! /usr/bin/python3 -c "import sys; a,b=[tuple(map(int,x.split('.'))) for x in sys.argv[1:]]; sys.exit(0 if b>=a else 1)" 3.7.0 "$PUBLISHED"; then
    # Выложенная служба старше той, что умеет обновляться сама: ставить
    # её значит откатиться на старую. Проверяем механизм иначе — служба
    # должна сказать, что свежая версия у неё уже есть.
    printf '%s' "9.9.9" > "$HELPER_DIR/version"
    launchctl kickstart -k "system/$LABEL"
    sleep 10
    touch "$STATE/obnovit-sejchas"
    for _ in $(seq 1 12); do
        [ -f "$STATE/obnovlenie.txt" ] && break
        sleep 10
    done
    if grep -q "свежая версия $PUBLISHED уже стоит" "$STATE/obnovlenie.txt" 2>/dev/null; then
        ok "служба сходила за версией и правильно решила, что обновлять нечего"
    else
        fail "служба не ответила на просьбу проверить обновление: $(cat "$STATE/obnovlenie.txt" 2>/dev/null || echo 'нет записи')"
    fi
    printf '%s' "$VERSION" > "$HELPER_DIR/version"
else
    # Выложенная умеет обновляться сама: притворяемся старее на шаг
    # и ждём, что служба скачает выложенную и встанет на неё.
    printf '%s' "3.7.0" > "$HELPER_DIR/version"
    [ "$PUBLISHED" = "3.7.0" ] && printf '%s' "3.6.9" > "$HELPER_DIR/version"
    launchctl kickstart -k "system/$LABEL"
    sleep 10
    touch "$STATE/obnovit-sejchas"
    for _ in $(seq 1 30); do
        [ "$(cat "$HELPER_DIR/version" 2>/dev/null)" = "$PUBLISHED" ] && break
        sleep 10
    done
    if [ "$(cat "$HELPER_DIR/version")" = "$PUBLISHED" ]; then
        ok "служба сама обновилась до $PUBLISHED: $(cat "$STATE/obnovlenie.txt" 2>/dev/null)"
        sleep 15
        alive "после самообновления"
    else
        fail "служба не обновилась: $(cat "$STATE/obnovlenie.txt" 2>/dev/null || echo 'нет записи')"
    fi
fi

echo
if [ "$FAILED" -ne 0 ]; then
    echo "ИТОГ: служба НЕ прошла проверку"
    exit 1
fi
echo "ИТОГ: служба ставится, живёт, держит туннель и обновляется сама"
