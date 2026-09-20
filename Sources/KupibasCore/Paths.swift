import Foundation

/// Пути, общие для GUI-приложения и root-демона.
public enum Paths {
    /// Каталог с конфигурацией. root:staff, права 0770 — писать может админ-пользователь.
    public static let stateDir = "/Library/Application Support/KupibasVPN"
    public static let configFile = stateDir + "/config.json"
    public static let statusFile = stateDir + "/status.json"

    /// Рантайм-каталог демона (только root).
    public static let runtimeDir = "/var/run/kupibas-vpn"
    public static let wgConfigFile = runtimeDir + "/kb0.conf"

    /// Наше имя туннеля. Система выдаёт настоящее (utunN) при создании,
    /// а это остаётся внутренним: по нему служба находит файл с именем.
    public static let interfaceName = "kb0"

    public static let logFile = "/var/log/kupibas-vpn.log"
    public static let daemonLabel = "com.kupibas.vpn.helper"
    public static let daemonPlist = "/Library/LaunchDaemons/com.kupibas.vpn.helper.plist"
    public static let helperDir = "/usr/local/libexec/kupibas-vpn"
    public static let helperBinary = helperDir + "/kupibasvpnd"

    /// Версия приложения, из которого поставили службу.
    ///
    /// Приложение обновляют перетаскиванием, а служба остаётся прежней —
    /// и продолжает работать по-старому. По этому файлу видно расхождение.
    public static let helperVersionFile = helperDir + "/version"
}
