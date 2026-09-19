import Foundation

public enum Formatting {

    public static func bytes(_ value: Int) -> String {
        let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        var size = Double(value)
        var index = 0
        while size >= 1024 && index < units.count - 1 {
            size /= 1024
            index += 1
        }
        return index == 0 ? "\(value) Б" : String(format: "%.1f %@", size, units[index])
    }

    /// «3 мин назад», «только что», «—».
    public static func relative(_ timestamp: Double) -> String {
        guard timestamp > 0 else { return "—" }
        let seconds = Int(Date().timeIntervalSince1970 - timestamp)
        if seconds < 5 { return "только что" }
        if seconds < 60 { return "\(seconds) с назад" }
        if seconds < 3600 { return "\(seconds / 60) мин назад" }
        if seconds < 86400 { return "\(seconds / 3600) ч назад" }
        return "\(seconds / 86400) дн назад"
    }

    /// Длительность соединения: «1 ч 05 мин».
    public static func duration(since timestamp: Double) -> String {
        guard timestamp > 0 else { return "—" }
        let seconds = max(0, Int(Date().timeIntervalSince1970 - timestamp))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%d ч %02d мин", hours, minutes) }
        if minutes > 0 { return String(format: "%d мин %02d с", minutes, secs) }
        return "\(secs) с"
    }
}
