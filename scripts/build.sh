#!/bin/bash
# Сборка KZTunnel: приложение KZTunnel.app и служебный демон kztunneld.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/KZTunnel.app"

cd "$ROOT"

echo "==> Собираю Swift-пакет (release)"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Собираю бандл приложения"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KZTunnelApp" "$APP/Contents/MacOS/KZTunnel"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Кладу рядом демон"
cp "$BIN_DIR/kztunneld" "$DIST/kztunneld"

echo "==> Подписываю ad-hoc подписью"
codesign --force --sign - --timestamp=none "$DIST/kztunneld"
codesign --force --deep --sign - --timestamp=none "$APP"

echo
echo "Готово:"
echo "  приложение: $APP"
echo "  демон:      $DIST/kztunneld"
echo
echo "Дальше: sudo $ROOT/scripts/install.sh"
