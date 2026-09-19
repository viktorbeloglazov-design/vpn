#!/bin/bash
# Собирает библиотеку AmneziaWG для Android из исходников Amnezia.
#
#   scripts/build-awg.sh android/app/libs/awg-tunnel.aar
#
# Протокол AmneziaWG — это WireGuard с маскировкой: мусорные пакеты и
# подменённые заголовки, чтобы провайдер не опознал туннель. Обычная
# библиотека WireGuard такие параметры не принимает, поэтому нужна эта.
set -euo pipefail

OUT="${1:?укажите, куда положить .aar}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Клонирую исходники (с подмодулями awg-go и awg-tools)"
git clone --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/amnezia-vpn/amneziawg-android.git "$WORK/awg"

echo "==> Собираю"
cd "$WORK/awg"
chmod +x gradlew 2>/dev/null || true
./gradlew :tunnel:assembleRelease --no-daemon

AAR="$(find "$WORK/awg/tunnel/build/outputs/aar" -name "*.aar" | head -1)"
if [ -z "$AAR" ]; then
    echo "Библиотека не собралась." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
cp "$AAR" "$OUT"
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"
