#!/bin/bash
# Пакует собранное приложение в образ для скачивания.
#
#   scripts/make-dmg.sh 1.0.0 [--app dist/QPVPN.app] [--out dist]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?укажите версию, например 1.0.0}"
shift || true

APP="$ROOT/dist/QPVPN.app"
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

cp -R "$APP" "$STAGE/QPVPN.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/ЧИТАТЬ ПЕРВЫМ.txt" <<'TXT'
QP VPN — установка

1. Перетащите QPVPN.app в папку Applications (ярлык рядом).

2. ПЕРВЫЙ ЗАПУСК. macOS покажет окно «Файл "QPVPN" не был открыт»
   — это обычная защита от программ без сертификата Apple. Обойти её
   нужно один раз, любым из двух способов:

   Способ А, без терминала:
     • нажмите «Готово» в этом окне;
     • Системные настройки → Конфиденциальность и безопасность;
     • пролистайте вниз до раздела «Безопасность» — там строка
       «Использование "QPVPN" было заблокировано…»;
     • нажмите «Открыть всё равно», подтвердите паролем или Touch ID;
     • в следующем окне ещё раз «Открыть».

   Способ Б, одной командой в Терминале:
     xattr -dr com.apple.quarantine /Applications/QPVPN.app

3. В окне приложения появится жёлтая полоса «Служба не установлена» —
   нажмите «Установить службу» и введите пароль администратора.
   Терминал для этого не нужен.

4. Вкладка «Сервер» → «Вставить конфиг WireGuard…» → вставьте конфиг
   вашего сервера в Казахстане → «Импортировать».

5. Нажмите круглую кнопку включения и проверьте «Проверить мой IP».

Если жёлтая полоса не исчезла, журнал службы: /var/log/kupibas-vpn.log

Все утилиты WireGuard уже внутри приложения — ставить ничего больше не нужно.
TXT

DMG="$OUT_DIR/QPVPN-$VERSION.dmg"
mkdir -p "$OUT_DIR"
rm -f "$DMG"

hdiutil create \
    -volname "QP VPN" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo "Готово: $DMG"
