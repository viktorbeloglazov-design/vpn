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
`dist/KupibasVPN.app` и `dist/kupibasvpnd` и подписывает их ad-hoc подписью
(платный аккаунт разработчика Apple не нужен).

Открыть проект в Xcode можно напрямую: `open Package.swift`.

### Самодостаточный образ, как в релизах

```bash
./scripts/ci/build-wireguard.sh /tmp/wg-tools        # wireguard-go, wg (universal)
./scripts/build.sh --universal --tools /tmp/wg-tools # утилиты уедут внутрь бандла
./scripts/make-dmg.sh 1.0.0                          # dist/KupibasVPN-1.0.0.dmg
```

У такой сборки служба ставится кнопкой в самом приложении, Homebrew не нужен.
Внутри `KupibasVPN.app` лежат:

| Путь в бандле | Что это |
|---|---|
| `Contents/MacOS/KupibasVPN` | интерфейс |
| `Contents/Library/Helpers/kupibasvpnd` | служба, которую установщик кладёт в `/usr/local/libexec/kupibas-vpn` |
| `Contents/Library/Helpers/{wireguard-go,wg}` | утилиты WireGuard |
| `Contents/Resources/install-helper.sh` | установщик, который запускает само приложение |

## Установка службы

```bash
sudo ./scripts/install.sh
```

Что делает скрипт:

1. проверяет наличие `wg` и `wireguard-go`;
2. копирует демон в `/usr/local/libexec/kupibas-vpn/kupibasvpnd`;
3. создаёт `/Library/Application Support/KupibasVPN` (`root:staff`, права `0770`)
   и стартовый `config.json`;
4. ставит и запускает launchd-службу `com.kupibas.vpn.helper`.

Служба стартует вместе с системой и работает независимо от того, открыто
приложение или нет. Права `root:staff` на каталог нужны, чтобы приложение,
запущенное от вашего пользователя-администратора, могло сохранять настройки.

## Первый запуск приложения

```bash
open dist/KupibasVPN.app
```

macOS может предупредить о неизвестном разработчике (ad-hoc подпись):
**Системные настройки → Конфиденциальность и безопасность → Открыть всё равно**.

Чтобы приложение всегда было под рукой, перетащите `KupibasVPN.app` в `/Applications`
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
sudo launchctl print system/com.kupibas.vpn.helper     # состояние службы
sudo launchctl kickstart -k system/com.kupibas.vpn.helper  # перезапуск
tail -f /var/log/kupibas-vpn.log                       # журнал
cat "/Library/Application Support/KupibasVPN/status.json"  # текущий статус
```
