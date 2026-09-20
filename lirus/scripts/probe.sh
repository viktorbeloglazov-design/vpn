#!/usr/bin/env bash
# LiRus — разведка головного устройства Li Auto L9 (Li OS / Android).
#
# Собирает всё, что нужно для выбора стратегии русификации, и складывает
# в probe_report.txt рядом со скриптом.
#
#   ./probe.sh                       подключение по USB
#   ./probe.sh 192.168.1.50          подключение по Wi-Fi (adb connect)
#   ./probe.sh 192.168.1.50:5555     то же, с явным портом
#   ./probe.sh --allow-changes       разрешить обратимые проверки (см. раздел 9)
#
# По умолчанию скрипт НИЧЕГО НЕ МЕНЯЕТ на машине: только читает.
# Проверки, которые что-то меняют, выполняются лишь с флагом --allow-changes,
# каждая возвращает исходное значение обратно.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT="$SCRIPT_DIR/probe_report.txt"
ALLOW_CHANGES=0
TARGET=""

for arg in "$@"; do
    case "$arg" in
        --allow-changes) ALLOW_CHANGES=1 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) TARGET="$arg" ;;
    esac
done

command -v adb >/dev/null 2>&1 || {
    echo "Не найден adb. macOS: brew install --cask android-platform-tools" >&2
    echo "Windows/Linux: пакет platform-tools с developer.android.com" >&2
    exit 1
}

# ---------- подключение ----------
if [ -n "$TARGET" ]; then
    case "$TARGET" in
        *:*) HOSTPORT="$TARGET" ;;
        *)   HOSTPORT="$TARGET:5555" ;;
    esac
    echo "==> Подключаюсь по Wi-Fi к $HOSTPORT"
    adb connect "$HOSTPORT" >/dev/null 2>&1
    sleep 1
fi

DEVICES="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
COUNT="$(printf '%s\n' "$DEVICES" | grep -c . || true)"

if [ "$COUNT" -eq 0 ]; then
    echo "Устройство не найдено." >&2
    echo >&2
    echo "Проверьте:" >&2
    echo "  1. В машине включена отладка по USB (инженерное меню Li OS)." >&2
    echo "  2. Кабель воткнут в порт передачи данных, а не только для зарядки." >&2
    echo "  3. На экране машины подтверждён запрос «Разрешить отладку?»." >&2
    echo "  4. Для Wi-Fi: машина и компьютер в одной сети, порт 5555 открыт." >&2
    echo >&2
    echo "Список того, что видит adb сейчас:" >&2
    adb devices -l >&2
    exit 1
fi

if [ "$COUNT" -gt 1 ]; then
    echo "Найдено несколько устройств:" >&2
    printf '%s\n' "$DEVICES" >&2
    echo "Укажите нужное: ANDROID_SERIAL=<серийник> $0 $*" >&2
    [ -z "${ANDROID_SERIAL:-}" ] && exit 1
fi

SERIAL="${ANDROID_SERIAL:-$(printf '%s\n' "$DEVICES" | head -1)}"
export ANDROID_SERIAL="$SERIAL"
echo "==> Устройство: $SERIAL"

# ---------- вывод ----------
: > "$REPORT"
sec() { printf '\n\n========== %s ==========\n' "$*" | tee -a "$REPORT"; }
note() { printf '%s\n' "$*" | tee -a "$REPORT"; }

# run "<команда для adb shell>" [пояснение]
run() {
    local cmd="$1" label="${2:-}"
    [ -n "$label" ] && printf '\n--- %s\n' "$label" >> "$REPORT"
    printf '$ adb shell %s\n' "$cmd" >> "$REPORT"
    local out
    out="$(adb shell "$cmd" 2>&1)"
    if [ -z "$out" ]; then
        printf '(пусто)\n' >> "$REPORT"
    else
        printf '%s\n' "$out" >> "$REPORT"
    fi
    printf '%s' "$out"
}

# Тихий вариант: только вернуть значение, в отчёт не писать.
q() { adb shell "$1" 2>/dev/null; }

note "LiRus — отчёт разведки"
note "Снят: $(date '+%Y-%m-%d %H:%M:%S')"
note "Устройство adb: $SERIAL"
note "Версия adb: $(adb version | head -1)"

# ---------- 1. устройство ----------
sec "1. УСТРОЙСТВО И СИСТЕМА"
run "getprop ro.product.manufacturer" "Производитель" >/dev/null
run "getprop ro.product.brand" "Бренд" >/dev/null
run "getprop ro.product.model" "Модель" >/dev/null
run "getprop ro.product.device" "Устройство" >/dev/null
run "getprop ro.build.version.release" "Android" >/dev/null
SDK="$(q 'getprop ro.build.version.sdk' | tr -d '\r')"
run "getprop ro.build.version.sdk" "SDK" >/dev/null
run "getprop ro.build.version.security_patch" "Патч безопасности" >/dev/null
run "getprop ro.build.fingerprint" "Отпечаток сборки" >/dev/null
run "getprop ro.build.display.id" "Идентификатор сборки" >/dev/null
run "getprop ro.product.cpu.abi" "Основной ABI" >/dev/null
run "getprop ro.product.cpu.abilist" "Все ABI" >/dev/null
run "getprop ro.build.type" "Тип сборки (user/userdebug/eng)" >/dev/null
run "getprop ro.debuggable" "ro.debuggable" >/dev/null
run "getprop ro.secure" "ro.secure" >/dev/null
run "getenforce" "SELinux" >/dev/null
run "uname -a" "Ядро" >/dev/null
run "pm list features | grep -i -E 'automotive|car|cluster'" "Автомобильные функции" >/dev/null

