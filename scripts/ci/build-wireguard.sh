#!/bin/bash
# Собирает утилиты WireGuard (wireguard-go, wg, wg-quick) universal-бинарниками,
# чтобы приложение работало и на Apple Silicon, и на Intel без Homebrew.
#
#   scripts/ci/build-wireguard.sh КАТАЛОГ_РЕЗУЛЬТАТА
set -euo pipefail

OUT="${1:?укажите каталог для результата}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> wireguard-go"
git clone --depth 1 https://github.com/WireGuard/wireguard-go.git "$WORK/wireguard-go"
cd "$WORK/wireguard-go"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -o "$WORK/wireguard-go-arm64" .
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -o "$WORK/wireguard-go-amd64" .
lipo -create -output "$OUT/wireguard-go" "$WORK/wireguard-go-arm64" "$WORK/wireguard-go-amd64"
install -m 0644 LICENSE "$OUT/LICENSE-wireguard-go.txt"

echo "==> wireguard-tools"
git clone --depth 1 https://github.com/WireGuard/wireguard-tools.git "$WORK/wireguard-tools"
cd "$WORK/wireguard-tools/src"
make clean >/dev/null 2>&1 || true
make -j4 CC="clang -arch arm64" wg
cp wg "$WORK/wg-arm64"
make clean >/dev/null 2>&1 || true
make -j4 CC="clang -arch x86_64" wg
cp wg "$WORK/wg-amd64"
lipo -create -output "$OUT/wg" "$WORK/wg-arm64" "$WORK/wg-amd64"

install -m 0755 "$WORK/wireguard-tools/src/wg-quick/darwin.bash" "$OUT/wg-quick"
install -m 0644 "$WORK/wireguard-tools/COPYING" "$OUT/LICENSE-wireguard-tools.txt"

echo
echo "Готово:"
for tool in wireguard-go wg wg-quick; do
    printf "  %-14s %s\n" "$tool" "$(lipo -archs "$OUT/$tool" 2>/dev/null || echo 'скрипт')"
done
