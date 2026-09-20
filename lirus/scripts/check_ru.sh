#!/usr/bin/env bash
#
# check_ru.sh — есть ли в прошивке Li Auto L9 (Li OS) скрытый русский язык.
#
# ТОЛЬКО ЧТЕНИЕ. Скрипт ничего не меняет в машине: он читает свойства
# системы, копирует установленные APK к себе на компьютер и смотрит,
# лежат ли внутри ресурсы values-ru. Никаких settings put, am, setprop,
# root и системных разделов.
#
# Запуск:
#   ./check_ru.sh                        # ключевые и фирменные пакеты
#   ./check_ru.sh --all                  # вообще всё, что установлено (долго)
#   ./check_ru.sh --out отчёт.md         # куда положить отчёт
#   ./check_ru.sh --serial ABC123        # если подключено несколько устройств
#
set -euo pipefail

ADB="${ADB:-adb}"
AAPT2="${AAPT2:-}"
SERIAL="${SERIAL:-}"
OUT="check_ru_report.md"
WORK=""
KEEP=0
SCAN_ALL=0
MAX_MB=400
LIMIT=0

usage() {
    cat <<'USAGE'
check_ru.sh — проверка скрытой русской локализации в прошивке Li Auto (Li OS).

  --serial SERIAL   какое устройство опрашивать (adb devices)
  --out FILE        файл отчёта, по умолчанию check_ru_report.md
  --work DIR        рабочий каталог для копий APK
  --all             смотреть все установленные пакеты, а не только ключевые
  --limit N         ограничить число пакетов (0 — без ограничения)
  --max-mb N        пропускать APK больше N мегабайт (по умолчанию 400)
  --keep            не удалять скачанные APK после разбора
  -h, --help        эта справка

Скрипт только читает. Ничего в машине не меняется.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --serial) SERIAL="${2:-}"; shift 2 ;;
        --out) OUT="${2:-}"; shift 2 ;;
        --work) WORK="${2:-}"; shift 2 ;;
        --all) SCAN_ALL=1; shift ;;
        --limit) LIMIT="${2:-0}"; shift 2 ;;
        --max-mb) MAX_MB="${2:-400}"; shift 2 ;;
        --keep) KEEP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Непонятный ключ: $1" >&2; usage >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf 'внимание: %s\n' "$*" >&2; }