# ---------- 2. экраны ----------
sec "2. ЭКРАНЫ (multi-display)"
note "Важно: у L9 несколько экранов — центральный, пассажирский, задний."
note "Для каждого нужны id, разрешение и плотность: оверлей рисуется отдельно на каждом."
run "dumpsys display | grep -E 'mDisplayId|uniqueId|deviceProductInfo|real [0-9]|density|mType|flags' | head -80" "Сводка по дисплеям" >/dev/null
run "wm size" "Размер основного экрана" >/dev/null
run "wm density" "Плотность основного экрана" >/dev/null
run "dumpsys display | grep -c 'Display id'" "Сколько дисплеев найдено" >/dev/null
run "cmd display get-displays 2>/dev/null || echo 'команда недоступна'" "cmd display get-displays" >/dev/null

# ---------- 3. локали ----------
sec "3. ЛОКАЛИ — есть ли русский в системе"
note "Если русская локаль присутствует, возможен вариант A: включить штатно,"
note "без оверлеев и перехвата. Это лучший исход."
run "getprop ro.product.locale" "Локаль по умолчанию" >/dev/null
run "getprop ro.product.locale.language" "Язык" >/dev/null
run "getprop ro.product.locale.region" "Регион" >/dev/null
run "getprop persist.sys.locale" "Текущая локаль" >/dev/null
run "settings get system system_locales" "system_locales" >/dev/null
run "getprop | grep -i locale" "Все свойства с locale" >/dev/null
run "am get-config" "Текущая конфигурация (locale=)" >/dev/null
note ""
note "Проверка наличия русских ресурсов во framework:"
run "ls /system/framework/framework-res.apk 2>/dev/null && echo 'framework-res.apk на месте'" "" >/dev/null
run "cmd locale --help 2>&1 | head -5" "Доступна ли cmd locale (API 33+)" >/dev/null

# ---------- 4. root ----------
sec "4. ROOT И СИСТЕМНЫЕ ПРАВА"
note "Нужно для варианта B (RRO-оверлеи с русскими строками)."
run "id" "Кто мы в shell" >/dev/null
run "which su || echo 'su не найден'" "Наличие su" >/dev/null
run "su -c id 2>&1 | head -2" "Попытка su" >/dev/null
echo "" >> "$REPORT"
printf '$ adb root\n' >> "$REPORT"
adb root 2>&1 | head -2 >> "$REPORT"
sleep 1
adb wait-for-device 2>/dev/null
run "id" "Кто мы после adb root" >/dev/null
adb unroot >/dev/null 2>&1

# ---------- 5. установка APK ----------
sec "5. МОЖНО ЛИ СТАВИТЬ ПРИЛОЖЕНИЯ"
note "Проверяем безопасно: создаём пустую сессию установки и сразу отменяем."
note "Ничего не устанавливается."
SESSION="$(q 'pm install-create -r' | tr -d '\r')"
printf '$ adb shell pm install-create -r\n%s\n' "$SESSION" >> "$REPORT"
SID="$(printf '%s' "$SESSION" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')"
if [ -n "$SID" ]; then
    note "УСТАНОВКА РАЗРЕШЕНА — сессия $SID создана, отменяю."
    q "pm install-abandon $SID" >/dev/null
else
    note "УСТАНОВКА ЗАБЛОКИРОВАНА или требует подтверждения на экране машины."
fi
run "settings get global install_non_market_apps" "Установка из неизвестных источников" >/dev/null
run "dumpsys device_policy | head -30" "Политики устройства (MDM-ограничения)" >/dev/null

# ---------- 6. права и команды ----------
sec "6. ДОСТУПНОСТЬ КОМАНД ДЛЯ ВЫДАЧИ ПРАВ"
note "От этого зависит, получится ли выдать права одной командой после установки."
run "cmd appops --help 2>&1 | head -3" "cmd appops" >/dev/null
run "cmd overlay list 2>&1 | head -20" "cmd overlay (нужен для RRO, вариант B)" >/dev/null
run "pm --help 2>&1 | grep -c grant" "pm grant доступен (1 = да)" >/dev/null
CUR_TZ="$(q 'settings get global lirus_probe_test' | tr -d '\r')"
if [ "$ALLOW_CHANGES" = "1" ]; then
    note ""
    note "Проверка записи в settings (флаг --allow-changes):"
    q "settings put global lirus_probe_test 1" >/dev/null
    VAL="$(q 'settings get global lirus_probe_test' | tr -d '\r')"
    if [ "$VAL" = "1" ]; then
        note "settings put РАБОТАЕТ — права выдать сможем."
    else
        note "settings put НЕ РАБОТАЕТ (получено: '$VAL')."
    fi
    q "settings delete global lirus_probe_test" >/dev/null
    note "Тестовое значение удалено."
