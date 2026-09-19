#!/bin/bash
# Сервисы Google и настоящий Android Auto на телефон без них.
#
#   ./scripts/carlink-gms.sh check          что стоит, чего нет, что качать
#   ./scripts/carlink-gms.sh install ПАПКА  поставить пакеты из папки
#   ./scripts/carlink-gms.sh id             идентификатор GSF и ссылка регистрации
#   ./scripts/carlink-gms.sh auto ПАПКА     всё подряд: проверка, установка, перезагрузка
#
# Телефон подключён к компьютеру по adb, отладка по USB включена.
set -uo pipefail

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }
# Не называем эту функцию head: ниже нужен настоящий head.
title() { printf "\n\033[1m%s\033[0m\n" "$1"; }

GSF="com.google.android.gsf"
GMS="com.google.android.gms"
STORE="com.android.vending"
AUTO="com.google.android.projection.gearhead"
SEARCH="com.google.android.googlequicksearchbox"

require_device() {
    command -v adb >/dev/null 2>&1 || { bad "нет adb — поставьте platform-tools"; exit 1; }
    if [ "$(adb devices | sed -n '2,$p' | grep -c "device$")" -eq 0 ]; then
        bad "телефон не виден по adb: включите отладку по USB и подтвердите запрос на экране"
        exit 1
    fi
}

prop() { adb shell getprop "$1" | tr -d '\r'; }

version_of() {
    adb shell dumpsys package "$1" 2>/dev/null | tr -d '\r' | grep -m1 "versionName=" | cut -d= -f2
}

installed() {
    adb shell pm list packages 2>/dev/null | tr -d '\r' | grep -qx "package:$1"
}

report_package() {
    local name="$1" title="$2"
    if installed "$name"; then
        ok "$title — $(version_of "$name")"
        return 0
    fi
    bad "$title не установлен ($name)"
    return 1
}

cmd_check() {
    require_device
    title "Телефон"
    echo "  $(prop ro.product.manufacturer) $(prop ro.product.model)"
    echo "  Android $(prop ro.build.version.release), API $(prop ro.build.version.sdk)"
    echo "  процессор: $(prop ro.product.cpu.abi)"
    echo "  плотность экрана: $(adb shell wm density | tr -d '\r' | tail -1)"

    title "Что установлено"
    report_package "$GSF" "Google Services Framework"; local a=$?
    report_package "$GMS" "Сервисы Google Play"; local b=$?
    report_package "$STORE" "Play Маркет"; local c=$?
    report_package "$AUTO" "Android Auto"; local d=$?
    installed "$SEARCH" && ok "Приложение Google (голосовой помощник)" || warn "Приложения Google нет — Android Auto будет без голосового помощника"

    title "Что качать"
    local abi sdk
    abi="$(prop ro.product.cpu.abi)"
    sdk="$(prop ro.build.version.sdk)"
    if [ $a -ne 0 ] || [ $b -ne 0 ] || [ $c -ne 0 ]; then
        cat <<TEXT
  Нужны три пакета — именно в таком порядке:
    1. $GSF      Google Services Framework
    2. $GMS      Google Play services
    3. $STORE              Google Play Store

  Выбирать варианты по этому телефону:
    процессор  $abi
    Android    API $sdk и ниже
    экран      nodpi (подходит любому)

  Сервисы Play сейчас раздают набором файлов (base + split). Такой набор
  (.apkm, .xapk или папка со split_config_*.apk) скрипт поставит сам.
TEXT
    else
        ok "сервисы Google на месте"
    fi
    if [ $d -ne 0 ]; then
        echo "  Android Auto ставится последним и лучше из Play Маркета:"
        echo "    $AUTO"
    fi

    title "Дальше"
    if [ $b -eq 0 ] && [ $c -eq 0 ]; then
        cat <<'TEXT'
  1. Войдите в аккаунт Google в Play Маркете.
  2. Play Маркет → «Настройки» → «О приложении» → «Сертификация Play Protect».
     Если написано «не сертифицировано» — зарегистрируйте телефон:
     ./scripts/carlink-gms.sh id
  3. Поставьте Android Auto из Play Маркета.
  4. В Android Auto: «Настройки» → десять раз нажать на версию → режим
     разработчика → «Запускать Android Auto по USB».
TEXT
    else
        echo "  Скачайте пакеты и поставьте их:"
        echo "    ./scripts/carlink-gms.sh install ПАПКА-С-ФАЙЛАМИ"
    fi
}

