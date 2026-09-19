#!/bin/bash
# Пакует собранное приложение в образ для скачивания.
#
#   scripts/make-dmg.sh 1.0.0 [--app dist/KupibasVPN.app] [--out dist]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?укажите версию, например 1.0.0}"
shift || true

APP="$ROOT/dist/KupibasVPN.app"
OUT_DIR="$ROOT/dist"

while [ $# -gt 0 ]; do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

if [ ! -d "$APP" ]; then
    echo "Не найдено приложение: $APP" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/KupibasVPN.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/ЧИТАТЬ ПЕРВЫМ.txt" <<'TXT'
Kupibas VPN — установка

1. Перетащите KupibasVPN.app в папку Applications (ярлык рядом).
2. Откройте приложение из папки «Программы».
   Первый запуск: нажмите правой кнопкой по значку → «Открыть» → «Открыть».
   Так делается один раз, потому что приложение подписано своим сертификатом.
3. В окне появится жёлтая полоса «Служба не установлена» — нажмите
   «Установить службу» и введите пароль администратора. Терминал не нужен.
4. Вкладка «Сервер» → «Вставить конфиг WireGuard…» → вставьте конфиг
   вашего сервера в Казахстане → «Импортировать».
5. Нажмите круглую кнопку включения и проверьте «Проверить мой IP».

Если жёлтая полоса не исчезла, журнал службы: /var/log/kupibas-vpn.log

Все утилиты WireGuard уже внутри приложения — ставить ничего больше не нужно.
TXT

DMG="$OUT_DIR/KupibasVPN-$VERSION.dmg"
mkdir -p "$OUT_DIR"
rm -f "$DMG"

hdiutil create \
    -volname "Kupibas VPN" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo "Готово: $DMG"
