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
# xray — тот же выпуск, что вложен в приложение для Mac: свежий тег vNN.
# Модулем Go он под таким номером не публикуется, поэтому берём его по
# коммиту. tun2socks закреплён: в 2.7 и в следующих версиях разный
# порядок запуска, а обёртка написана под 2.7.
XRAY_TAG="$(git ls-remote --refs --tags https://github.com/XTLS/Xray-core.git 'v2*' \
    | awk -F/ '{print $3}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
XRAY_SHA="$(git ls-remote https://github.com/XTLS/Xray-core.git "refs/tags/$XRAY_TAG^{}" | cut -f1)"
[ -n "$XRAY_SHA" ] || XRAY_SHA="$(git ls-remote https://github.com/XTLS/Xray-core.git "refs/tags/$XRAY_TAG" | cut -f1)"
echo "xray $XRAY_TAG ($XRAY_SHA)"
go get "github.com/xtls/xray-core@$XRAY_SHA"
go get github.com/xjasonlyu/tun2socks/v2@v2.7.0
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