die() { printf 'ошибка: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- инструменты

command -v "$ADB" >/dev/null 2>&1 || die "не найден adb. Поставьте Android Platform Tools и повторите."

find_aapt2() {
    if [ -n "$AAPT2" ] && [ -x "$AAPT2" ]; then return 0; fi
    if command -v aapt2 >/dev/null 2>&1; then AAPT2="$(command -v aapt2)"; return 0; fi
    for root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
        [ -n "$root" ] || continue
        [ -d "$root/build-tools" ] || continue
        candidate="$(ls -1 "$root"/build-tools/*/aapt2 2>/dev/null | sort | tail -1)"
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then AAPT2="$candidate"; return 0; fi
    done
    return 1
}

if ! find_aapt2; then
    die "не найден aapt2. Он лежит в Android SDK: \$ANDROID_HOME/build-tools/<версия>/aapt2.
     Поставьте «Android SDK Build-Tools» в SDK Manager или укажите путь: AAPT2=/путь/к/aapt2 $0"
fi

# ------------------------------------------------------------------ устройство

adb_args() {
    if [ -n "$SERIAL" ]; then printf '%s\n' "-s" "$SERIAL"; fi
}

sh_cmd() {
    # Выполнить команду на устройстве и убрать возврат каретки.
    if [ -n "$SERIAL" ]; then
        "$ADB" -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r' || true
    else
        "$ADB" shell "$@" 2>/dev/null | tr -d '\r' || true
    fi
}

pull_file() {
    # $1 — путь в машине, $2 — куда положить
    if [ -n "$SERIAL" ]; then
        "$ADB" -s "$SERIAL" pull "$1" "$2" >/dev/null 2>&1
    else
        "$ADB" pull "$1" "$2" >/dev/null 2>&1
    fi
}

step "Ищу устройство"
DEVICES="$("$ADB" devices 2>/dev/null | tr -d '\r' | awk 'NR > 1 && $2 == "device" { print $1 }')"
[ -n "$DEVICES" ] || die "adb не видит ни одного устройства. Включите отладку по USB и разрешите подключение на экране машины."
if [ -z "$SERIAL" ]; then
    COUNT="$(printf '%s\n' "$DEVICES" | wc -l | tr -d ' ')"
    [ "$COUNT" = "1" ] || die "подключено несколько устройств, укажите нужное: --serial <из adb devices>"
    SERIAL="$(printf '%s\n' "$DEVICES" | head -1)"
fi
say "устройство: $SERIAL"

if [ -z "$WORK" ]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/check_ru.XXXXXX")"
fi
mkdir -p "$WORK/apk"
say "рабочий каталог: $WORK"

step "Читаю сведения о системе"
ANDROID_RELEASE="$(sh_cmd getprop ro.build.version.release | head -1)"
ANDROID_SDK="$(sh_cmd getprop ro.build.version.sdk | head -1)"
BUILD_ID="$(sh_cmd getprop ro.build.display.id | head -1)"
FINGERPRINT="$(sh_cmd getprop ro.build.fingerprint | head -1)"
MODEL="$(sh_cmd getprop ro.product.model | head -1)"
DEVICE_NAME="$(sh_cmd getprop ro.product.device | head -1)"
SYSTEM_LOCALES="$(sh_cmd settings get system system_locales | head -1)"
PERSIST_LOCALE="$(sh_cmd getprop persist.sys.locale | head -1)"
PRODUCT_LOCALE="$(sh_cmd getprop ro.product.locale | head -1)"
LOCALE_PROPS="$(sh_cmd getprop | grep -i locale || true)"
AM_CONFIG="$(sh_cmd am get-config | head -20 || true)"
OVERLAYS="$(sh_cmd cmd overlay list 2>/dev/null | head -60 || true)"
OVERLAY_FILES="$(sh_cmd ls -1 /product/overlay /vendor/overlay /system/overlay 2>/dev/null | head -60 || true)"

say "Android: ${ANDROID_RELEASE:-?} (SDK ${ANDROID_SDK:-?}), сборка: ${BUILD_ID:-?}"
say "модель: ${MODEL:-?} / ${DEVICE_NAME:-?}"
say "system_locales: ${SYSTEM_LOCALES:-нет}"
say "persist.sys.locale: ${PERSIST_LOCALE:-нет}"

# ------------------------------------------------------------------- пакеты

step "Собираю список пакетов"
PKG_LIST="$WORK/packages.txt"
sh_cmd pm list packages -f \
    | sed -e 's/^package://' \
    | awk -F= 'NF >= 2 { path = $1; pkg = $NF; sub("=" pkg "$", "", path); print pkg "\t" path }' \
    | sort -u > "$PKG_LIST"

TOTAL_PKGS="$(wc -l < "$PKG_LIST" | tr -d ' ')"
say "всего установлено пакетов: $TOTAL_PKGS"

# Ключевые: рамка системы, настройки, оболочка, рабочий стол.
KEY_RE='com\.android\.settings|com\.android\.systemui|launcher|com\.android\.car|android\.car\.'
# Фирменные пакеты Li Auto (Chehejia — прежнее имя компании).
LI_RE='chj|lixiang|liauto|li\.auto|ideal|理想'
# Климат, приборка, камеры, мультимедиа.
CAR_RE='hvac|climate|aircond|cluster|meter|instrument|dashboard|ivi|avm|surround|camera|dvr|media|music|navi'

SELECTED="$WORK/selected.txt"
if [ "$SCAN_ALL" = "1" ]; then
    cp "$PKG_LIST" "$SELECTED"
else
    grep -Ei "$KEY_RE|$LI_RE|$CAR_RE" "$PKG_LIST" > "$SELECTED" || true
fi

if [ "$LIMIT" != "0" ]; then
    head -"$LIMIT" "$SELECTED" > "$SELECTED.cut" && mv "$SELECTED.cut" "$SELECTED"
fi
SELECTED_COUNT="$(wc -l < "$SELECTED" | tr -d ' ')"
say "к разбору отобрано: $SELECTED_COUNT"

# ------------------------------------------------------------------- разбор

# Считает строковые ресурсы по языкам внутри APK.
# Печатает: ru en zh base
count_strings() {
    "$AAPT2" dump resources "$1" 2>/dev/null | awk '
        /^[ \t]*resource 0x/ {
            n = split($3, parts, "/")
            type = (n > 1 ? parts[1] : "")
            next
        }
        type != "string" { next }
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (substr(line, 1, 1) != "(") next
            stop = index(line, ")")
            if (stop < 2) next
            cfg = substr(line, 2, stop - 2)
            if (cfg == "") { base++; next }
            if (cfg ~ /(^|-)(b\+)?ru([+-]|$)/) { ru++; next }
            if (cfg ~ /(^|-)(b\+)?en([+-]|$)/) { en++; next }
            if (cfg ~ /(^|-)(b\+)?zh([+-]|$)/) { zh++; next }
        }
        END { printf "%d %d %d %d\n", ru + 0, en + 0, zh + 0, base + 0 }
    '
}