else
    note ""
    note "Проверка записи в settings пропущена. Запустите с --allow-changes,"
    note "чтобы проверить (скрипт запишет и тут же удалит тестовый ключ)."
fi

# ---------- 7. accessibility ----------
sec "7. ACCESSIBILITY И ОВЕРЛЕИ"
note "Основа варианта C: служба доступности читает интерфейс, оверлей рисует перевод."
run "settings get secure accessibility_enabled" "accessibility_enabled" >/dev/null
run "settings get secure enabled_accessibility_services" "Включённые службы доступности" >/dev/null
run "pm list packages -d | head -20" "Отключённые пакеты" >/dev/null
run "dumpsys accessibility | head -40" "Состояние подсистемы доступности" >/dev/null
run "cmd appops query-op SYSTEM_ALERT_WINDOW allow 2>&1 | head -20" "Кому разрешён показ поверх других окон" >/dev/null

# ---------- 8. пакеты ----------
sec "8. ПАКЕТЫ LI AUTO — что переводить"
note "Li Auto (компания 车和家 / Chehejia) обычно использует префиксы"
note "com.chj.*, com.lixiang.*, com.liauto.*, com.halo.*."
run "pm list packages | wc -l" "Всего пакетов" >/dev/null
run "pm list packages | grep -i -E 'chj|lixiang|liauto|halo|chehejia' | sort" "Пакеты Li Auto" >/dev/null
run "pm list packages -s | sort | head -100" "Системные пакеты (первые 100)" >/dev/null
run "pm list packages -3 | sort" "Сторонние пакеты" >/dev/null
run "cmd package resolve-activity -c android.intent.category.HOME 2>/dev/null | head -20" "Лаунчер (главный экран машины)" >/dev/null
run "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp'" "Активное окно прямо сейчас" >/dev/null
run "pm list packages | grep -i 'com.google.android.gms' || echo 'GMS отсутствует'" "Google Play Services" >/dev/null

# ---------- 9. вердикт ----------
sec "9. ПРЕДВАРИТЕЛЬНЫЙ ВЕРДИКТ"
HAS_RU=0
if q 'getprop | grep -i locale' | grep -qi 'ru[-_]\?RU\|\bru\b'; then HAS_RU=1; fi
if q 'settings get system system_locales' | grep -qi 'ru'; then HAS_RU=1; fi
HAS_ROOT=0
if q 'which su' | grep -q 'su'; then HAS_ROOT=1; fi
CAN_INSTALL=0
[ -n "$SID" ] && CAN_INSTALL=1
HAS_OVERLAY_CMD=0
if q 'cmd overlay list' | grep -q '.'; then HAS_OVERLAY_CMD=1; fi
# Сама по себе доступность cmd overlay ничего не решает: она есть почти везде.
# Установить RRO можно только с root либо на отладочной сборке.
BUILD_TYPE="$(q 'getprop ro.build.type' | tr -d '\r')"
DEBUGGABLE="$(q 'getprop ro.debuggable' | tr -d '\r')"
CAN_RRO=0
if [ "$HAS_ROOT" = "1" ] || [ "$BUILD_TYPE" = "userdebug" ] || [ "$BUILD_TYPE" = "eng" ] || [ "$DEBUGGABLE" = "1" ]; then
    CAN_RRO=1
fi

note "Русская локаль в системе:      $([ $HAS_RU = 1 ] && echo 'НАЙДЕНА' || echo 'не найдена')"
note "Root (su):                     $([ $HAS_ROOT = 1 ] && echo 'ЕСТЬ' || echo 'нет')"
note "Установка приложений:          $([ $CAN_INSTALL = 1 ] && echo 'разрешена' || echo 'под вопросом')"
note "cmd overlay (команда):         $([ $HAS_OVERLAY_CMD = 1 ] && echo 'доступна' || echo 'недоступна')"
note "Тип сборки:                    ${BUILD_TYPE:-неизвестен} (ro.debuggable=${DEBUGGABLE:-?})"
note "Можно ставить RRO:             $([ $CAN_RRO = 1 ] && echo 'да' || echo 'нет — нужен root или отладочная сборка')"
note "SDK:                           ${SDK:-неизвестен}"
note ""
if [ $HAS_RU = 1 ]; then
    note "РЕКОМЕНДАЦИЯ: вариант A — русская локаль в системе есть."
    note "Скорее всего достаточно переключить её и закрепить при загрузке."
elif [ $CAN_RRO = 1 ]; then
    note "РЕКОМЕНДАЦИЯ: вариант B — подменить строки через RRO-оверлеи,"
    note "плюс вариант C для того, что не покрывается ресурсами."
else
    note "РЕКОМЕНДАЦИЯ: вариант C — служба доступности плюс оверлей-переводчик."
fi
note ""
note "Отчёт сохранён: $REPORT"

echo
echo "==> Готово. Отчёт: $REPORT"
echo "==> Пришлите его целиком — по нему выберем стратегию."
