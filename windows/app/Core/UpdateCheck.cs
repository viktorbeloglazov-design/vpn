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

    /// <summary>Куда отправить человека, если спросить сервер не вышло.</summary>
    public const string PageUrl = ArchiveUrl;

    /// <summary>
    /// Сколько раз спросить, прежде чем сдаться.
    ///
    /// Канал, по которому раздаются сборки, рвётся: одна неудачная попытка
    /// ничего не значит, а человек из-за неё остаётся на старой версии.
    /// </summary>
    private const int Attempts = 3;

    /// <summary>Раз в сутки — чаще незачем, реже можно пропустить важное.</summary>
    public static readonly TimeSpan CheckInterval = TimeSpan.FromDays(1);

    /// <summary>Свежая версия на сервере, либо null — узнать не вышло.</summary>
    public static async Task<string?> LatestVersionAsync()
    {
        for (var attempt = 1; attempt <= Attempts; attempt++)
        {
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
                // Ответ не должен браться из кэша: иначе программа будет
                // видеть вчерашний номер версии и молчать про новую.
                client.DefaultRequestHeaders.CacheControl =
                    new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };

                var text = (await client.GetStringAsync(VersionUrl).ConfigureAwait(false)).Trim();
                if (text.Length > 0 && char.IsDigit(text[0])) return text;
            }
            catch (Exception)
            {
                // Обрыв — обычное дело для этого канала. Пробуем ещё.
            }

            if (attempt < Attempts) await Task.Delay(1500 * attempt).ConfigureAwait(false);
        }
        return null;
    }

    /// <summary>
    /// Скачивает архив, продолжая с места обрыва. null — не вышло.
    ///
    /// Канал, по которому раздаются сборки, рвётся на больших файлах,
    /// а архив весит шестьдесят мегабайт. Закачка с нуля в таком канале
    /// не доходит никогда, поэтому недостающее дописывается.
    /// </summary>
    public static async Task<string?> DownloadAsync(IProgress<int>? progress = null)
    {
        var target = Path.Combine(Path.GetTempPath(), "QPVPN-update.zip");
        long total = 0;
        // Метка версии файла на сервере: с ней сервер сам решит, можно ли
        // дописывать, или сборку успели заменить и нужна она целиком.
        string? tag = null;

        for (var attempt = 1; attempt <= 8; attempt++)
        {
            var have = File.Exists(target) ? new FileInfo(target).Length : 0;
            if (total > 0 && have >= total) return Verify(target, total);

            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
                using var request = new HttpRequestMessage(HttpMethod.Get, ArchiveUrl);
                if (have > 0)
                {
                    request.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(have, null);
                    if (tag is not null)
                    {
                        request.Headers.TryAddWithoutValidation("If-Range", tag);
                    }
                }

                using var response = await client
                    .SendAsync(request, HttpCompletionOption.ResponseHeadersRead)
                    .ConfigureAwait(false);
                if (!response.IsSuccessStatusCode) continue;

                // 206 — сервер дописывает с нужного места. 200 — отдаёт файл
                // целиком, значит написанное раньше надо выбросить.
                var appending = response.StatusCode == System.Net.HttpStatusCode.PartialContent && have > 0;
                if (!appending && have > 0) File.Delete(target);

                tag ??= response.Headers.ETag?.ToString()
                    ?? response.Content.Headers.LastModified?.ToString("R");

                var startAt = appending ? have : 0;
                var length = response.Content.Headers.ContentLength ?? 0;
                if (total == 0 || !appending) total = length > 0 ? length + startAt : 0;

                await using var source = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
                await using (var file = new FileStream(target, appending ? FileMode.Append : FileMode.Create,
                                                       FileAccess.Write, FileShare.None))
                {
                    var buffer = new byte[64 * 1024];
                    var done = startAt;
                    while (true)
                    {
                        var read = await source.ReadAsync(buffer).ConfigureAwait(false);
                        if (read <= 0) break;
                        await file.WriteAsync(buffer.AsMemory(0, read)).ConfigureAwait(false);
                        done += read;
                        if (total > 0) progress?.Report((int)(done * 100 / total));
                    }

                    if (total == 0 || done >= total)
                    {
                        file.Close();
                        return Verify(target, total);
                    }
                }
            }
            catch (Exception)
            {
                // Обрыв посередине — ожидаемое поведение этого канала,
                // а не повод стереть уже скачанное.
            }

            await Task.Delay(Math.Min(1500 * attempt, 6000)).ConfigureAwait(false);
        }

        try { File.Delete(target); } catch (Exception) { }
        return null;
    }

    /// <summary>
    /// Проверяет, что скачан архив, а не страница с ошибкой.
    /// </summary>
    private static string? Verify(string path, long expected)
    {
        try
        {
            var info = new FileInfo(path);
            if (expected > 0 && info.Length != expected) { info.Delete(); return null; }

            // ZIP всегда начинается с этих двух букв.
            using var stream = File.OpenRead(path);
            var head = new byte[2];
            if (stream.Read(head, 0, 2) != 2 || head[0] != (byte)'P' || head[1] != (byte)'K')
            {
                stream.Close();
                File.Delete(path);
                return null;
            }
            return path;
        }
        catch (Exception)
        {
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