# Есть ли вообще конфигурация ru в ресурсах APK.
has_ru_config() {
    "$AAPT2" dump configurations "$1" 2>/dev/null \
        | tr -d '\r' \
        | grep -Eq '(^|-)(b\+)?ru([+-]|$)' && return 0
    return 1
}

ROWS="$WORK/rows.tsv"
: > "$ROWS"

analyze_one() {
    pkg="$1"
    remote="$2"
    label="$3"

    size_kb="$(sh_cmd ls -l "$remote" 2>/dev/null | awk 'NR == 1 { print int($5 / 1024) }')"
    if [ -n "${size_kb:-}" ] && [ "$size_kb" -gt $((MAX_MB * 1024)) ] 2>/dev/null; then
        printf '%s\t%s\t%s\tпропущен\t0\t0\t0\t0\t-\n' "$pkg" "$label" "$remote" >> "$ROWS"
        warn "$pkg: APK больше ${MAX_MB} МБ, пропускаю"
        return
    fi

    local_apk="$WORK/apk/$(printf '%s' "$pkg" | tr '/:' '__').apk"
    if ! pull_file "$remote" "$local_apk"; then
        printf '%s\t%s\t%s\tне скачан\t0\t0\t0\t0\t-\n' "$pkg" "$label" "$remote" >> "$ROWS"
        warn "$pkg: не удалось скачать $remote (нет доступа)"
        return
    fi

    if has_ru_config "$local_apk"; then ru_cfg="да"; else ru_cfg="нет"; fi
    ru=0; en=0; zh=0; base=0
    counts="$(count_strings "$local_apk")"
    IFS=' ' read -r ru en zh base <<< "$counts"

    coverage="$(awk -v ru="$ru" -v base="$base" 'BEGIN { if (base > 0) printf "%.1f", ru * 100 / base; else print "0.0" }')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$pkg" "$label" "$remote" "$ru_cfg" "$ru" "$en" "$zh" "$base" "$coverage" >> "$ROWS"
    say "  $pkg: values-ru $ru_cfg, русских строк $ru из $base (${coverage}%)"

    [ "$KEEP" = "1" ] || rm -f "$local_apk"
}

step "Разбираю рамку системы (framework-res)"
analyze_one "framework-res" "/system/framework/framework-res.apk" "рамка системы"

step "Разбираю пакеты"
while IFS="$(printf '\t')" read -r pkg path; do
    [ -n "${pkg:-}" ] || continue
    [ -n "${path:-}" ] || continue
    label="прочее"
    case "$pkg" in
        *settings*|*systemui*|*launcher*) label="ключевой" ;;
    esac
    if printf '%s' "$pkg" | grep -Eqi "$LI_RE"; then label="Li Auto"; fi
    if printf '%s' "$pkg" | grep -Eqi "$CAR_RE"; then label="${label}, машина"; fi
    analyze_one "$pkg" "$path" "$label"
done < "$SELECTED"

# ------------------------------------------------------------------- отчёт

step "Пишу отчёт: $OUT"

KEY_COVERAGE="$(awk -F'\t' '$1 == "framework-res" { print $9 }' "$ROWS" | head -1)"
KEY_COVERAGE="${KEY_COVERAGE:-0.0}"
LI_MAX="$(awk -F'\t' '$2 ~ /Li Auto/ { if ($9 + 0 > max) max = $9 + 0 } END { printf "%.1f", max + 0 }' "$ROWS")"
UI_MAX="$(awk -F'\t' '$2 ~ /ключевой/ { if ($9 + 0 > max) max = $9 + 0 } END { printf "%.1f", max + 0 }' "$ROWS")"
WITH_RU="$(awk -F'\t' '$4 == "да" { n++ } END { print n + 0 }' "$ROWS")"
SCANNED="$(wc -l < "$ROWS" | tr -d ' ')"

VERDICT="НЕТ"
VERDICT_TEXT="Русских ресурсов в ключевых пакетах не нашлось — переключение языка даст в лучшем случае частично русские системные диалоги, а интерфейс машины останется как был. Второй этап (приложение-переключатель) смысла не имеет."
if awk -v k="$KEY_COVERAGE" -v li="$LI_MAX" -v ui="$UI_MAX" 'BEGIN { exit !(k >= 50 && (li >= 30 || ui >= 30)) }'; then
    VERDICT="ДА"
    VERDICT_TEXT="Русские ресурсы есть и в рамке системы, и в интерфейсных пакетах. Переключение языка должно дать осмысленно русское меню — второй этап имеет смысл."
