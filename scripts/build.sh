#!/bin/bash
# Сборка Kupibas VPN: приложение «Kupibas VPN.app» и служебный демон kupibasvpnd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/KupibasVPN.app"

cd "$ROOT"

echo "==> Собираю Swift-пакет (release)"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Собираю бандл приложения"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KupibasVPNApp" "$APP/Contents/MacOS/KupibasVPN"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Кладу рядом демон"
cp "$BIN_DIR/kupibasvpnd" "$DIST/kupibasvpnd"

echo "==> Подписываю ad-hoc подписью"
codesign --force --sign - --timestamp=none "$DIST/kupibasvpnd"
codesign --force --deep --sign - --timestamp=none "$APP"

echo
echo "Готово:"
echo "  приложение: $APP"
echo "  демон:      $DIST/kupibasvpnd"
echo
echo "Дальше: sudo $ROOT/scripts/install.sh"
