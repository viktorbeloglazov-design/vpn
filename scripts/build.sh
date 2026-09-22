#!/bin/bash
# Сборка QP VPN: приложение QPVPN.app и служебный демон kupibasvpnd.
#
#   ./scripts/build.sh                       обычная сборка под текущий процессор
#   ./scripts/build.sh --universal           universal-бинарник (Apple Silicon + Intel)
#   ./scripts/build.sh --tools КАТАЛОГ       вложить утилиты WireGuard в приложение
#   ./scripts/build.sh --version 2.5.0       проставить номер версии выпуска
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
ARCH_FLAGS=()
TOOLS_DIR=""
VERSION="0.0.0"

while [ $# -gt 0 ]; do
    case "$1" in
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64); shift ;;
        --tools) TOOLS_DIR="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

cd "$ROOT"

# ${ARCH_FLAGS[@]+...} — чтобы пустой массив не ронял скрипт в bash 3.2 из macOS.
echo "==> Собираю Swift-пакет (release)"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Собираю бандл приложения"
mkdir -p "$DIST"
if [ -n "$TOOLS_DIR" ]; then
    "$ROOT/scripts/bundle-app.sh" --bin-dir "$BIN_DIR" --tools "$TOOLS_DIR" \
        --out "$DIST" --version "$VERSION"
else
    "$ROOT/scripts/bundle-app.sh" --bin-dir "$BIN_DIR" --out "$DIST" --version "$VERSION"
fi

echo "==> Собираю программу удаления"
"$ROOT/scripts/bundle-uninstaller.sh" --bin-dir "$BIN_DIR" --out "$DIST" --version "$VERSION"

echo "==> Кладу рядом демон (для установки из исходников)"
install -m 0755 "$BIN_DIR/kupibasvpnd" "$DIST/kupibasvpnd"
codesign --force --sign - --timestamp=none "$DIST/kupibasvpnd"

echo
echo "Готово:"
echo "  приложение: $DIST/QPVPN.app"
echo "  удаление:   $DIST/Удалить QP VPN.app"
echo "  демон:      $DIST/kupibasvpnd"
echo
if [ -n "$TOOLS_DIR" ]; then
    echo "Утилиты WireGuard вложены внутрь приложения — Homebrew не нужен."
    echo "Службу можно поставить кнопкой в самом приложении."
else
    echo "Дальше: sudo $ROOT/scripts/install.sh"
fi
