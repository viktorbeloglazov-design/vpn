#!/bin/bash
# Собирает «Удалить QP VPN.app» из готового бинарника.
#
#   scripts/bundle-uninstaller.sh --bin-dir .build/release [--out dist] [--version 2.7.0]
#
# Отдельная программа, а не кнопка внутри основной: она нужна ровно тогда,
# когда основная не открывается или открывается не та копия.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR=""
OUT_DIR="$ROOT/dist"
VERSION="0.0.0"

while [ $# -gt 0 ]; do
    case "$1" in
        --bin-dir) BIN_DIR="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$BIN_DIR" ]; then
    echo "Укажите --bin-dir" >&2
    exit 1
fi

APP="$OUT_DIR/Удалить QP VPN.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 0755 "$BIN_DIR/KupibasUninstaller" "$APP/Contents/MacOS/QPVPNUninstaller"
install -m 0755 "$ROOT/scripts/uninstall-mac.sh" "$APP/Contents/Resources/uninstall-mac.sh"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Свой опознавательный знак, отличный от основной программы: иначе система
# будет считать их одной и той же и путать при запуске.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Удалить QP VPN</string>
    <key>CFBundleDisplayName</key>
    <string>Удалить QP VPN</string>
    <key>CFBundleExecutable</key>
    <string>QPVPNUninstaller</string>
    <key>CFBundleIdentifier</key>
    <string>com.kupibas.vpn.uninstaller</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Иконка та же, что у основной программы: собирается из набора картинок.
ICONSET="$ROOT/Resources/AppIcon.iconset"
if [ -d "$ICONSET" ] && command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

codesign --force --deep --sign - --timestamp=none "$APP"
echo "Готово: $APP"
