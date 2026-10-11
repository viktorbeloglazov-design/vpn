#!/bin/bash
# Проверка туннеля X-Ray на эмуляторе Android.
#
#   scripts/ci/check-android-xray.sh путь/к/universal.apk
#
# Сервер X-Ray уже запущен на этом же компьютере (127.0.0.1:18443),
# эмулятор видит его как 10.0.2.2. Ключ одноразовый: UUID в XRAY_UUID.
# Проверяем по-честному: ставим APK, загружаем ключ ссылкой, нажимаем
# кнопку и смотрим, что запросы с телефона доходят до сервера.
set -uo pipefail

APK="${1:?укажите APK}"
SERVER_LOG="${SERVER_LOG:?нужен журнал сервера}"
FAILED=0
fail() { echo "ПРОВАЛ: $*"; echo "::error::$*"; FAILED=1; }
ok()   { echo "в порядке: $*"; }

annotate() {
    local title="$1" text
    text="$(cat | tail -n 60 | sed -e 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
    [ -n "$text" ] && echo "::notice title=$title::$text"
}

notes() {
    adb logcat -d 2>/dev/null | grep -iE "qpvpn|xray|GoLog|tun2socks|VpnService|FATAL|Abort message|F DEBUG|F libc|panic|fatal error" \
        | grep -v "uiautomator" | tail -n 60 | annotate "Журнал телефона"
    adb logcat -d -b crash 2>/dev/null | tail -n 60 | annotate "Падения"
    tail -n 40 "$SERVER_LOG" | annotate "Журнал сервера X-Ray"
}
trap notes EXIT

adb wait-for-device
adb shell getprop ro.product.cpu.abilist

echo "=== Установка ==="
if ! adb install -r -g "$APK"; then
    fail "APK не установился на эмулятор"
    exit 1
fi
adb shell pm grant kz.qpvpn android.permission.POST_NOTIFICATIONS 2>/dev/null || true
# Разрешение на VPN, которое человек даёт кнопкой «ОК» в системном окне.
adb shell appops set kz.qpvpn ACTIVATE_VPN allow

echo "=== Ключ ссылкой ==="
LINK="vless://$XRAY_UUID@10.0.2.2:18443?type=tcp&security=none&encryption=none#CI-XRay"
adb shell "am start -W -a android.intent.action.VIEW -d '$LINK' kz.qpvpn"
sleep 6

tap_by_description() {
    local wanted="$1"
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
    python3 - "$wanted" <<'PY'
import re, sys
wanted = sys.argv[1]
text = open("/tmp/ui.xml", encoding="utf-8").read()
for node in re.finditer(r'<node [^>]*>', text):
    n = node.group(0)
    if f'content-desc="{wanted}"' in n or f'text="{wanted}"' in n:
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        x1, y1, x2, y2 = map(int, b.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
}

echo "=== Включаю ==="
POINT=""
for _ in $(seq 1 10); do
    POINT="$(tap_by_description "Включить")"
    [ -n "$POINT" ] && break
    sleep 2
done
if [ -z "$POINT" ]; then
    fail "кнопка «Включить» не нашлась на экране"
    grep -o 'text="[^"]*"' /tmp/ui.xml | head -30 | annotate "Что на экране"
    exit 1
fi
adb shell input tap $POINT

# «Подключён» приложение пишет только после того, как проверочный
# запрос сходил через сервер и вернулся.
screen_has() {
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
    grep -q "text=\"$1\"" /tmp/ui.xml
}
CONNECTED=""
for _ in $(seq 1 20); do
    if screen_has "Подключён"; then CONNECTED=1; break; fi
    sleep 3
done
if [ -n "$CONNECTED" ]; then
    ok "приложение пишет «Подключён»: сервер ответил на проверку"
else
    fail "за минуту приложение не подключилось"
    grep -o 'text="[^"]*"' /tmp/ui.xml | grep -v 'text=""' | head -30 | annotate "Что на экране"
fi

TUN="$(adb shell ip -o addr show 2>/dev/null | grep 172.19.0.1 | awk '{print $2}')"
[ -n "$TUN" ] && ok "туннель системы поднят ($TUN)" || fail "туннеля 172.19.0.1 на телефоне нет"

echo "=== Трафик другой программы ==="
# Запрос из оболочки телефона — это не наше приложение, его пакеты
# идут через туннель системы: tun2socks → xray → сервер.
REPLY="$(adb shell "printf 'GET / HTTP/1.0\r\nHost: example.com\r\n\r\n' | toybox nc -w 15 example.com 80 | head -1" 2>&1)"
echo "Ответ: $REPLY"
case "$REPLY" in
    HTTP/*) ok "сайт открылся с телефона" ;;
    *) fail "сайт с телефона не открылся: $REPLY" ;;
esac
sleep 2
# Адрес телефон узнаёт сам (через тот же туннель), поэтому сервер видит
# не имя, а адрес — ищем соединение на порт 80.
if grep -E "accepted tcp:[^ ]+:80( |$)" "$SERVER_LOG" >/dev/null; then
    ok "запрос прошёл через сервер X-Ray ($(grep -oE "accepted tcp:[^ ]+:80" "$SERVER_LOG" | tail -1))"
else
    fail "в журнале сервера нет соединения на порт 80 — трафик шёл мимо туннеля"
fi

echo
if [ "$FAILED" -ne 0 ]; then
    echo "ИТОГ: X-Ray на Android НЕ прошёл проверку"
    exit 1
fi
echo "ИТОГ: X-Ray на Android поднимается и пропускает трафик через сервер"
