using System;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace QPVPN.Core;

/// <summary>
/// Проверка, что через туннель проходят большие порции данных.
///
/// Слишком большой пакет — самая частая причина жалоб вида «сообщения
/// отправляются, а видео крутится и не скачивается». Мелкие пакеты
/// пролезают, крупные сеть не пропускает целиком, и каждая порция уходит
/// заново: связь вроде есть, а толку нет.
/// </summary>
public static class BulkCheck
{
    private const int Needed = 128 * 1024;
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(9);

    private static readonly string[] Sources =
    {
        "https://speed.cloudflare.com/__down?bytes=1000000",
        "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png",
        "https://raw.githubusercontent.com/viktorbeloglazov-design/vpn/main/README.md",
    };

    private enum Outcome { Ok, Stalled, Unreachable }

    /// <summary>Проходят ли большие порции. false — пакет стоит уменьшить.</summary>
    public static async Task<bool> WorksAsync()
    {
        foreach (var source in Sources)
        {
            switch (await DownloadAsync(source).ConfigureAwait(false))
            {
                case Outcome.Ok: return true;
                case Outcome.Stalled: return false;
                default: continue;
            }
        }
        // Ни один источник не отозвался: проблема не в размере пакета,
        // и уменьшать его вслепую незачем.
        return true;
    }

    private static async Task<Outcome> DownloadAsync(string url)
    {
        using var handler = new SocketsHttpHandler { UseProxy = false };
        using var client = new HttpClient(handler);
        using var cancel = new CancellationTokenSource(Timeout + TimeSpan.FromSeconds(3));

        try
        {
            using var response = await client
                .GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancel.Token)
                .ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return Outcome.Unreachable;

            var expected = response.Content.Headers.ContentLength ?? 0;
            await using var stream = await response.Content.ReadAsStreamAsync(cancel.Token).ConfigureAwait(false);

            var watch = Stopwatch.StartNew();
            var buffer = new byte[32 * 1024];
            long total = 0;

            while (total < Needed && watch.Elapsed < Timeout)
            {
                var read = await stream.ReadAsync(buffer, cancel.Token).ConfigureAwait(false);
                if (read <= 0) break;
                total += read;
            }

            // Файл кончился раньше — значит, он просто небольшой и дошёл целиком.
            return total >= Needed || (expected > 0 && total >= expected)
                ? Outcome.Ok
                : Outcome.Stalled;
        }
        catch (OperationCanceledException)
        {
            // Соединение установилось, а данные не идут — это как раз оно.
            return Outcome.Stalled;
        }
        catch (Exception)
        {
            return Outcome.Unreachable;
        }
    }
}
