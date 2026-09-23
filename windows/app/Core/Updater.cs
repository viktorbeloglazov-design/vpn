using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;

namespace QPVPN.Core;

/// <summary>
/// Установка обновления поверх работающей программы.
///
/// Windows не даёт переписать файл запущенной программы, поэтому заменить
/// себя на ходу нельзя. Зато можно оставить после себя короткий список
/// указаний: дождаться, пока программа закроется, переложить файлы
/// и запустить её снова. Этим и занимается помощник — человеку остаётся
/// нажать одну кнопку.
/// </summary>
public static class Updater
{
    /// <summary>Что вышло из установки.</summary>
    public abstract record Outcome
    {
        /// <summary>Всё готово: программа сейчас закроется и откроется заново.</summary>
        public sealed record Restarting : Outcome;

        /// <summary>Не вышло — человеку показывается причина и папка с архивом.</summary>
        public sealed record Failed(string Reason) : Outcome;
    }

    /// <summary>
    /// Распаковывает скачанный архив и готовит замену файлов.
    /// </summary>
    /// <param name="archive">Скачанный архив со сборкой.</param>
    /// <param name="installDirectory">Папка, где лежит работающая программа.</param>
    public static Outcome Install(string archive, string installDirectory)
    {
        string staging;
        try
        {
            staging = Path.Combine(Path.GetTempPath(), "QPVPN-update-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(staging);
            ZipFile.ExtractToDirectory(archive, staging);
        }
        catch (Exception error)
        {
            return new Outcome.Failed($"Архив не распаковался: {error.Message}");
        }

        // Архив собран с папкой внутри: ищем ту, где лежит сама программа.
        var source = FindProgramDirectory(staging);
        if (source is null)
        {
            return new Outcome.Failed("В архиве не нашлось QPVPN.exe — скачайте заново.");
        }

        try
        {
            var script = WriteHelper(source, installDirectory, staging);
            Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{script}\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetTempPath(),
            });
            return new Outcome.Restarting();
        }
        catch (Exception error)
        {
            return new Outcome.Failed($"Не удалось запустить замену файлов: {error.Message}");
        }
    }

    /// <summary>Папка внутри распакованного архива, где лежит QPVPN.exe.</summary>
    public static string? FindProgramDirectory(string root)
    {
        if (File.Exists(Path.Combine(root, "QPVPN.exe"))) return root;

        return Directory.EnumerateDirectories(root, "*", SearchOption.AllDirectories)
            .FirstOrDefault(directory => File.Exists(Path.Combine(directory, "QPVPN.exe")));
    }

    /// <summary>
    /// Пишет список указаний, который выполнится после закрытия программы.
    ///
    /// Ждём именно по номеру процесса, а не просто паузу: на медленной
    /// машине программа закрывается дольше, и файлы всё ещё заняты.
    /// </summary>
    private static string WriteHelper(string source, string target, string staging)
    {
        var script = Path.Combine(Path.GetTempPath(), "QPVPN-update.cmd");
        var pid = Environment.ProcessId;

        var text = new StringBuilder();
        text.AppendLine("@echo off");
        text.AppendLine("chcp 65001 >nul");
        // Ждём закрытия программы: пока она жива, файлы заменить нельзя.
        text.AppendLine($"for /l %%i in (1,1,60) do (");
        text.AppendLine($"  tasklist /fi \"PID eq {pid}\" 2>nul | find \"{pid}\" >nul || goto :replace");
        text.AppendLine("  timeout /t 1 /nobreak >nul");
        text.AppendLine(")");
        text.AppendLine(":replace");
        // Служба туннеля держит свои файлы: снимаем её на время замены.
        text.AppendLine($"\"{Path.Combine(target, "qpvpn-tunnel.exe")}\" /uninstalltunnelservice qpvpn >nul 2>&1");
        text.AppendLine("timeout /t 2 /nobreak >nul");
        text.AppendLine($"robocopy \"{source}\" \"{target}\" /e /is /it /r:3 /w:1 >nul");
        text.AppendLine($"start \"\" \"{Path.Combine(target, "QPVPN.exe")}\"");
        // Прибираем за собой: временная папка и сам этот файл.
        text.AppendLine($"rmdir /s /q \"{staging}\" >nul 2>&1");
        text.AppendLine("del \"%~f0\" >nul 2>&1");

        File.WriteAllText(script, text.ToString(), Encoding.UTF8);
        return script;
    }
}
