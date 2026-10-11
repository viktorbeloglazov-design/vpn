#!/bin/bash
# Собирает библиотеку X-Ray для Android: xray и tun2socks в одном .aar.
#
#   scripts/build-xray-android.sh android/app/libs/xraylib.aar
#
# Исходники обёртки лежат в android/xraylib, движки берутся свежими
# выпусками. Нужны Go, Android SDK и NDK — на раннере GitHub они есть.
set -euo pipefail

OUT="${1:?укажите, куда положить .aar}"
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$ROOT/android/xraylib/." "$WORK/"
cd "$WORK"

export ANDROID_NDK_HOME="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}"
if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "Не найден Android NDK (ANDROID_NDK_LATEST_HOME / ANDROID_NDK_HOME)." >&2
    exit 1
fi
echo "NDK: $ANDROID_NDK_HOME"

echo "==> Движки"
go get github.com/xtls/xray-core@latest
go get github.com/xjasonlyu/tun2socks/v2@latest
go get golang.org/x/mobile/bind@latest
go mod tidy
grep -E "xray-core|tun2socks|x/mobile" go.mod

echo "==> gomobile"
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
export PATH="$(go env GOPATH)/bin:$PATH"
gomobile init

echo "==> Сборка"
gomobile bind -v -target=android/arm64,android/arm -androidapi 26 \
    -trimpath -ldflags="-s -w -buildid=" -o "$OUT" .

echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"
unzip -l "$OUT" | grep -E "\.so|classes" || true
