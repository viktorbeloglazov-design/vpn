import Foundation

/// Пути, общие для GUI-приложения и root-демона.
public enum Paths {
    /// Каталог с конфигурацией. root:staff, права 0770 — писать может админ-пользователь.
    public static let stateDir = "/Library/Application Support/KZTunnel"
    public static let configFile = stateDir + "/config.json"
    public static let statusFile = stateDir + "/status.json"

    /// Рантайм-каталог демона (только root).
    public static let runtimeDir = "/var/run/kztunnel"
    public static let wgConfigFile = runtimeDir + "/kz0.conf"

    /// Имя WireGuard-интерфейса (wg-quick создаёт utunN и связывает его с этим именем).
    public static let interfaceName = "kz0"

    public static let logFile = "/var/log/kztunnel.log"
    public static let daemonLabel = "com.kztunnel.helper"
    public static let daemonPlist = "/Library/LaunchDaemons/com.kztunnel.helper.plist"
    public static let helperDir = "/usr/local/libexec/kztunnel"
    public static let helperBinary = helperDir + "/kztunneld"
}