elif awk -v k="$KEY_COVERAGE" 'BEGIN { exit !(k >= 50) }'; then
    VERDICT="ЧАСТИЧНО"
    VERDICT_TEXT="Русский есть в рамке системы (диалоги Android, клавиатура, системные сообщения), но фирменные экраны Li Auto не переведены. После переключения язык станет смешанным: часть по-русски, экраны машины — по-прежнему по-китайски. Решать вам, нужен ли такой промежуточный результат."
fi

{
    printf '# Проверка русского языка в прошивке Li Auto\n\n'
    printf '_Снято %s, только чтение: в машине ничего не менялось._\n\n' "$(date '+%Y-%m-%d %H:%M')"

    printf '## Машина\n\n'
    printf '| Что | Значение |\n|---|---|\n'
    printf '| Модель | `%s` / `%s` |\n' "${MODEL:-?}" "${DEVICE_NAME:-?}"
    printf '| Android | %s (SDK %s) |\n' "${ANDROID_RELEASE:-?}" "${ANDROID_SDK:-?}"
    printf '| Сборка | `%s` |\n' "${BUILD_ID:-?}"
    printf '| Отпечаток | `%s` |\n' "${FINGERPRINT:-?}"
    printf '| system_locales | `%s` |\n' "${SYSTEM_LOCALES:-нет}"
    printf '| persist.sys.locale | `%s` |\n' "${PERSIST_LOCALE:-нет}"
    printf '| ro.product.locale | `%s` |\n' "${PRODUCT_LOCALE:-нет}"
    printf '| Пакетов установлено | %s |\n' "$TOTAL_PKGS"
    printf '| Разобрано пакетов | %s |\n\n' "$SCANNED"

    printf '### Свойства с языком\n\n```\n%s\n```\n\n' "${LOCALE_PROPS:-нет}"
    printf '### Текущая конфигурация (am get-config)\n\n```\n%s\n```\n\n' "${AM_CONFIG:-нет}"
    printf '### Наложения ресурсов (RRO)\n\n```\n%s\n%s\n```\n\n' "${OVERLAYS:-нет}" "${OVERLAY_FILES:-}"

    printf '## Пакеты\n\n'
    printf '«Базовых» — строки без языкового уточнения (в китайской прошивке это обычно китайский).\n'
    printf 'Покрытие — сколько из них переведено на русский.\n\n'
    printf '| Пакет | Роль | values-ru | ru | en | zh | базовых | покрытие |\n'
    printf '|---|---|---|---:|---:|---:|---:|---:|\n'
    sort -t"$(printf '\t')" -k9 -nr "$ROWS" | awk -F'\t' '{ printf "| `%s` | %s | %s | %s | %s | %s | %s | %s%% |\n", $1, $2, $4, $5, $6, $7, $8, $9 }'
    printf '\n'

    printf '## Вывод\n\n'
    printf '**Русские ресурсы в ключевых пакетах: %s**\n\n' "$VERDICT"
    printf '%s\n\n' "$VERDICT_TEXT"
    printf -- '- рамка системы (`framework-res`): покрытие %s%%\n' "$KEY_COVERAGE"
    printf -- '- лучший из ключевых интерфейсных пакетов: %s%%\n' "$UI_MAX"
    printf -- '- лучший из фирменных пакетов Li Auto: %s%%\n' "$LI_MAX"
    printf -- '- пакетов, где вообще есть values-ru: %s из %s\n\n' "$WITH_RU" "$SCANNED"

    printf '## Чего не хватает\n\n'
    awk -F'\t' '$4 == "нет" && $8 + 0 > 200 { printf "- `%s` (%s): русских строк нет, базовых %s\n", $1, $2, $8 }' "$ROWS" | head -30
    printf '\n'

    printf '## Как это снято\n\n'
    printf '`%s`, только чтение: getprop, settings get, pm list packages, adb pull копий APK,\n' "$(basename "$0")"
    printf 'разбор ресурсов через `aapt2 dump resources`. Системные разделы не трогались,\n'
    printf 'root не требовался, в машине ничего не изменено.\n'
} > "$OUT"

step "Готово"
say "отчёт: $OUT"
say "вердикт: $VERDICT"
if [ "$KEEP" = "1" ]; then
    say "скачанные APK: $WORK/apk"
else
    rm -rf "$WORK/apk"
fi
