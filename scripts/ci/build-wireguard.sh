#!/bin/bash
# Собирает утилиты туннеля universal-бинарниками, чтобы приложение работало
# и на Apple Silicon, и на Intel без Homebrew.
#
#   scripts/ci/build-wireguard.sh КАТАЛОГ_РЕЗУЛЬТАТА
#
# Берётся не обычный WireGuard, а форк Amnezia: он понимает и обычные ключи,
# и ключи с маскировкой (Jc, S1, H1 и прочие). Обычный wg такие настройки
# считает ошибкой и туннель не поднимает.
#
# Файлы кладутся под двумя именами — своими и привычными (wg, wireguard-go):
# служба ищет их по вторым, а каталог службы стоит в PATH первым, поэтому
# подхватываются именно наши.
set -euo pipefail

OUT="${1:?укажите каталог для результата}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> amneziawg-go"
git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-go.git "$WORK/amneziawg-go"
cd "$WORK/amneziawg-go"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -o "$WORK/awg-go-arm64" .
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -o "$WORK/awg-go-amd64" .
lipo -create -output "$OUT/amneziawg-go" "$WORK/awg-go-arm64" "$WORK/awg-go-amd64"
install -m 0644 LICENSE "$OUT/LICENSE-amneziawg-go.txt"

echo "==> amneziawg-tools"
git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git "$WORK/amneziawg-tools"
cd "$WORK/amneziawg-tools/src"
make clean >/dev/null 2>&1 || true
make -j4 CC="clang -arch arm64" wg
cp wg "$WORK/awg-arm64"
make clean >/dev/null 2>&1 || true
make -j4 CC="clang -arch x86_64" wg
cp wg "$WORK/awg-amd64"
lipo -create -output "$OUT/awg" "$WORK/awg-arm64" "$WORK/awg-amd64"

# awg-quick намеренно не кладём: это скрипт на bash, которому нужен bash 4+,
# а macOS поставляет 3.2 и другого не будет. Туннель поднимает сама служба —
# несколько вызовов ifconfig и route вместо пятисот строк скрипта.
install -m 0644 "$WORK/amneziawg-tools/COPYING" "$OUT/LICENSE-amneziawg-tools.txt"

echo "==> привычные имена"
cp "$OUT/amneziawg-go" "$OUT/wireguard-go"
cp "$OUT/awg" "$OUT/wg"
chmod 0755 "$OUT/wireguard-go" "$OUT/wg"

# ── X-Ray ─────────────────────────────────────────────────────────────
# Сервер перешёл на X-Ray. На Mac он работает связкой из двух программ:
# xray держит соединение с сервером и слушает socks-вход на самом
# компьютере, tun2socks заводит туннельный интерфейс и передаёт в этот
# вход всё, что система решила вести через VPN. Обе на Go — собираются
# так же, как amneziawg-go, сразу под оба процессора.

latest_tag() {
    git ls-remote --refs --tags "$1" 'v*' | awk -F/ '{print $3}' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

echo "==> xray"
XRAY_TAG="$(latest_tag https://github.com/XTLS/Xray-core.git)"
echo "Xray-core $XRAY_TAG"
git clone --depth 1 --branch "$XRAY_TAG" https://github.com/XTLS/Xray-core.git "$WORK/xray"
cd "$WORK/xray"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "-s -w -buildid=" -o "$WORK/xray-arm64" ./main
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags "-s -w -buildid=" -o "$WORK/xray-amd64" ./main
lipo -create -output "$OUT/xray" "$WORK/xray-arm64" "$WORK/xray-amd64"
install -m 0644 LICENSE "$OUT/LICENSE-xray.txt"

echo "==> tun2socks"
# Закреплён: служба запускает tun2socks с параметрами версии 2.7.
T2S_TAG="v2.7.0"
echo "tun2socks $T2S_TAG"
git clone --depth 1 --branch "$T2S_TAG" https://github.com/xjasonlyu/tun2socks.git "$WORK/tun2socks"
cd "$WORK/tun2socks"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "-s -w -buildid=" -o "$WORK/t2s-arm64" .
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags "-s -w -buildid=" -o "$WORK/t2s-amd64" .
lipo -create -output "$OUT/tun2socks" "$WORK/t2s-arm64" "$WORK/t2s-amd64"
install -m 0644 LICENSE "$OUT/LICENSE-tun2socks.txt"

echo
echo "Готово:"
for tool in amneziawg-go awg wireguard-go wg xray tun2socks; do
    printf "  %-14s %s\n" "$tool" "$(lipo -archs "$OUT/$tool" 2>/dev/null || echo 'скрипт')"
done

# Проверяем, что собрана именно версия с маскировкой.
if "$OUT/awg" --help 2>&1 | head -40 | grep -qi "awg\|amnezia"; then
    echo "Утилита управления: форк Amnezia"
fi
