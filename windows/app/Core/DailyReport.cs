using System;
using System.IO;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Ежедневный отчёт о работе программы — файлом в папке «Документы».
///
/// Нужен затем, чтобы разбираться по записям, а не по памяти. Когда
/// человек говорит «вчера днём отвалилось», в отчёте видно, что было:
/// подключались или нет, сколько прошло данных, какой размер пакета
/// подобрался, что ответил сервер.
///
/// Файл на каждый день, перезаписывается по ходу дня, так что к вечеру
/// в нём последнее состояние. Старше месяца — удаляются сами.
///
/// Ключей и паролей в отчёте нет: только адрес сервера, счётчики и
/// состояние. Такой файл можно пересылать не задумываясь.
/// </summary>
public static class DailyReport
{
    /// <summary>Сколько дней держим отчёты.</summary>
    public const int KeepDays = 30;

    public static string Directory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
        "QP VPN", "отчёты");

    public static string PathFor(DateTimeOffset day) =>
        Path.Combine(Directory, $"{day:yyyy-MM-dd}.txt");

    /// <summary>Складывает отчёт за сегодня. Возвращает путь или пустую строку.</summary>
    public static string Save(string text, DateTimeOffset now)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var path = PathFor(now);
            File.WriteAllText(path, text);
            Forget(now);
            return path;
        }
        catch (Exception)
        {
            // Папка недоступна — отчёт не главное, работе это не мешает.
            return "";
        }
    }

    /// <summary>Убирает отчёты старше месяца, чтобы папка не росла без конца.</summary>
    public static void Forget(DateTimeOffset now)
    {
        try
        {
            var edge = now.AddDays(-KeepDays);
            foreach (var file in System.IO.Directory.GetFiles(Directory, "*.txt"))
            {
                var name = Path.GetFileNameWithoutExtension(file);
                if (DateTimeOffset.TryParse(name, out var day) && day < edge)
                {
                    File.Delete(file);
                }
            }
        }
        catch (Exception)
        {
            // Не вышло убрать — не беда.
        }
    }

    /// <summary>Отчёт, каким он ложится в файл.</summary>
    public static string Compose(
        string version,
        TunnelStatus status,
        AppConfig config,
        string profileSummary,
        int activeMtu,
        bool usedBackupEntry,
        DateTimeOffset now)
    {
        var lines = new[]
        {
            $"QP VPN для Windows {version}",
            $"Отчёт за {now:yyyy-MM-dd}, записан в {now.ToLocalTime():HH:mm}",
            "",
            $"Состояние: {StateName(status.State)}",
            $"Сообщение: {(status.Message.Length > 0 ? status.Message : "—")}",
            $"Сервер: {(status.ServerName.Length > 0 ? status.ServerName : "—")}",
            $"Вход: {(usedBackupEntry ? "запасной узел" : "сервер напрямую")}",
            $"Размер пакета: {(activeMtu > 0 ? activeMtu.ToString() : "—")}"
                + (config.Mtu > 0 ? " (выбран вручную)" : " (подобран сам)"),
            $"Адресов в туннеле: {status.RouteCount}",
            $"Принято/отправлено: {Bytes(status.RxBytes)} / {Bytes(status.TxBytes)}",
            "",
            $"Через VPN идут: рабочая зона для 1С"
                + (config.ServicesThroughVpn ? " и " + string.Join(", ", VpnServices.Titles) : ""),
            "Всё остальное идёт напрямую, мимо VPN.",
            "",
            $"Ключ: {profileSummary}",
            $"Запасной вход: {(config.BackupEndpoint.Length > 0 ? config.BackupEndpoint : "не задан")}",
            "",
            "Ключей и паролей в отчёте нет — файл можно переслать как есть.",
        };
        return string.Join(Environment.NewLine, lines) + Environment.NewLine;
    }

    private static string StateName(ConnectionState state) => state switch
    {
        ConnectionState.Connected => "подключён",
        ConnectionState.Connecting => "подключается",
        ConnectionState.Error => "ошибка",
        _ => "выключен",
    };

    private static string Bytes(long value)
    {
        string[] names = { "Б", "КБ", "МБ", "ГБ", "ТБ" };
        double size = value;
        var step = 0;
        while (size >= 1024 && step < names.Length - 1)
        {
            size /= 1024;
            step++;
        }
        return step == 0 ? $"{value} Б" : $"{size:0.#} {names[step]}";
    }
}
