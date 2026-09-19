#!/bin/bash
# Собирает KupibasVPN.app из уже скомпилированных бинарников.
#
#   scripts/bundle-app.sh --bin-dir .build/release [--tools КАТАЛОГ] [--out dist]
#
# --tools: каталог с wireguard-go, wg и wg-quick. Если указан, утилиты кладутся
# внутрь приложения и Homebrew пользователю не нужен.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR=""
TOOLS_DIR=""
OUT_DIR="$ROOT/dist"

while [ $# -gt 0 ]; do
    case "$1" in
        --bin-dir) BIN_DIR="$2"; shift 2 ;;
        --tools) TOOLS_DIR="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$BIN_DIR" ]; then
    echo "Укажите --bin-dir" >&2
    exit 1
fi

APP="$OUT_DIR/QPVPN.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/Helpers"

install -m 0755 "$BIN_DIR/KupibasVPNApp" "$APP/Contents/MacOS/QPVPN"
install -m 0644 "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Служба и всё, что нужно для её установки, едут внутри приложения.
install -m 0755 "$BIN_DIR/kupibasvpnd" "$APP/Contents/Library/Helpers/kupibasvpnd"
install -m 0755 "$ROOT/scripts/install-helper.sh" "$APP/Contents/Resources/install-helper.sh"
install -m 0644 "$ROOT/launchd/com.kupibas.vpn.helper.plist" "$APP/Contents/Resources/com.kupibas.vpn.helper.plist"

# Иконка: на macOS собираем .icns из готового iconset.
ICONSET="$ROOT/Resources/AppIcon.iconset"
if [ -d "$ICONSET" ]; then
    if command -v iconutil >/dev/null 2>&1; then
        iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
    else
        echo "iconutil недоступен — приложение соберётся без иконки" >&2
    fi
fi

if [ -n "$TOOLS_DIR" ]; then
    for tool in wireguard-go wg wg-quick; do
        if [ ! -f "$TOOLS_DIR/$tool" ]; then
            echo "В каталоге утилит нет $tool" >&2
            exit 1
        fi
        install -m 0755 "$TOOLS_DIR/$tool" "$APP/Contents/Library/Helpers/$tool"
    done
    for license in "$TOOLS_DIR"/LICENSE-*; do
        [ -f "$license" ] && install -m 0644 "$license" "$APP/Contents/Resources/"
    done
fi

echo "==> Подписываю ad-hoc подписью"
# Подписывать нужно изнутри наружу: сначала вложенные программы, затем бандл.
# Ключ --deep для этого не предназначен и на вложенных утилитах даёт сбои.
for binary in "$APP/Contents/Library/Helpers"/*; do
    [ -f "$binary" ] || continue
    if file "$binary" | grep -q "Mach-O"; then
        codesign --force --sign - --timestamp=none "$binary"
    fi
done
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/QPVPN"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "Готово: $APP"
