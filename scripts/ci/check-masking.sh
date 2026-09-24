#!/usr/bin/env bash
# Сверяет параметры маскировки AmneziaWG в приложении Windows с тем,
# что на самом деле понимает служба туннеля.
#
# Зачем. Приложение читает из ключа только те параметры, которые
# перечислены у него в списке, а остальные молча выбрасывает. Маскировка
# же работает целиком: потеряется защита заголовков — сервер перестанет
# узнавать наши пакеты, и туннель будет вечно «подключаться». Так и
# случилось: в приложении лежало шестнадцать параметров, служба понимала
# двадцать девять, а в рабочем ключе их было двадцать.
#
# Поэтому список сверяется на каждой проверке: если Amnezia добавит новый
# параметр, об этом скажет сборка, а не человек, у которого перестал
# работать VPN.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
profile="$root/windows/app/Core/WgProfile.cs"

module="$(awk '/amneziawg-windows/ { print $1 "@" $2 }' "$root/windows/tunnel/go.mod" | head -1)"
if [ -z "$module" ]; then
    echo "Не нашёл amneziawg-windows в windows/tunnel/go.mod" >&2
    exit 1
fi

echo "==> Служба туннеля: $module"
go mod download "$module"
parser="$(go env GOMODCACHE)/${module%@*}@${module#*@}/conf/parser.go"
if [ ! -f "$parser" ]; then
    echo "Не нашёл разбор настроек службы: $parser" >&2
    exit 1
fi

# Имена, которые служба принимает в секции [Interface]. Обычные поля
# WireGuard к маскировке отношения не имеют — их отбрасываем.
plain="privatekey|listenport|fwmark|mtu|address|dns|preup|postup|predown|postdown|table|publickey|presharedkey|allowedips|persistentkeepalive|endpoint|errno|replace_peers|update_only|remove|protocol_version"

service="$(grep -oE 'case "[a-z0-9_]+"(, "[a-z0-9_]+")*' "$parser" \
    | grep -oE '"[a-z0-9_]+"' | tr -d '"' | sort -u \
    | grep -vxE "$plain" \
    | grep -vE '_' || true)"

app="$(grep -oE '\("[a-z0-9]+", "[A-Za-z0-9]+"\)' "$profile" \
    | grep -oE '^\("[a-z0-9]+' | tr -d '("' | sort -u)"

missing="$(comm -23 <(echo "$service") <(echo "$app") || true)"

if [ -n "$missing" ]; then
    echo >&2
    echo "Приложение не передаёт службе эти параметры маскировки:" >&2
    echo "$missing" | sed 's/^/  /' >&2
    echo >&2
    echo "Добавьте их в AmneziaFields в windows/app/Core/WgProfile.cs." >&2
    echo "Пока они не переданы, сервер не узнаёт пакеты и туннель" >&2
    echo "висит в состоянии «подключение»." >&2
    exit 1
fi

extra="$(comm -13 <(echo "$service") <(echo "$app") || true)"
if [ -n "$extra" ]; then
    echo >&2
    echo "Приложение передаёт параметры, которых служба не знает:" >&2
    echo "$extra" | sed 's/^/  /' >&2
    echo "Служба отвергает такие настройки целиком." >&2
    exit 1
fi

echo "Параметры маскировки сходятся: $(echo "$service" | wc -l | tr -d ' ') штук."
