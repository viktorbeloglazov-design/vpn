# Сборка и установка

## Требования

- macOS 13 Ventura или новее;
- Xcode Command Line Tools: `xcode-select --install`;
- Homebrew и WireGuard: `brew install wireguard-tools wireguard-go`.

## Сборка

```bash
./scripts/build.sh
```

Скрипт собирает Swift-пакет в release-режиме, складывает
`dist/KZTunnel.app` и `dist/kztunneld` и подписывает их ad-hoc подписью
(платный аккаунт разработчика Apple не нужен).

Открыть проект в Xcode можно напрямую: `open Package.swift`.

## Установка службы

```bash
sudo ./scripts/install.sh
```

Что делает скрипт:

1. проверяет наличие `wg`, `wg-quick`, `wireguard-go`;
2. копирует демон в `/usr/local/libexec/kztunnel/kztunneld`;
3. создаёт `/Library/Application Support/KZTunnel` (`root:staff`, права `0770`)
   и стартовый `config.json`;
4. ставит и запускает launchd-службу `com.kztunnel.helper`.

Служба стартует вместе с системой и работает независимо от того, открыто
приложение или нет. Права `root:staff` на каталог нужны, чтобы приложение,
запущенное от вашего пользователя-администратора, могло сохранять настройки.

## Первый запуск приложения

```bash
open dist/KZTunnel.app
```

macOS может предупредить о неизвестном разработчике (ad-hoc подпись):
**Системные настройки → Конфиденциальность и безопасность → Открыть всё равно**.

Чтобы приложение всегда было под рукой, перетащите `KZTunnel.app` в `/Applications`
и включите «Запускать при входе в систему» на вкладке «Настройки».

## Обновление

```bash
git pull
./scripts/build.sh
sudo ./scripts/install.sh   # перезапустит службу с новой версией
```

## Удаление

```bash
sudo ./scripts/uninstall.sh            # снять службу
sudo ./scripts/uninstall.sh --purge    # снять службу и удалить настройки
```

## Полезные команды

```bash
sudo launchctl print system/com.kztunnel.helper     # состояние службы
sudo launchctl kickstart -k system/com.kztunnel.helper  # перезапуск
tail -f /var/log/kztunnel.log                       # журнал
cat "/Library/Application Support/KZTunnel/status.json"  # текущий статус
```
