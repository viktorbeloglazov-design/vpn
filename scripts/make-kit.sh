#!/usr/bin/env bash
# Собирает один архив для раздачи людям: папки Windows, Mac, Android, iPhone,
# в каждой — приложение (где оно есть) и инструкция по установке.
#
#   scripts/make-kit.sh --android 1.5.0 --mac 1.4.0
#
# Приложения берутся из релизов на GitHub, инструкции — из папки kit/.
set -euo pipefail

REPO="viktorbeloglazov-design/vpn"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_VERSION=""
MAC_VERSION=""
KIT_VERSION="1.0"
OUT="$ROOT/dist"
KEEP_ADMIN="no"

while [ $# -gt 0 ]; do
    case "$1" in
        --android) ANDROID_VERSION="$2"; shift 2 ;;
        --mac) MAC_VERSION="$2"; shift 2 ;;
        --kit) KIT_VERSION="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --without-admin) KEEP_ADMIN="no"; shift ;;
        --with-admin) KEEP_ADMIN="yes"; shift ;;
        *) echo "Неизвестный параметр: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$ANDROID_VERSION" ] || [ -z "$MAC_VERSION" ]; then
    echo "Укажите версии: --android 1.5.0 --mac 1.4.0" >&2
    exit 1
fi

NAME="QP-VPN-$KIT_VERSION"
STAGE="$OUT/$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE"/{Windows,Mac,Android,iPhone}

echo "→ Инструкции"
cp "$ROOT/kit/ЧИТАЙ-МЕНЯ.txt" "$STAGE/"
cp "$ROOT/kit/README.md" "$STAGE/"
[ "$KEEP_ADMIN" = "yes" ] && cp "$ROOT/kit/ДЛЯ-АДМИНИСТРАТОРА.md" "$STAGE/"
for folder in Windows Mac Android iPhone; do
    cp -R "$ROOT/kit/$folder/." "$STAGE/$folder/"
done

download() {
    local url="$1" target="$2"
    echo "→ $(basename "$target")"
    curl -fsSL --retry 4 --retry-delay 2 -o "$target" "$url"
}

download "https://github.com/$REPO/releases/download/android-v$ANDROID_VERSION/QPVPN-$ANDROID_VERSION.apk" \
    "$STAGE/Android/QPVPN-$ANDROID_VERSION.apk"
download "https://github.com/$REPO/releases/download/v$MAC_VERSION/QPVPN-$MAC_VERSION.dmg" \
    "$STAGE/Mac/QPVPN-$MAC_VERSION.dmg"

echo "→ QR-коды на загрузку"
python3 -c "import segno" 2>/dev/null || pip install --quiet segno 2>/dev/null || true
python3 "$ROOT/scripts/make-download-qr.py" "$STAGE"

# Версии видно прямо в архиве: человек по телефону скажет, что у него стоит.
cat > "$STAGE/ВЕРСИИ.txt" <<TXT
QP VPN
  Android  $ANDROID_VERSION   (файл QPVPN-$ANDROID_VERSION.apk)
  Mac      $MAC_VERSION   (файл QPVPN-$MAC_VERSION.dmg)
  Windows  клиент AmneziaVPN, ставится с amnezia.org
  iPhone   клиент DefaultVPN, ставится из App Store

Собрано: $(date -u '+%Y-%m-%d %H:%M UTC')
TXT

echo "→ Архив"
ARCHIVE="$OUT/$NAME.zip"
rm -f "$ARCHIVE"
(cd "$OUT" && zip -qr "$NAME.zip" "$NAME")

echo
echo "Готово: $ARCHIVE"
du -h "$ARCHIVE" | cut -f1 | sed 's/^/Размер: /'
