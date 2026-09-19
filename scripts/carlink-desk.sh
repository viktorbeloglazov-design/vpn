#!/bin/bash
# Стенд головного устройства: эмулятор машины на компьютере.
# Пробрасывает порт на телефон и запускает эмулятор.
#   ./scripts/carlink-desk.sh                     — экран 1280×720
#   ./scripts/carlink-desk.sh --size 1920x720     — другое разрешение
#   ./scripts/carlink-desk.sh --port 5300 --record поток.h264
set -uo pipefail

PORT=5288
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --port) PORT="$2"; ARGS+=("--port" "$2"); shift 2 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done
if [ ${#ARGS[@]} -eq 0 ] || [[ " ${ARGS[*]} " != *" --port "* ]]; then
    ARGS+=("--port" "$PORT")
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v gradle >/dev/null 2>&1; then
    echo "Нет gradle — поставьте его, эмулятор собирается им же." >&2
    exit 1
fi

if command -v adb >/dev/null 2>&1; then
    if adb devices | sed -n '2,$p' | grep -q "device$"; then
        # Телефон будет стучаться на свой 127.0.0.1 — трафик уйдёт по кабелю
        # отладки сюда, никакой общей сети не нужно.
        adb reverse "tcp:$PORT" "tcp:$PORT" && echo "порт $PORT проброшен на телефон"
    else
        echo "Телефон по adb не виден — проброс пропускаю (можно подключиться по Wi-Fi)."
    fi
else
    echo "Нет adb — проброс пропускаю (можно подключиться по Wi-Fi)."
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Нет ffmpeg — окно откроется без картинки, протокол и касания работать будут."
fi

cd "$ROOT/carlink" || exit 1
exec gradle --quiet --console=plain :headunit:run --args="${ARGS[*]}"
