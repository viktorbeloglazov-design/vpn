using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;

namespace QPVPN.Core;

/// <summary>
/// Проверка и скачивание обновления.
///
/// Приложение ставится архивом с сайта, мимо магазина, поэтому напомнить о
/// новой версии некому — делаем это сами. Рядом со сборкой лежит файл с
/// номером версии строкой: он весит десяток байт.
///
/// Ссылки постоянные: имя файла без номера, выпуск с меткой latest.
/// </summary>
public static class UpdateCheck
{
    private const string Base =
        "https://github.com/viktorbeloglazov-design/vpn/releases/download/latest";

    private const string VersionUrl = Base + "/windows-version.txt";
    private const string ArchiveUrl = Base + "/QPVPN-windows.zip";

    /// <summary>Раз в сутки — чаще незачем, реже можно пропустить важное.</summary>
    public static readonly TimeSpan CheckInterval = TimeSpan.FromDays(1);

    /// <summary>Свежая версия на сервере, либо null — узнать не вышло.</summary>
    public static async Task<string?> LatestVersionAsync()
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            var text = (await client.GetStringAsync(VersionUrl).ConfigureAwait(false)).Trim();
            return text.Length > 0 && char.IsDigit(text[0]) ? text : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>Скачивает архив во временный каталог. null — не вышло.</summary>
    public static async Task<string?> DownloadAsync(IProgress<int>? progress = null)
    {
        var target = Path.Combine(Path.GetTempPath(), "QPVPN-update.zip");
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
            using var response = await client
                .GetAsync(ArchiveUrl, HttpCompletionOption.ResponseHeadersRead)
                .ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return null;

            var expected = response.Content.Headers.ContentLength ?? 0;
            await using var source = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
            await using (var file = File.Create(target))
            {
                var buffer = new byte[64 * 1024];
                long done = 0;
                while (true)
                {
                    var read = await source.ReadAsync(buffer).ConfigureAwait(false);
                    if (read <= 0) break;
                    await file.WriteAsync(buffer.AsMemory(0, read)).ConfigureAwait(false);
                    done += read;
                    if (expected > 0) progress?.Report((int)(done * 100 / expected));
                }

                // Оборванная закачка даёт битый архив: лучше сразу считать
                // её неудачей, чем разбирать невнятную ошибку распаковки.
                if (expected > 0 && done < expected)
                {
                    file.Close();
                    File.Delete(target);
                    return null;
                }
            }
            return target;
        }
        catch (Exception)
        {
            try { File.Delete(target); } catch (Exception) { }
            return null;
        }
    }

    /// <summary>
    /// Свежее ли «1.2.10», чем «1.2.9».
    ///
    /// Сравниваем числами по частям: по буквам «10» оказалось бы меньше «9».
    /// </summary>
    public static bool IsNewer(string candidate, string current)
    {
        var left = Parts(candidate);
        var right = Parts(current);
        for (var index = 0; index < Math.Max(left.Length, right.Length); index++)
        {
            var a = index < left.Length ? left[index] : 0;
            var b = index < right.Length ? right[index] : 0;
            if (a != b) return a > b;
        }
        return false;
    }

    private static int[] Parts(string version)
    {
        var pieces = version.Trim().Split('.', '-', '+');
        var result = new int[pieces.Length];
        for (var index = 0; index < pieces.Length; index++)
        {
            var digits = "";
            foreach (var symbol in pieces[index])
            {
                if (!char.IsDigit(symbol)) break;
                digits += symbol;
            }
            result[index] = digits.Length > 0 ? int.Parse(digits) : 0;
        }
        return result;
    }
}