# Один пакет: либо обычный apk, либо набор файлов.
install_one() {
    local target="$1"
    case "$target" in
        *.apkm|*.xapk|*.zip)
            local tmp
            tmp="$(mktemp -d)"
            unzip -q -o "$target" -d "$tmp" || { bad "не распаковался: $target"; return 1; }
            local parts=()
            while IFS= read -r part; do parts+=("$part"); done < <(find "$tmp" -name "*.apk" | sort)
            if [ ${#parts[@]} -eq 0 ]; then
                bad "внутри $target нет apk"
                rm -rf "$tmp"
                return 1
            fi
            echo "  ставлю $(basename "$target") (${#parts[@]} файл(ов))"
            adb install-multiple -r -d "${parts[@]}" >/dev/null 2>&1
            local code=$?
            rm -rf "$tmp"
            return $code
            ;;
        *.apk)
            echo "  ставлю $(basename "$target")"
            adb install -r -d "$target" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Из папки берём файлы в правильном порядке: сначала framework, потом сервисы.
cmd_install() {
    require_device
    local dir="${1:-}"
    [ -d "$dir" ] || { bad "укажите папку с файлами: ./scripts/carlink-gms.sh install ~/Downloads/gms"; exit 1; }

    title "Установка из $dir"
    local order=("gsf" "services" "gms" "vending" "store" "market" "gearhead" "auto" "quicksearch")
    local done_files=()

    for key in "${order[@]}"; do
        while IFS= read -r file; do
            case " ${done_files[*]} " in *" $file "*) continue ;; esac
            done_files+=("$file")
            if install_one "$file"; then ok "$(basename "$file")"; else bad "$(basename "$file") — не встало"; fi
        done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.apk" -o -iname "*.apkm" -o -iname "*.xapk" \) -iname "*${key}*" | sort)
    done

    # Всё, что не подошло ни под одно имя, ставим в конце.
    while IFS= read -r file; do
        case " ${done_files[*]} " in *" $file "*) continue ;; esac
        done_files+=("$file")
        if install_one "$file"; then ok "$(basename "$file")"; else bad "$(basename "$file") — не встало"; fi
    done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.apk" -o -iname "*.apkm" -o -iname "*.xapk" \) | sort)

    if [ ${#done_files[@]} -eq 0 ]; then
        bad "в папке нет ни одного apk/apkm/xapk"
        exit 1
    fi

    title "Проверка после установки"
    report_package "$GSF" "Google Services Framework"
    report_package "$GMS" "Сервисы Google Play"
    report_package "$STORE" "Play Маркет"
    echo
    echo "  Перезагрузите телефон: adb reboot"
}

cmd_id() {
    require_device
    title "Идентификатор устройства (GSF ID)"
    local raw value
    raw="$(adb shell "content query --uri content://com.google.android.gsf.gservices --where \"name='android_id'\"" 2>/dev/null | tr -d '\r')"
    value="$(echo "$raw" | sed -n 's/.*value=\([0-9]*\).*/\1/p' | head -1)"
    if [ -n "$value" ]; then
        ok "$value"
        echo
        echo "  Откройте https://www.google.com/android/uncertified/ , войдите тем же"
        echo "  аккаунтом Google, вставьте это число и нажмите «Зарегистрировать»."
        echo "  Через несколько минут перезагрузите телефон."
    else
        warn "не прочитался (Android не дал доступ к провайдеру)"
        echo "  Тот же номер показывает экран «Сертификация» в приложении CarLink,"
        echo "  либо любое приложение вида «Device ID» из Play Маркета."
        echo "  Ответ провайдера: ${raw:-пусто}"
    fi
}

cmd_auto() {
    cmd_check
    cmd_install "${1:-}"
    title "Перезагружаю телефон"
    adb reboot
    echo "  Ждите загрузки, потом: ./scripts/carlink-gms.sh id"
}

case "${1:-check}" in
    check) cmd_check ;;
    install) cmd_install "${2:-}" ;;
    id) cmd_id ;;
    auto) cmd_auto "${2:-}" ;;
    *) echo "check | install ПАПКА | id | auto ПАПКА" ;;
esac
